import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'clips_screen.dart';
import '../core/social.dart';
import '../core/binge.dart';
import '../core/api_service.dart';
import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../core/hls_quality.dart';
import '../core/stream_resolver.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/download_button.dart';
import '../widgets/quick_share.dart';
import '../widgets/player_gestures.dart';
import '../core/app_prefs.dart';
import '../core/library_store.dart';

/// In-app episode player — **native playback**.
///
/// The selected server is resolved into a direct media URL (progressive MP4
/// or HLS) through [StreamResolver] and played by the platform's own player
/// (ExoPlayer on Android) via `video_player` — no WebView anywhere.
/// Fallback: if a server cannot be resolved, the next one is tried
/// automatically. Demo titles (offline fallback) keep the mock playback UI.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late Anime _anime;
  Episode? _episode;
  List<Episode> _episodes = const <Episode>[];

  Future<List<EpisodeServer>>? _serversFuture;
  List<EpisodeServer> _servers = const <EpisodeServer>[];
  String _serverKind = 'sub';
  EpisodeServer? _server;

  VideoPlayerController? _player;
  ResolvedStream? _stream;
  bool _resolving = false;
  String? _error;
  String _status = '';

  bool _landscape = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  double _speed = 1.0;

  // --- Gesture / QoL features ---------------------------------------------
  bool _locked = false; // control lock (see PlayerGestureOverlay)
  bool _loop = false; // loop current episode
  Timer? _sleepTimer; // sleep timer → pauses playback
  int _sleepMinutes = 0; // 0 = off
  bool _introSkipped = false; // auto-skip applied for current stream

  /// Mid-stream recovery state (see [_onStreamDied]).
  bool _recovering = false;
  int _streamRetries = 0;

  /// True while the user is dragging the seek bar (position updates from the
  /// player are ignored so the thumb does not fight the finger).
  bool _dragging = false;
  double _dragValue = 0;

  static const MethodChannel _channel = MethodChannel('animax/app');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anime = const Anime(
        id: '',
        title: '',
        poster: '',
        score: 0,
        year: '',
        genres: <String>[],
        synopsis: '');
  }

  /// Pause playback when the app goes to the background (audio kept playing
  /// before, and the surface could go black on return).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (c.value.isPlaying) c.pause();
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Object? args = ModalRoute.of(context)!.settings.arguments;
    Anime anime;
    Episode? ep;
    if (args is (Anime, Episode?)) {
      anime = args.$1;
      ep = args.$2;
    } else if (args is Anime) {
      anime = args;
    } else {
      anime = _anime;
    }
    if (anime.id != _anime.id) {
      _anime = anime;
      _episode = ep;
      _server = null;
      _stream = null;
      _error = null;
      _status = '';
      _serversFuture = _loadServers();
      _loadEpisodeList();
      // Fire-and-forget view count, exactly like the site's own pages.
      final String? wid = anime.watchId;
      if (anime.isRemote && wid != null) {
        unawaited(ApiService.I.recordView(wid));
      }
      // Auto-resolve the default server once the list arrives.
      unawaited(_autoResolve());
    } else if (ep != null && ep.number != _episode?.number) {
      _switchEpisode(ep);
    }
  }

  Future<void> _loadEpisodeList() async {
    if (!_anime.isRemote) return;
    try {
      final List<Episode> eps = await AppState.I.episodesFor(_anime);
      if (mounted) setState(() => _episodes = eps);
    } catch (_) {
      // Navigation simply stays unavailable.
    }
  }

  Future<List<EpisodeServer>> _loadServers() async {
    final String? wid = _anime.watchId;
    if (!_anime.isRemote || wid == null || _episode == null) {
      return const <EpisodeServer>[];
    }
    try {
      final List<EpisodeServer> list = await ApiService.I
          .fetchServers(wid, '${_episode!.number}')
          .timeout(const Duration(seconds: 12));
      if (mounted) setState(() => _servers = list);
      return list;
    } catch (_) {
      return const <EpisodeServer>[];
    }
  }

  /// Picks the best server of the selected kind and starts playback,
  /// falling through the remaining servers until one resolves.
  Future<void> _autoResolve() async {
    final List<EpisodeServer>? servers = await _serversFuture;
    if (!mounted || servers == null || servers.isEmpty) return;
    final List<String> kinds =
        servers.map((EpisodeServer s) => s.kind).toSet().toList();
    if (!kinds.contains(_serverKind) && kinds.isNotEmpty) {
      _serverKind = kinds.first;
    }
    // Preferred kind first, then every other server as fallback.
    final List<EpisodeServer> order = <EpisodeServer>[
      ...servers.where((EpisodeServer s) => s.kind == _serverKind),
      ...servers.where((EpisodeServer s) => s.kind != _serverKind),
    ];
    await _playThrough(order);
  }

  /// Tries [order] sequentially until one server yields a playable stream.
  Future<void> _playThrough(List<EpisodeServer> order) async {
    for (int i = 0; i < order.length; i++) {
      final EpisodeServer candidate = order[i];
      final List<EpisodeServer> rest = order.sublist(i + 1);
      if (await _resolveAndPlay(candidate, rest: rest)) return;
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() {
      _resolving = false;
      _error = 'لا يوجد سيرفر يستجيب حاليًا.\n'
          'جرّب سيرفرًا آخر أو مسارًا صوتيًا مختلفًا بالأسفل.';
    });
  }

  /// Resolves [server] into a direct stream and starts the native player.
  /// Returns false when the server is unusable ([rest] is the remaining
  /// fallback list shown in the status line).
  Future<bool> _resolveAndPlay(EpisodeServer server,
      {List<EpisodeServer> rest = const <EpisodeServer>[]}) async {
    if (!mounted) return true;
    setState(() {
      _server = server;
      _resolving = true;
      _error = null;
      _status = 'جارٍ تحميل ${server.name}…';
    });
    final ResolvedStream? rs =
        await StreamResolver.I.resolve(server).timeout(
              const Duration(seconds: 20),
              onTimeout: () => null,
            );
    if (!mounted) return true;
    if (rs == null) {
      setState(() {
        _resolving = false;
        _status = '${server.name} غير متاح — جارٍ تجربة السيرفر التالي…';
      });
      return false;
    }
    final bool ok = await _startPlayer(rs);
    if (!mounted) return true;
    if (!ok) {
      // Player could not open this stream — fall through to the next server.
      setState(() {
        _stream = null;
        _resolving = false;
        _status = '${server.name} لم يستجب — جارٍ تجربة السيرفر التالي…';
      });
      return false;
    }
    setState(() {
      _status = '';
      _resolving = false;
    });
    return true;
  }

  /// Creates the [VideoPlayerController] for [rs] and starts playback.
  /// Keeps the current position when switching quality mid-play.
  /// Returns false when the stream cannot be opened (caller falls back to
  /// the next server).
  Future<bool> _startPlayer(ResolvedStream rs, {Duration? resumeAt}) async {
    final VideoPlayerController? old = _player;
    final Duration pos = resumeAt ??
        (old != null && old.value.isInitialized
            ? old.value.position
            : Duration.zero);
    await _disposePlayer();
    final Map<String, String> headers = <String, String>{
      'User-Agent': _browserUa,
      if (rs.referer.isNotEmpty) 'Referer': rs.referer,
    };
    // Bandwidth-based auto quality: for HLS master playlists pick the variant
    // that fits the measured throughput (Wi-Fi/cellular aware) and expose all
    // variants in the quality menu. Non-HLS or already-discrete streams pass
    // through untouched.
    ResolvedStream effective = rs;
    try {
      effective = await HlsQuality.autoSelect(rs, headers: headers);
    } catch (_) {}
    if (_stream != null && effective.url != rs.url) {
      setState(() => _stream = effective);
    }
    // The backend's HLS playlists are served from URLs like
    // `/cdn/{hash}?t.m3u8&v.m3u8` — the .m3u8 marker lives only in the QUERY
    // string, so ExoPlayer cannot infer HLS from the path and would try to
    // parse the playlist as progressive media (fails with an error). The
    // explicit format hint fixes exactly that case.
    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      Uri.parse(effective.url),
      httpHeaders: headers,
      formatHint: effective.isHls ? VideoFormat.hls : VideoFormat.other,
    );
    _player = controller;
    controller.addListener(() => _playerListener(controller));
    setState(() {}); // attach early so buffering state is visible
    try {
      await controller.initialize();
    } catch (_) {
      if (!mounted) return false;
      await _disposePlayer();
      setState(() {
        _resolving = false;
      });
      return false;
    }
    if (!mounted) {
      await controller.dispose();
      return false;
    }
    if (pos > Duration.zero) {
      try {
        await controller.seekTo(pos);
      } catch (_) {}
    }
    controller.setVolume(_muted ? 0 : 1);
    if (_speed != 1.0) controller.setPlaybackSpeed(_speed);
    Binge.started('anime:${_anime.id}#${_episode?.number ?? 0}');
    unawaited(Social.countView('anime:${_anime.id}',
        title: _anime.title, poster: _anime.poster, kind: 'anime'));
    await controller.play();
    _setKeepScreenOn(true);
    _bumpControls();
    setState(() {}); // attach the (now ready) controller
    _introSkipped = false;
    // Library bookkeeping: history row + stored resume position.
    if (_anime.id.isNotEmpty) {
      LibraryStore.I.pushHistory(
        key: 'anime:${_anime.id}',
        title: _anime.title,
        poster: _anime.poster,
        kind: 'anime',
        sub: '${_episode?.number ?? 1}',
        label: 'الحلقة ${_episode?.number ?? 1}',
      );
    }
    return true;
  }

  /// Runtime listener for the active controller: catches mid-playback errors
  /// (expired stream URL, network drop) and auto-advances on completion.
  void _playerListener(VideoPlayerController c) {
    if (!mounted || _player != c) return;
    final VideoPlayerValue v = c.value;
    if (v.hasError && !_resolving) {
      _onStreamDied(v.errorDescription ?? 'خطأ غير معروف');
      return;
    }
    // Auto-skip intro (Settings → Player → Auto-skip intro).
    if (!_introSkipped &&
        (AppPrefs.I.autoSkipIntro || Binge.on) &&
        _stream != null &&
        _stream!.hasIntro &&
        v.position.inSeconds >= _stream!.introStart &&
        v.position.inSeconds < _stream!.introEnd) {
      _introSkipped = true;
      c.seekTo(Duration(seconds: _stream!.introEnd));
    }
    if (v.isCompleted && !_resolving) {
      if (_loop) {
        c.seekTo(Duration.zero);
        c.play();
        return;
      }
      Binge.episodeEnded(context,
          episodeKey: 'anime:${_anime.id}#${_episode?.number ?? 0}',
          next: _hasNextEpisode && (AppPrefs.I.autoPlayNext || Binge.on)
              ? () => _autoNextEpisode(force: true)
              : null);
    }
  }

  /// True when a next episode exists in the loaded list.
  bool get _hasNextEpisode {
    if (_episode == null || _episodes.isEmpty) return false;
    final int i =
        _episodes.indexWhere((Episode e) => e.number == _episode!.number);
    return i >= 0 && i + 1 < _episodes.length;
  }

  void _autoNextEpisode({bool force = false}) {
    if (!force && !AppPrefs.I.autoPlayNext) return;
    if (!_hasNextEpisode) return;
    final int i =
        _episodes.indexWhere((Episode e) => e.number == _episode!.number);
    _switchEpisode(_episodes[i + 1]);
  }

  /// Mid-stream failure recovery: re-resolve the same server (signed URLs can
  /// expire), preserving the position; after repeated failures fall through
  /// to the next server instead of freezing on a black frame.
  Future<void> _onStreamDied(String detail) async {
    if (_recovering) return;
    _recovering = true;
    try {
      _streamRetries++;
      final Duration pos = _player?.value.position ?? Duration.zero;
      if (_streamRetries <= 2) {
        await _disposePlayer();
        if (!mounted) return;
        setState(() {
          _resolving = true;
          _status = '';
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        _recovering = false;
        final bool ok = await _startPlayer(
          _stream ?? const ResolvedStream(url: ''),
          resumeAt: pos,
        );
        if (ok && mounted) {
          setState(() {
            _resolving = false;
          });
        }
        return;
      }
      // Same server keeps failing — try the next one.
      final EpisodeServer? current = _server;
      final List<EpisodeServer> rest = <EpisodeServer>[
        ..._servers.where((EpisodeServer s) =>
            s != current && s.kind == _serverKind),
        ..._servers.where((EpisodeServer s) =>
            s != current && s.kind != _serverKind),
      ];
      if (rest.isNotEmpty) {
        await _disposePlayer();
        if (!mounted) return;
        _streamRetries = 0;
        _recovering = false;
        setState(() {
          _resolving = true;
          _status = 'جارٍ تبديل السيرفر…';
        });
        await _resolveAndPlay(rest.first, rest: rest.sublist(1));
        return;
      }
      _recovering = false;
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = 'فشل التشغيل: $detail';
        });
      }
    } catch (_) {
      _recovering = false;
    }
  }

  Future<void> _disposePlayer() async {
    final VideoPlayerController? c = _player;
    _player = null;
    try {
      await c?.dispose();
    } catch (_) {}
  }

  /// Queues the episode at the quality currently playing.
  Future<void> _download() async {
    final ResolvedStream? rs = _stream;
    if (rs == null) return;
    await DownloadManager.I.addVideo(
      title: _anime.title,
      subtitle: 'الحلقة ${_episode?.number ?? 1}',
      poster: _anime.poster,
      url: rs.url,
      headers: <String, String>{
        'User-Agent': _browserUa,
        if (rs.referer.isNotEmpty) 'Referer': rs.referer,
      },
      isHls: rs.isHls,
    );
  }

  Future<void> _switchQuality(String url) async {
    final ResolvedStream? rs = _stream;
    if (rs == null || _player == null || url == rs.url) return;
    final Duration pos =
        _player!.value.isInitialized ? _player!.value.position : Duration.zero;
    final ResolvedStream next = ResolvedStream(
      url: url,
      qualities: rs.qualities,
      introStart: rs.introStart,
      introEnd: rs.introEnd,
      referer: rs.referer,
    );
    setState(() => _stream = next);
    await _startPlayer(next, resumeAt: pos);
  }

  void _switchEpisode(Episode ep) {
    if (ep.number == _episode?.number) return;
    setState(() {
      _episode = ep;
      _server = null;
      _stream = null;
      _error = null;
      _status = '';
      _serversFuture = _loadServers();
    });
    final String? wid = _anime.watchId;
    if (_anime.isRemote && wid != null) {
      unawaited(ApiService.I.recordView(wid));
    }
    unawaited(_autoResolve());
  }

  Future<void> _openInBrowser() async {
    final String url = _anime.watchUrl(
        base: ApiService.I.config.cleanBase, ep: _episode?.number);
    try {
      await _channel
          .invokeMethod<bool>('openUrl', <String, String>{'url': url});
    } on PlatformException {
      // Channel unavailable (e.g. tests) — nothing else to do here.
    } catch (_) {}
  }

  void _setKeepScreenOn(bool keep) {
    _channel
        .invokeMethod<bool>('setKeepScreenOn', <String, dynamic>{'keep': keep})
        .catchError((Object e) => false);
  }

  // ----- Controls helpers -----

  void _bumpControls() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    final bool playing = _player?.value.isInitialized == true &&
        _player!.value.isPlaying;
    if (playing) {
      _hideTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  void _togglePlay() {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    } else {
      c.play();
      _bumpControls();
    }
    setState(() {});
  }

  /// Seek-bar scrubbing (called from the overlay widgets).
  void dragTo(double ms) {
    if (!mounted) return;
    setState(() {
      _dragging = true;
      _dragValue = ms;
    });
  }

  /// Seek released — apply the position once.
  void endDrag(VideoPlayerController player, double ms) {
    _dragging = false;
    player.seekTo(Duration(milliseconds: ms.round()));
    _bumpControls();
  }

  /// Public so the stage widgets (same file) can drop the overlay without
  /// touching [State.setState] directly.
  void hideControls() {
    _hideTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = false);
  }

  Future<void> _seekRel(int seconds) async {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    Duration target = c.value.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (c.value.duration > Duration.zero && target > c.value.duration) {
      target = c.value.duration;
    }
    await c.seekTo(target);
    _bumpControls();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player?.setVolume(_muted ? 0 : 1);
    _bumpControls();
  }

  bool _muted = false;

  // ---- Gesture / QoL handlers ---------------------------------------------

  void _toggleLock() {
    setState(() => _locked = !_locked);
    if (_locked) {
      _hideTimer?.cancel();
    } else {
      _bumpControls();
    }
  }

  void _toggleLoop() {
    setState(() => _loop = !_loop);
    _bumpControls();
  }

  void _onSpeedBoost(bool active) {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    c.setPlaybackSpeed(active ? 2.0 : _speed);
    if (!active) _bumpControls();
  }

  void _onVolume(double value) {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    c.setVolume(value);
    if (value > 0 && _muted) {
      setState(() => _muted = false);
    }
  }

  void _onSeek(int seconds) => _seekRel(seconds);

  Future<void> _enterPip() async {
    final bool ok = await enterPipMode();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'خاصية صورة داخل صورة غير متاحة على هذا الجهاز أو إصدار أندرويد.')));
    }
  }

  void _pickSleepTimer() {
    const List<int> options = <int>[0, 15, 30, 45, 60, 90];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('مؤقت النوم',
                  style: TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
            ),
            for (final int m in options)
              ListTile(
                leading: Icon(
                    m == 0
                        ? Icons.timer_off_rounded
                        : Icons.nightlight_round,
                    color: _sleepMinutes == m
                        ? AppColors.accent
                        : AppColors.muted,
                    size: 20),
                title: Text(m == 0 ? 'إيقاف' : '$m دقيقة',
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 13.5,
                        color: _sleepMinutes == m
                            ? AppColors.accent
                            : AppColors.text)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _setSleepTimer(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepMinutes = minutes);
    if (minutes == 0) return;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      if (mounted && _player?.value.isPlaying == true) {
        _player!.pause();
        if (mounted) {
          setState(() => _controlsVisible = true);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'مؤقت النوم — توقف التشغيل بعد $minutes دقيقة')));
        }
      }
      if (mounted) setState(() => _sleepMinutes = 0);
    });
  }

  void _setSpeed(double v) {
    setState(() => _speed = v);
    _player?.setPlaybackSpeed(v);
    _bumpControls();
  }

  void _toggleOrientation() {
    setState(() => _landscape = !_landscape);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      if (_landscape) ...<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ] else
        DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      _landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    _bumpControls();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _sleepTimer?.cancel();
    SystemBrightness.reset();
    _saveProgressSnapshot();
    _setKeepScreenOn(false);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    final VideoPlayerController? c = _player;
    _player = null;
    c?.dispose();
    super.dispose();
  }

  /// Persists the exact resume position for this episode and records a
  /// history row — used by Continue Watching / History / stats.
  void _saveProgressSnapshot() {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized || _anime.id.isEmpty) return;
    LibraryStore.I.saveProgress(
      key: 'anime:${_anime.id}',
      sub: '${_episode?.number ?? 1}',
      positionSec: c.value.position.inSeconds,
      durationSec: c.value.duration.inSeconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final int epNum = _episode?.number ?? 1;
    final String epTitle = _episode?.title ?? 'الحلقة $epNum';

    final Widget stage = _VideoStage(
      state: this,
      episodeLabel: epTitle,
    );

    if (_landscape) {
      // Immersive fullscreen stage.
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: stage),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- Top bar ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  IconBubble(Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_anime.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppText.bodyBold.copyWith(fontSize: 13.5)),
                        Text(
                          _episode == null
                              ? 'فيلم • المشغّل الأصلي'
                              : 'الحلقة $epNum • المشغّل الأصلي',
                          style: AppText.label.copyWith(fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconBubble(Icons.screen_rotation_rounded,
                      onTap: _toggleOrientation),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ---------- Stage ----------
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: Colors.black,
                  child: stage,
                ),
              ),
            )),

            // ---------- Episode title ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('يُعرض الآن',
                      style: AppText.label.copyWith(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(epTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.h3.copyWith(fontSize: 16)),
                ],
              ),
            ),

            // ---------- Servers / navigation panel ----------
            _ServersPanel(
              future: _serversFuture,
              kind: _serverKind,
              activeServer: _server,
              status: _status,
              onKind: (String k) {
                setState(() => _serverKind = k);
                _autoResolve();
              },
              onPick: (EpisodeServer s) => _playThrough(<EpisodeServer>[
                s,
                ..._servers.where((EpisodeServer x) => x != s),
              ]),
              episode: _episode,
              episodes: _episodes,
              onSwitch: _switchEpisode,
            ),
          ],
        ),
      ),
    );
  }
}

/// Browser-mirrored UA — also used as the player's request header.
const String _browserUa =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

// ---------------------------------------------------------------------------
// Video stage — native VideoPlayer + Animax-styled overlay controls
// ---------------------------------------------------------------------------

/// Renders [PlayerScreenState]'s video. The parent state owns the
/// controller; this widget subscribes to it and paints the overlay.
class _VideoStage extends StatelessWidget {
  const _VideoStage({required this.state, required this.episodeLabel});

  final _PlayerScreenState state;
  final String episodeLabel;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = state._player;
    final ResolvedStream? stream = state._stream;

    // Error (nothing loaded).
    if (state._error != null) {
      return _StageMessage(
        icon: Icons.error_outline_rounded,
        title: 'مشكلة في التشغيل',
        message: state._error!,
        actions: [
          if (stream != null || state._server != null)
            GhostChip(
              label: 'حاول مجددًا',
              active: true,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              onTap: () {
                final EpisodeServer? s = state._server;
                if (s != null) {
                  state._playThrough(<EpisodeServer>[s, ...state._servers
                      .where((EpisodeServer x) => x != s)]);
                } else {
                  state._autoResolve();
                }
              },
            ),
          GhostChip(
            label: 'فتح في المتصفح',
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            onTap: state._openInBrowser,
          ),
        ],
      );
    }

    // Resolving.
    if (state._resolving && player == null) {
      return _StageMessage(
        icon: Icons.hourglass_top_rounded,
        title: 'جارٍ التحميل…',
        message: state._status.isEmpty
            ? 'جارٍ تجهيز الفيديو.'
            : state._status,
        busy: true,
      );
    }

    // Waiting for a server pick (no servers auto-resolved yet).
    if (player == null || !player.value.isInitialized) {
      if (player == null) {
        return _StageMessage(
          icon: Icons.play_circle_outline_rounded,
          title: 'اختر سيرفرًا',
          message: state._status.isEmpty
              ? 'اختر سيرفرًا (مترجم / مدبلج) بالأسفل لبدء المشاهدة.'
              : state._status,
        );
      }
      return const _StageMessage(
        icon: Icons.hourglass_top_rounded,
        title: 'جارٍ التخزين المؤقت…',
        message: 'جارٍ فتح البث.',
        busy: true,
      );
    }

    // Live surface — rebuilds on every controller tick (position, buffering).
    return ListenableBuilder(
      listenable: player,
      builder: (BuildContext context, _) {
        final VideoPlayerValue v = player.value;
        final bool showIntro = stream != null &&
            stream.hasIntro &&
            v.position.inSeconds >= stream.introStart &&
            v.position.inSeconds < stream.introEnd;

        return Stack(
          fit: StackFit.expand,
          children: [
            // --- Video surface with gesture layer ---
            PlayerGestureOverlay(
              onTap: () {
                if (state._controlsVisible && v.isPlaying) {
                  state.hideControls();
                } else {
                  state._bumpControls();
                }
              },
              onSeek: state._onSeek,
              onSpeedBoost: state._onSpeedBoost,
              onVolume: state._onVolume,
              onBrightness: (double _) {},
              locked: state._locked,
              onLockTap: state._toggleLock,
              child: Center(
                child: AspectRatio(
                  aspectRatio: v.aspectRatio <= 0 ? 16 / 9 : v.aspectRatio,
                  child: VideoPlayer(player),
                ),
              ),
            ),

            // --- Buffering spinner ---
            if (v.isBuffering)
              Center(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                      color: AppColors.accent, strokeWidth: 2.6),
                ),
              ),

            // --- Controls overlay ---
            AnimatedOpacity(
              opacity: state._controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !state._controlsVisible,
                child: Column(
                  children: [
                    _TopGradientBar(state: state, episodeLabel: episodeLabel),
                    const Spacer(),
                    if (showIntro)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: AlignmentDirectional.bottomEnd,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: GhostChip(
                              label: 'تخطّي المقدمة',
                              active: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 9),
                              onTap: () => player
                                  .seekTo(Duration(seconds: stream.introEnd)),
                            ),
                          ),
                        ),
                      ),
                    _BottomControls(state: state, value: v),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopGradientBar extends StatelessWidget {
  const _TopGradientBar({required this.state, required this.episodeLabel});

  final _PlayerScreenState state;
  final String episodeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (state._landscape) {
                state._toggleOrientation();
              } else {
                Navigator.pop(context);
              }
            },
            child:
                const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state._anime.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(episodeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 10.5,
                        color: Colors.white70)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              state._muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: state._toggleMute,
          ),
          IconButton(
            icon: Icon(
              state._loop ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              color: state._loop ? AppColors.accent : Colors.white,
              size: 21,
            ),
            tooltip: 'تكرار الحلقة',
            onPressed: state._toggleLoop,
          ),
          IconButton(
            icon: Icon(
              Icons.nightlight_round,
              color: state._sleepMinutes > 0 ? AppColors.accent : Colors.white,
              size: 21,
            ),
            tooltip: 'مؤقت النوم',
            onPressed: state._pickSleepTimer,
          ),
          IconButton(
            icon: const Icon(Icons.picture_in_picture_rounded,
                color: Colors.white, size: 20),
            tooltip: 'صورة داخل صورة',
            onPressed: state._enterPip,
          ),
          IconButton(
            icon: Icon(
              state._locked
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
              color: state._locked ? AppColors.accent : Colors.white,
              size: 20,
            ),
            tooltip: state._locked ? 'فتح القفل' : 'قفل التحكم',
            onPressed: state._toggleLock,
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.state, required this.value});

  final _PlayerScreenState state;
  final VideoPlayerValue value;

  static String _fmt(Duration d) {
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController player = state._player!;
    final Duration pos = value.position;
    final Duration dur = value.duration;
    final double max = dur.inMilliseconds > 0
        ? dur.inMilliseconds.toDouble()
        : 1.0;
    final ResolvedStream? stream = state._stream;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 26, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- Center row: seek 10s + play/pause ---
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10_rounded,
                    color: Colors.white, size: 30),
                onPressed: () => state._seekRel(-10),
              ),
              const SizedBox(width: 22),
              InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: state._togglePlay,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 22),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded,
                    color: Colors.white, size: 30),
                onPressed: () => state._seekRel(10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // --- Seek bar ---
          Row(
            children: [
              Text(_fmt(pos),
                  style: const TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 10.5,
                      color: Colors.white)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 13),
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: AppColors.accent,
                    overlayColor: AppColors.accent.withValues(alpha: 0.25),
                  ),
                  child: Slider(
                    // Scrub-safe: dragging only moves the thumb, the real
                    // seekTo fires once on release (ExoPlayer stutters when
                    // seeked on every drag tick).
                    value: state._dragging
                        ? state._dragValue
                        : pos.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                    max: max,
                    onChanged: (double ms) {
                      state.dragTo(ms);
                    },
                    onChangeEnd: (double ms) {
                      state.endDrag(player, ms);
                    },
                  ),
                ),
              ),
              Text(_fmt(dur),
                  style: const TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 10.5,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 2),
          // --- Bottom row: quality / speed / fullscreen ---
          Row(
            children: [
              if (stream != null && stream.hasQualities)
                _OverlayMenuButton(
                  icon: Icons.high_quality_rounded,
                  label: _activeQualityLabel(stream),
                  entries: stream.qualities.keys
                      .map((String q) => (
                            q,
                            () => state._switchQuality(stream.qualities[q]!)
                          ))
                      .toList(),
                )
              else if (stream != null)
                const _OverlayLabel(
                    icon: Icons.high_quality_rounded, label: 'تلقائي'),
              const Spacer(),
              IconButton(
                tooltip: 'اصنع مقطعًا',
                icon: const Icon(Icons.content_cut_rounded,
                    color: Colors.white, size: 21),
                onPressed: (state._player == null ||
                        !state._player!.value.isInitialized ||
                        state._anime.watchId == null)
                    ? null
                    : () {
                        final VideoPlayerController c = state._player!;
                        c.pause();
                        showClipMaker(
                          context,
                          position: c.value.position,
                          duration: c.value.duration,
                          title: state._anime.title,
                          label: 'الحلقة ${state._episode?.number ?? 1}',
                          poster: state._anime.poster,
                          kind: 'anime',
                          source: 'anime',
                          ref: <String, String>{
                            'watchId': state._anime.watchId!,
                            'ep': '${state._episode?.number ?? 1}',
                            'slug': state._anime.slug ?? state._anime.id,
                          },
                        );
                      },
              ),
              IconButton(
                tooltip: 'مشاركة سريعة',
                icon: const Icon(Icons.share_rounded, color: Colors.white, size: 21),
                onPressed: stream == null
                    ? null
                    : () => showQuickShare(
                          context,
                          title: state._anime.title,
                          subtitle: 'الحلقة ${state._episode?.number ?? 1}',
                          poster: state._anime.poster,
                          source: 'url',
                          url: stream.url,
                          headers: <String, String>{
                            'User-Agent': _browserUa,
                            if (stream.referer.isNotEmpty) 'Referer': stream.referer,
                          },
                        ),
              ),
              DownloadIconButton(
                url: stream?.url ?? '',
                enabled: stream != null,
                onStart: state._download,
              ),
              _OverlayMenuButton<double>(
                icon: Icons.speed_rounded,
                label: '${_speedLabel(state._speed)}x',
                entries: const <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                    .map((double v) => (
                          '${_speedLabel(v)}x',
                          () => state._setSpeed(v),
                        ))
                    .toList(),
              ),
              IconButton(
                icon: Icon(
                  state._landscape
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: state._toggleOrientation,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _speedLabel(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static String _activeQualityLabel(ResolvedStream stream) {
    for (final MapEntry<String, String> e in stream.qualities.entries) {
      if (e.value == stream.url) return e.key;
    }
    return 'تلقائي';
  }
}

/// Small rounded button that opens an in-place menu (quality / speed).
class _OverlayMenuButton<T> extends StatelessWidget {
  const _OverlayMenuButton({
    required this.icon,
    required this.label,
    required this.entries,
  });

  final IconData icon;
  final String label;
  final List<(String, VoidCallback)> entries;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      color: AppColors.surfaceHi,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.zero,
      onSelected: (int i) => entries[i].$2(),
      itemBuilder: (BuildContext ctx) => List<PopupMenuItem<int>>.generate(
        entries.length,
        (int i) => PopupMenuItem<int>(
          value: i,
          height: 38,
          child: Text(entries[i].$1,
              style: const TextStyle(
                  fontFamily: 'Plex',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _OverlayLabel extends StatelessWidget {
  const _OverlayLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 19),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Plex',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

class _StageMessage extends StatelessWidget {
  const _StageMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const <Widget>[],
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                    color: AppColors.accent, strokeWidth: 2.5),
              )
            else
              Icon(icon, color: AppColors.muted, size: 40),
            const SizedBox(height: 12),
            Text(title,
                style: AppText.bodyBold.copyWith(fontSize: 14)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(fontSize: 11.5)),
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Servers panel (live backend)
// ---------------------------------------------------------------------------

class _ServersPanel extends StatelessWidget {
  const _ServersPanel({
    required this.future,
    required this.kind,
    required this.activeServer,
    required this.status,
    required this.onKind,
    required this.onPick,
    required this.episode,
    required this.episodes,
    required this.onSwitch,
  });

  final Future<List<EpisodeServer>>? future;
  final String kind;
  final EpisodeServer? activeServer;
  final String status;
  final ValueChanged<String> onKind;
  final ValueChanged<EpisodeServer> onPick;
  final Episode? episode;
  final List<Episode> episodes;
  final ValueChanged<Episode> onSwitch;

  static const Map<String, String> _kindLabel = <String, String>{
    'sub': 'مترجم',
    'ssub': 'مترجم-S',
    'dub': 'مدبلج',
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EpisodeServer>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<EpisodeServer>> snap) {
        final List<EpisodeServer> servers = snap.data ?? const <EpisodeServer>[];
        final List<String> kinds =
            servers.map((EpisodeServer s) => s.kind).toSet().toList();
        final bool loading = snap.connectionState != ConnectionState.done;

        final Episode? prev = _neighbour(-1);
        final Episode? next = _neighbour(1);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status.isNotEmpty) ...<Widget>[
                Row(
                  children: [
                    const SizedBox(width: 2),
                    Icon(Icons.info_outline_rounded,
                        size: 13, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label.copyWith(
                              fontSize: 10.5, color: AppColors.sub)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (loading && status.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: AppColors.accent, strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text('جارٍ تحميل السيرفرات…',
                          style: AppText.label.copyWith(fontSize: 11.5)),
                    ],
                  ),
                )
              else if (kinds.isEmpty && status.isEmpty)
                Text(
                  'تعذّر تحميل السيرفرات لهذه الحلقة — تحقّق من اتصالك أو حاول لاحقًا.',
                  style: AppText.label.copyWith(fontSize: 11),
                )
              else if (kinds.isNotEmpty) ...<Widget>[
                Row(
                  children: [
                    for (final String k in kinds) ...<Widget>[
                      GhostChip(
                        label: _kindLabel[k] ?? k.toUpperCase(),
                        active: k == kind,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        onTap: () => onKind(k),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: servers
                      .where((EpisodeServer s) => s.kind == kind)
                      .map((EpisodeServer s) {
                    final bool active = activeServer == s;
                    return GestureDetector(
                      onTap: () => onPick(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.accent.withValues(alpha: 0.16)
                              : AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: active
                                  ? AppColors.accent
                                  : AppColors.stroke),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                                active
                                    ? Icons.play_arrow_rounded
                                    : Icons.dns_rounded,
                                size: 14,
                                color: AppColors.accent),
                            const SizedBox(width: 6),
                            Text(s.name,
                                style: AppText.bodyBold.copyWith(
                                    fontSize: 11.5,
                                    color: active
                                        ? AppColors.accent
                                        : AppColors.text)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _NavButton(
                    label: 'الحلقة السابقة',
                    icon: Icons.skip_previous_rounded,
                    enabled: prev != null,
                    onTap: prev == null ? null : () => onSwitch(prev),
                  ),
                  const SizedBox(width: 10),
                  _NavButton(
                    label: 'الحلقة التالية',
                    icon: Icons.skip_next_rounded,
                    enabled: next != null,
                    onTap: next == null ? null : () => onSwitch(next),
                  ),
                ],
              ),
              if (episode != null && episodes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'الحلقة ${episode!.number} من ${episodes.length}',
                  style: AppText.label.copyWith(fontSize: 10, color: AppColors.sub),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Episode? _neighbour(int delta) {
    if (episode == null || episodes.isEmpty) return null;
    final int i =
        episodes.indexWhere((Episode e) => e.number == episode!.number);
    if (i < 0) return null;
    final int j = i + delta;
    if (j < 0 || j >= episodes.length) return null;
    return episodes[j];
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(label,
                  style: AppText.bodyBold.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
