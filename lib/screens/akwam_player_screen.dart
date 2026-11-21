import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'clips_screen.dart';
import '../core/social.dart';
import '../core/binge.dart';
import '../core/akwam_api.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../core/library_store.dart';
import '../core/net_quality.dart';
import '../core/app_prefs.dart';
import '../core/audio_mode.dart';
import '../core/data_budget.dart';
import '../core/moments.dart';
import '../core/fast_start.dart';
import '../widgets/player_social.dart';
import '../widgets/player_gestures.dart';
import '../widgets/download_button.dart';
import '../widgets/quick_share.dart';
import 'akwam_tab.dart';

/// Native (ExoPlayer) player for the Akwam section.
///
/// Resolves the chosen quality's `/watch/{fileId}` page into the direct
/// MP4 URL Akwam embeds there and plays it through `video_player` — no
/// WebView. Includes prev/next episode, quality switcher, speed, mute,
/// lock and immersive fullscreen.
class AkwamPlayerScreen extends StatefulWidget {
  const AkwamPlayerScreen({super.key});

  @override
  State<AkwamPlayerScreen> createState() => _AkwamPlayerScreenState();
}

class _AkwamPlayerScreenState extends State<AkwamPlayerScreen>
    with WidgetsBindingObserver {
  AkwamItem _item = AkwamItem(id: '', path: '', kind: AkwamKind.movie, title: '');
  AkwamEpisode? _episode;
  List<AkwamEpisode> _episodes = const <AkwamEpisode>[];
  List<AkwamSource> _sources = const <AkwamSource>[];
  int _sourceIndex = 0;

  VideoPlayerController? _player;

  /// Hot moments + timed comments of the episode being played.
  EpisodeSocial? _social;

  // ----- Fast start (slow connections) -----
  /// Every quality's MP4 (one watch page lists them all): height → URL.
  Map<int, String> _streams = const <int, String>{};

  /// Play through FastStart windows (small index, starts in seconds).
  bool _fastStart = true;

  /// Current window (null = the plain file is playing).
  FastWindow? _win;
  VideoPlayerController? _next;
  FastWindow? _nextWin;
  bool _preparingNext = false;
  bool _swapping = false;

  /// Sleep timer: minutes (0 = off, -1 = end of this episode).
  int _sleepMinutes = 0;
  Timer? _sleepTimer;

  /// Buffering samples (stall detection → automatic lower quality).
  final List<DateTime> _stallTicks = <DateTime>[];
  DateTime _lastSeekAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': AkwamApi.ua,
    'Referer': '${AkwamApi.base}/',
  };

  Duration get _offset => _win == null
      ? Duration.zero
      : Duration(milliseconds: (_win!.offset * 1000).round());

  /// Real playback position in the movie / episode.
  Duration get _pos {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return Duration.zero;
    return c.value.position + _offset;
  }

  /// Real duration of the movie / episode.
  Duration get _dur {
    if (_win != null) return Duration(milliseconds: (_win!.total * 1000).round());
    return _player?.value.duration ?? Duration.zero;
  }

  static int _heightOf(String q) =>
      int.tryParse(RegExp(r'(\d{3,4})').firstMatch(q)?.group(1) ?? '') ?? 0;

  /// Direct stream URL of the quality being played (for downloads).
  String _streamUrl = '';
  bool _resolving = true;
  String? _error;
  String _status = '';

  bool _landscape = false;
  bool _controlsVisible = true;
  bool _muted = false;
  bool _locked = false;
  double _speed = 1.0;
  Timer? _hideTimer;
  Timer? _positionTicker;

  /// Scrub state — seek fires once on release.
  bool _dragging = false;
  double _dragValue = 0;

  /// Mid-stream recovery state.
  bool _recovering = false;
  int _streamRetries = 0;

  static const MethodChannel _channel = MethodChannel('animax/app');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Sound-only mode keeps playing with the screen off.
      if (c.value.isPlaying && !AppPrefs.I.audioOnly) c.pause();
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
    if (args is ({AkwamItem item, AkwamEpisode? episode})) {
      // Open only when the target actually changed (didChangeDependencies
      // also fires on unrelated dependency updates like theme switches).
      final bool changed = args.item.path != _item.path ||
          args.episode?.id != _episode?.id;
      _item = args.item;
      _episode = args.episode;
      if (changed || _player == null) {
        _open(args.episode);
      }
    }
  }

  String get _progressKey => 'akwam:${_item.path}';
  String get _progressSub => '${_episode?.number ?? 0}';

  /// Stores the playback position (resume + progress bars + watched marks).
  void _saveProgress() {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized || _item.path.isEmpty) return;
    final int pos = _pos.inSeconds;
    final int dur = _dur.inSeconds;
    if (pos <= 0) return;
    LibraryStore.I.saveProgress(
      key: _progressKey,
      sub: _progressSub,
      positionSec: pos,
      durationSec: dur,
      watched: dur > 0 && pos >= dur * 0.92,
    );
  }

  @override
  void dispose() {
    _saveProgress();
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _positionTicker?.cancel();
    _sleepTimer?.cancel();
    final VideoPlayerController? c = _player;
    _player = null;
    c?.dispose();
    _next?.dispose();
    _next = null;
    _social?.dispose();
    unawaited(AudioMode.keepAlive(false));
    _setKeepScreenOn(false);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ----- Playback -----

  Future<void> _open(AkwamEpisode? episode, {Duration? resumeAt}) async {
    _positionTicker?.cancel();
    _hideTimer?.cancel();
    await _disposePlayer();
    if (!mounted) return;
    setState(() {
      _episode = episode;
      _resolving = true;
      _error = null;
      _sources = const <AkwamSource>[];
      _sourceIndex = 0;
      _status = episode == null
          ? 'جارٍ تحميل الجودات…'
          : 'جارٍ تحميل الحلقة ${episode.number}…';
    });

    // 1. Sources (qualities) from the episode page — or the movie page.
    List<AkwamSource> sources;
    try {
      sources = episode == null
          ? await AkwamApi.I.sourcesFor(_item)
          : await AkwamApi.I.episodeSources(episode);
    } on AkwamApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'تعذّر الوصول إلى أكوام — تحقّق من اتصالك.';
      });
      return;
    }
    if (sources.isEmpty) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'لا توجد جودة قابلة للتشغيل لهذا العنوان.';
      });
      return;
    }

    // 2. Resolve the first quality into a direct stream URL.
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _status = 'جارٍ التحميل…';
    });
    // One watch page lists the file of every quality.
    try {
      _streams = await AkwamApi.I.streamsOf(sources.first.watchPath);
    } catch (_) {
      _streams = const <int, String>{};
    }
    // Measure the real speed (the OS link speed is often far too
    // optimistic) while the lowest quality's index starts loading.
    int kbps = NetQuality.hasFreshMeasure ? NetQuality.measuredKbps : -1;
    if (_streams.isNotEmpty) {
      final String low = AkwamApi.pickAkwamStream(_streams, lowest: true);
      unawaited(FastStart.index(low, _headers).then((_) {}, onError: (Object _) {}));
      if (kbps <= 0) {
        if (mounted) setState(() => _status = 'جارٍ قياس سرعة الإنترنت…');
        kbps = await NetQuality.probe(low, _headers);
      }
    }
    if (!mounted) return;
    final bool slow = await NetQuality.check();
    // FastStart unless the line is clearly fast.
    _fastStart = kbps <= 0 || kbps < 6000 || slow;
    await _playSource(_startIndex(sources, kbps, slow), resumeAt: resumeAt);

    // 3. Episode list for prev/next (series only, best-effort).
    if (episode != null && _episodes.isEmpty) {
      try {
        final List<AkwamEpisode> eps = await AkwamApi.I.episodesOf(_item);
        if (mounted) setState(() => _episodes = eps);
      } catch (_) {
        // Navigation simply stays unavailable.
      }
    }
  }

  /// Quality to start with: the user's fixed choice, else the best one the
  /// measured speed sustains (lowest in low-data / sound-only mode).
  int _startIndex(List<AkwamSource> sources, int kbps, bool slow) {
    final List<int> hs = sources.map((AkwamSource s) => _heightOf(s.quality)).toList();
    int target;
    final int? fixed = int.tryParse(AppPrefs.I.defaultQuality);
    if (fixed != null) {
      target = fixed;
    } else if (AppPrefs.I.audioOnly || AppPrefs.I.dataSaver ||
        DataBudget.I.nearLimit || (slow && kbps <= 0)) {
      target = 0; // lowest
    } else {
      target = NetQuality.pickHeight(hs, kbps);
    }
    int best = -1;
    for (int i = 0; i < hs.length; i++) {
      final int h = hs[i];
      if (target == 0) {
        if (best < 0 || (h > 0 && h < hs[best])) best = i;
      } else if (h > 0 && h <= target && (best < 0 || h > hs[best])) {
        best = i;
      }
    }
    if (best < 0) {
      // Nothing at/below the target: take the smallest.
      for (int i = 0; i < hs.length; i++) {
        if (best < 0 || (hs[i] > 0 && hs[i] < hs[best])) best = i;
      }
    }
    return best < 0 ? 0 : best;
  }

  Future<String> _urlFor(int index) async {
    final AkwamSource s = _sources[index];
    final int h = _heightOf(s.quality);
    if (_streams.isNotEmpty) {
      final String u = AkwamApi.pickAkwamStream(_streams, height: h == 0 ? null : h);
      if (u.isNotEmpty) return u;
    }
    return AkwamApi.I.resolveStream(s.watchPath, quality: s.quality);
  }

  /// [exact]: [resumeAt] is a user choice (seek / quality switch) — do not
  /// replace it with the saved resume position.
  Future<void> _playSource(int index, {Duration? resumeAt, bool exact = false}) async {
    if (index < 0 || index >= _sources.length) return;
    _positionTicker?.cancel();
    await _disposePlayer();
    if (!mounted) return;
    setState(() {
      _sourceIndex = index;
      _resolving = true;
      _error = null;
      _status = 'جارٍ التحميل…';
    });

    String url;
    try {
      url = await _urlFor(index);
    } on AkwamApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'تعذّر الوصول إلى أكوام — تحقّق من اتصالك.';
      });
      return;
    }

    if (!mounted) return;
    if (!await DataBudget.I.allowStreaming(context)) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'تم الإيقاف للحفاظ على ميزانية البيانات — اتصل بشبكة Wi-Fi.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _status = '';
      _streamUrl = url;
    });
    final bool isHls = url.contains('.m3u8');
    final Map<String, String> headers = <String, String>{
      'User-Agent': AkwamApi.ua,
      'Referer': '${AkwamApi.base}/',
    };
    final String playUrl = isHls && AppPrefs.I.audioOnly
        ? await AudioMode.lightestHls(url, headers)
        : url;
    final String ek = Moments.episodeKey(
        'akwam', <String, String>{'path': _sources[index].watchPath});
    if (_social?.ek != ek) {
      _social?.dispose();
      _social = ek.isEmpty ? null : EpisodeSocial(ek);
    }
    // Where to start (real time): explicit, else the saved resume point.
    Duration target = resumeAt ?? Duration.zero;
    if (!exact && target == Duration.zero && _item.path.isNotEmpty) {
      final ProgressEntry? p =
          LibraryStore.I.progressOf(_progressKey, _progressSub);
      if (p != null && !p.watched && p.positionSec > 15) {
        target = Duration(seconds: p.positionSec);
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text('استئناف من ${_fmt(target)}'),
            duration: const Duration(seconds: 2),
          ));
        }
      }
    }
    // Fast start: a small index for the next ~90 s instead of the whole
    // file's (MBs) — plays within seconds on slow lines.
    FastWindow? win;
    if (_fastStart && !isHls) {
      if (mounted) setState(() => _status = 'تشغيل سريع…');
      try {
        win = await FastStart.open(url, headers,
            from: target.inMilliseconds / 1000, length: 90);
      } catch (_) {
        win = null; // unusual file → play it directly
      }
      if (!mounted) return;
      setState(() => _status = '');
    }
    final VideoPlayerController controller = win != null
        ? VideoPlayerController.networkUrl(
            win.uri,
            formatHint: VideoFormat.other,
            videoPlayerOptions:
                VideoPlayerOptions(allowBackgroundPlayback: AppPrefs.I.audioOnly),
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(playUrl),
            httpHeaders: headers,
            formatHint: isHls ? VideoFormat.hls : VideoFormat.other,
            videoPlayerOptions:
                VideoPlayerOptions(allowBackgroundPlayback: AppPrefs.I.audioOnly),
          );
    _win = win;
    _player = controller;
    controller.addListener(() => _playerListener(controller));
    setState(() {});
    try {
      await controller.initialize();
    } catch (_) {
      if (!mounted) return;
      if (win != null) {
        // The windowed file failed to open → play the original directly.
        _fastStart = false;
        await _playSource(index, resumeAt: target, exact: true);
        return;
      }
      // This quality failed — automatically try the next one.
      if (index + 1 < _sources.length) {
        await _playSource(index + 1, resumeAt: target, exact: true);
        return;
      }
      await _disposePlayer();
      setState(() {
        _resolving = false;
        _error = 'تعذّر على المشغّل فتح البث. جرّب جودة أخرى.';
      });
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    // Seek to the target inside the window (or the plain file).
    final Duration local = target - _offset;
    if (local > const Duration(milliseconds: 300)) {
      try {
        await controller.seekTo(local);
      } catch (_) {}
    }
    _lastSeekAt = DateTime.now();
    controller.setVolume(_muted ? 0 : 1);
    if (_speed != 1.0) controller.setPlaybackSpeed(_speed);
    await controller.play();
    _setKeepScreenOn(true);
    unawaited(AudioMode.keepAlive(AppPrefs.I.audioOnly, title: _title));
    Binge.started('akwam:${_item.path}#${_episode?.number ?? 0}');
    // Watch history: powers "continue watching" on Home and the Me page.
    if (_item.path.isNotEmpty) {
      unawaited(Social.countView('akwam:${_item.path}',
          title: _item.title, poster: _item.poster, kind: 'akwam'));
      LibraryStore.I.pushHistory(
        key: 'akwam:${_item.path}',
        title: _item.title,
        poster: _item.poster,
        kind: 'akwam',
        sub: '${_episode?.number ?? 0}',
        label: _episode == null
            ? (_item.year.isEmpty ? 'فيلم' : _item.year)
            : 'الحلقة ${_episode!.number}',
      );
    }
    int ticks = 0;
    _positionTicker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() {});
      if (++ticks % 12 == 0) _saveProgress(); // every ~5 s
      final FastWindow? w = _win;
      if (w != null && !w.isLast) {
        // Build the next window ahead of time; switch right at the edge.
        final double left = w.end - _pos.inMilliseconds / 1000;
        if (left < 45) unawaited(_prepareNext());
        final VideoPlayerController? c = _player;
        if (c != null &&
            c.value.isInitialized &&
            c.value.duration > Duration.zero &&
            c.value.position >= c.value.duration - const Duration(milliseconds: 150)) {
          unawaited(_advanceWindow());
        }
      }
      _watchStalls();
    });
    _bumpControls();
    setState(() {
      _resolving = false;
      _status = '';
    });
  }

  Future<void> _disposePlayer() async {
    final VideoPlayerController? c = _player;
    final VideoPlayerController? n = _next;
    _player = null;
    _next = null;
    _nextWin = null;
    _win = null;
    try {
      await c?.dispose();
      await n?.dispose();
    } catch (_) {}
  }

  /// Prepares the window that follows the current one (paused, buffered).
  Future<void> _prepareNext() async {
    final FastWindow? w = _win;
    if (w == null || w.isLast || _preparingNext || _next != null) return;
    _preparingNext = true;
    try {
      final FastWindow nw =
          await FastStart.open(_streamUrl, _headers, from: w.end, length: 300);
      if (!mounted || _win != w) return;
      final VideoPlayerController c = VideoPlayerController.networkUrl(
        nw.uri,
        formatHint: VideoFormat.other,
        videoPlayerOptions:
            VideoPlayerOptions(allowBackgroundPlayback: AppPrefs.I.audioOnly),
      );
      await c.initialize();
      if (!mounted || _win != w) {
        await c.dispose();
        return;
      }
      await c.setVolume(_muted ? 0 : 1);
      if (_speed != 1.0) await c.setPlaybackSpeed(_speed);
      c.addListener(() => _playerListener(c));
      _next = c;
      _nextWin = nw;
    } catch (_) {
      // Retried on the next tick / at the edge.
    } finally {
      _preparingNext = false;
    }
  }

  /// Switches to the next window exactly where the current one ends.
  Future<void> _advanceWindow() async {
    final FastWindow? w = _win;
    if (w == null || w.isLast || _swapping) return;
    _swapping = true;
    try {
      if (_next == null) {
        if (mounted) setState(() => _resolving = true);
        await _prepareNext();
      }
      if (!mounted || _win != w) return;
      final VideoPlayerController? n = _next;
      if (n == null) {
        // Could not prepare in time → reopen at the edge.
        await _playSource(_sourceIndex,
            resumeAt: Duration(milliseconds: (w.end * 1000).round()), exact: true);
        return;
      }
      final VideoPlayerController? old = _player;
      setState(() {
        _player = n;
        _win = _nextWin;
        _next = null;
        _nextWin = null;
        _resolving = false;
      });
      await n.play();
      _lastSeekAt = DateTime.now();
      await old?.dispose();
    } finally {
      _swapping = false;
    }
  }

  /// Seeks in real time; outside the loaded window a new window is opened.
  Future<void> _seekReal(Duration t) async {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    if (t < Duration.zero) t = Duration.zero;
    if (_dur > Duration.zero && t > _dur) t = _dur - const Duration(seconds: 1);
    _lastSeekAt = DateTime.now();
    final FastWindow? w = _win;
    if (w == null) {
      await c.seekTo(t);
      return;
    }
    final double s = t.inMilliseconds / 1000;
    if (s >= w.offset && s < w.end - 1) {
      await c.seekTo(t - _offset);
      return;
    }
    await _playSource(_sourceIndex, resumeAt: t, exact: true);
  }

  /// ~8 s of stalling within a minute → step down to a lower quality.
  void _watchStalls() {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized || _resolving || _swapping) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastSeekAt).inSeconds < 8) return;
    if (c.value.isBuffering && c.value.isPlaying) _stallTicks.add(now);
    _stallTicks.removeWhere((DateTime t) => now.difference(t).inSeconds > 60);
    if (_stallTicks.length < 20) return;
    _stallTicks.clear();
    final int cur = _heightOf(_sources[_sourceIndex].quality);
    int lower = -1;
    for (int i = 0; i < _sources.length; i++) {
      final int h = _heightOf(_sources[i].quality);
      if (h > 0 && h < cur && (lower < 0 || h > _heightOf(_sources[lower].quality))) {
        lower = i;
      }
    }
    if (lower < 0) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      persist: false,
      duration: const Duration(seconds: 3),
      content: Text('الإنترنت بطيء — تم التبديل إلى ${_sources[lower].quality} لتشغيل أسلس'),
    ));
    unawaited(_playSource(lower, resumeAt: _pos, exact: true));
  }

  /// Runtime listener: mid-playback failure recovery + auto-advance.
  void _playerListener(VideoPlayerController c) {
    if (!mounted || _player != c) return;
    final VideoPlayerValue v = c.value;
    if (v.hasError && !_resolving) {
      _onStreamDied();
      return;
    }
    if (v.isCompleted && !_resolving) {
      if (_win != null && !_win!.isLast) {
        unawaited(_advanceWindow());
        return;
      }
      if (_sleepMinutes == -1) {
        // "End of episode" sleep timer: stop here, no auto-next.
        setState(() {
          _sleepMinutes = 0;
          _controlsVisible = true;
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
            content: Text('مؤقت النوم — انتهت الحلقة وتوقف التشغيل')));
        return;
      }
      Binge.episodeEnded(context,
          episodeKey: 'akwam:${_item.path}#${_episode?.number ?? 0}',
          next: _hasNext ? _autoNextEpisode : null);
    }
  }

  void _autoNextEpisode() {
    if (_episode == null) return;
    final int i = _indexOfEpisode(_episode!);
    if (i < 0 || i + 1 >= _episodes.length) return;
    _open(_episodes[i + 1]);
  }

  /// Mid-stream failure: retry once at the same position, then error out.
  Future<void> _onStreamDied() async {
    if (_recovering) return;
    _recovering = true;
    try {
      _streamRetries++;
      final Duration pos = _pos;
      if (_streamRetries <= 1) {
        await _disposePlayer();
        if (!mounted) return;
        setState(() {
          _resolving = true;
          _status = '';
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        _recovering = false;
        await _playSource(_sourceIndex, resumeAt: pos, exact: true);
        return;
      }
      _recovering = false;
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = 'فشل التشغيل — جرّب جودة أخرى.';
        });
      }
    } catch (_) {
      _recovering = false;
    }
  }

  int _indexOfEpisode(AkwamEpisode ep) {
    for (int i = 0; i < _episodes.length; i++) {
      if (_episodes[i].id == ep.id) return i;
    }
    return -1;
  }

  void _switchEpisode(int delta) {
    if (_episode == null) return;
    final int i = _indexOfEpisode(_episode!);
    if (i < 0) return;
    final int next = i + delta;
    if (next < 0 || next >= _episodes.length) return;
    _open(_episodes[next]);
  }

  bool get _hasPrev =>
      _episode != null && _indexOfEpisode(_episode!) > 0;
  bool get _hasNext {
    if (_episode == null) return false;
    final int i = _indexOfEpisode(_episode!);
    return i >= 0 && i + 1 < _episodes.length;
  }

  void _setKeepScreenOn(bool keep) {
    _channel
        .invokeMethod<bool>('setKeepScreenOn', <String, dynamic>{'keep': keep})
        .catchError((Object e) => false);
  }

  // ----- Controls -----

  Future<void> _enterPip() async {
    final bool ok = await enterPipMode();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('خاصية صورة داخل صورة غير متاحة على هذا الجهاز.')));
    }
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepMinutes = minutes);
    if (minutes <= 0) return;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      if (!mounted) return;
      _player?.pause();
      setState(() {
        _sleepMinutes = 0;
        _controlsVisible = true;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text('مؤقت النوم — توقف التشغيل بعد $minutes دقيقة')));
    });
  }

  void _pickSleepTimer() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final int m in <int>[0, -1, 15, 30, 45, 60, 90])
                ListTile(
                  leading: Icon(
                      m == 0 ? Icons.timer_off_rounded : Icons.nightlight_round,
                      color: _sleepMinutes == m ? AkwamColors.teal : AppColors.muted),
                  title: Text(
                      m == 0
                          ? 'إيقاف المؤقت'
                          : m == -1
                              ? 'عند نهاية الحلقة'
                              : '$m دقيقة',
                      style: const TextStyle(fontFamily: 'Plex', color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setSleepTimer(m);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sound only ⇄ video. Re-opens the stream: sound only plays the smallest
  /// quality and keeps running in the background.
  Future<void> _toggleAudioOnly() async {
    final bool on = !AppPrefs.I.audioOnly;
    AppPrefs.I.set('audioOnly', on);
    final Duration pos = _pos;
    int index = _sourceIndex;
    if (on && _sources.length > 1) {
      int q(AkwamSource s) =>
          int.tryParse(RegExp(r'(\d{3,4})').firstMatch(s.quality)?.group(1) ?? '') ?? 9999;
      for (int i = 0; i < _sources.length; i++) {
        if (q(_sources[i]) < q(_sources[index])) index = i;
      }
    }
    if (!on) unawaited(AudioMode.keepAlive(false));
    await _playSource(index, resumeAt: pos, exact: true);
  }

  void _bumpControls() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    final bool playing = _player?.value.isInitialized == true &&
        _player!.value.isPlaying;
    _hideTimer = Timer(Duration(milliseconds: playing ? 3500 : 60000), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _togglePlay() {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    c.value.isPlaying ? c.pause() : c.play();
    _bumpControls();
  }

  void dragTo(double ms) {
    if (!mounted) return;
    setState(() {
      _dragging = true;
      _dragValue = ms;
    });
  }

  void endDrag(double ms) {
    _dragging = false;
    unawaited(_seekReal(Duration(milliseconds: ms.round())));
    _bumpControls();
  }

  void _seekBy(int seconds) {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    unawaited(_seekReal(_pos + Duration(seconds: seconds)));
    _bumpControls();
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    if (_locked) {
      _hideTimer?.cancel();
    } else {
      _bumpControls();
    }
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
    final double v = (c.value.volume + value).clamp(0.0, 1.0);
    c.setVolume(v);
    if (v > 0 && _muted) setState(() => _muted = false);
  }

  void _toggleMute() {
    final VideoPlayerController? c = _player;
    if (c == null) return;
    setState(() => _muted = !_muted);
    c.setVolume(_muted ? 0 : 1);
    _bumpControls();
  }

  Future<void> _setSpeed(double s) async {
    setState(() => _speed = s);
    await _player?.setPlaybackSpeed(s);
    _bumpControls();
  }

  void _toggleOrientation() {
    setState(() => _landscape = !_landscape);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      if (_landscape) ...<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ] else ...<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
    ]);
    SystemChrome.setEnabledSystemUIMode(
      _landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    _bumpControls();
  }

  void _showQualitySheet() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text('الجودة — أكوام',
                  style: AppText.h3.copyWith(fontSize: 14)),
            ),
            for (int i = 0; i < _sources.length; i++)
              ListTile(
                leading: Icon(
                  i == _sourceIndex
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: i == _sourceIndex ? AkwamColors.teal : AppColors.muted,
                  size: 20,
                ),
                title: Text(
                  _sources[i].quality +
                      (_sources[i].size.isNotEmpty
                          ? '  ·  ${_sources[i].size}'
                          : ''),
                  style: TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (i != _sourceIndex) {
                    _playSource(i, resumeAt: _pos, exact: true);
                  }
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  // ----- Build -----

  /// Queues the current title/episode at the quality being played.
  Future<void> _download() async {
    if (_streamUrl.isEmpty) return;
    final String quality =
        _sources.isEmpty ? '' : _sources[_sourceIndex].quality;
    await DownloadManager.I.addVideo(
      title: _item.title,
      subtitle: <String>[
        if (_episode != null) 'الحلقة ${_episode!.number}',
        if (quality.isNotEmpty) quality,
      ].join(' · '),
      poster: _item.poster,
      url: _streamUrl,
      headers: <String, String>{
        'User-Agent': AkwamApi.ua,
        'Referer': '${AkwamApi.base}/',
      },
    );
  }

  String get _title {
    final String base = _item.title;
    return _episode == null ? base : '$base · E${_episode!.number}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayerGestureOverlay(
        onTap: _bumpControls,
        onSeek: _seekBy,
        onSpeedBoost: _onSpeedBoost,
        onVolume: _onVolume,
        onBrightness: (double _) {},
        locked: _locked,
        onLockTap: _toggleLock,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _videoArea(),
            if (AppPrefs.I.audioOnly && _player != null)
              AudioOnlyCover(
                  poster: _item.poster, title: _title, onExit: _toggleAudioOnly),
            TimedCommentsLayer(
                social: _social, controller: _player, offset: _offset),
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Column(
                  children: <Widget>[
                    _topBar(),
                    const Spacer(),
                    _centerControls(),
                    _bottomControls(),
                  ],
                ),
              ),
            ),
            if (_resolving) _resolvingCard(),
            if (!_resolving && _error != null) _errorCard(),
          ],
        ),
      ),
    );
  }

  Widget _videoArea() {
    final VideoPlayerController? player = _player;
    if (player == null || !player.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_item.poster.isNotEmpty)
            Image.network(_item.poster,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(color: Colors.black))
          else
            Container(color: Colors.black),
        ],
      );
    }
    final Size size = player.value.size;
    return Center(
      child: AspectRatio(
        aspectRatio: size.width == 0 || size.height == 0
            ? 16 / 9
            : size.width / size.height,
        child: VideoPlayer(player),
      ),
    );
  }

  Widget _topBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Text(
                _title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
            IconButton(
              tooltip: 'اصنع مقطعًا',
              icon: const Icon(Icons.content_cut_rounded,
                  color: Colors.white, size: 21),
              onPressed: (_player == null ||
                      !_player!.value.isInitialized ||
                      _sources.isEmpty)
                  ? null
                  : () {
                      final VideoPlayerController c = _player!;
                      c.pause();
                      showClipMaker(
                        context,
                        position: _pos,
                        duration: _dur,
                        title: _item.title,
                        label: _episode == null ? '' : 'الحلقة ${_episode!.number}',
                        poster: _item.poster,
                        kind: 'akwam',
                        source: 'akwam',
                        ref: <String, String>{
                          'path': _sources[_sourceIndex].watchPath,
                          'item': _item.path,
                          if (_episode != null) 'ep': '${_episode!.number}',
                        },
                      );
                    },
            ),
            IconButton(
              tooltip: 'مشاركة سريعة',
              icon: const Icon(Icons.share_rounded, color: Colors.white, size: 21),
              onPressed: _streamUrl.isEmpty
                  ? null
                  : () => showQuickShare(
                        context,
                        title: _item.title,
                        subtitle: _episode == null ? '' : 'الحلقة ${_episode!.number}',
                        poster: _item.poster,
                        source: 'url',
                        url: _streamUrl,
                        headers: <String, String>{
                          'User-Agent': AkwamApi.ua,
                          'Referer': '${AkwamApi.base}/',
                        },
                      ),
            ),
            DownloadIconButton(
              url: _streamUrl,
              enabled: _streamUrl.isNotEmpty,
              onStart: _download,
              size: 21,
            ),
            IconButton(
              icon: Icon(
                _locked
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: _toggleLock,
            ),
            PopupMenuButton<String>(
              key: const Key('akwamMore'),
              tooltip: 'المزيد',
              color: AppColors.surface,
              icon: Icon(Icons.more_vert_rounded,
                  color: _sleepMinutes != 0 ? AkwamColors.teal : Colors.white, size: 21),
              onSelected: (String v) {
                if (v == 'pip') _enterPip();
                if (v == 'sleep') _pickSleepTimer();
              },
              itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                    value: 'pip',
                    child: Text('صورة داخل صورة', style: TextStyle(fontFamily: 'Plex'))),
                PopupMenuItem<String>(
                    value: 'sleep',
                    child: Text(
                        _sleepMinutes == 0
                            ? 'مؤقت النوم'
                            : _sleepMinutes == -1
                                ? 'مؤقت النوم (نهاية الحلقة)'
                                : 'مؤقت النوم ($_sleepMinutes د)',
                        style: const TextStyle(fontFamily: 'Plex'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (_episode != null)
          IconButton(
            icon: Icon(Icons.skip_previous_rounded,
                color: _hasPrev ? Colors.white : Colors.white24, size: 38),
            onPressed: _hasPrev ? () => _switchEpisode(-1) : null,
          ),
        const SizedBox(width: 18),
        Material(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(40),
          child: IconButton(
            icon: Icon(
              _player != null &&
                      _player!.value.isInitialized &&
                      _player!.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 44,
            ),
            onPressed: _togglePlay,
          ),
        ),
        const SizedBox(width: 18),
        if (_episode != null)
          IconButton(
            icon: Icon(Icons.skip_next_rounded,
                color: _hasNext ? Colors.white : Colors.white24, size: 38),
            onPressed: _hasNext ? () => _switchEpisode(1) : null,
          ),
      ],
    );
  }

  Widget _bottomControls() {
    final VideoPlayerController? c = _player;
    final Duration position =
        _dragging ? Duration(milliseconds: _dragValue.round()) : _pos;
    final Duration duration = _dur;
    final double maxMs = duration.inMilliseconds.toDouble();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(_fmt(position),
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 10.5,
                        color: Colors.white70)),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: HeatStrip(
                          social: _social,
                          duration: duration,
                          onSeek: (Duration d) {
                            unawaited(_seekReal(d));
                            _bumpControls();
                          },
                        ),
                      ),
                      SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: AkwamColors.teal,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: maxMs <= 0 ||
                              position.inMilliseconds > maxMs
                          ? 0
                          : position.inMilliseconds.toDouble(),
                      max: maxMs <= 0 ? 1 : maxMs,
                      onChanged: c == null || !c.value.isInitialized || maxMs <= 0
                          ? null
                          : dragTo,
                      onChangeEnd: maxMs <= 0 ? null : endDrag,
                    ),
                  ),
                    ],
                  ),
                ),
                Text(_fmt(duration),
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 10.5,
                        color: Colors.white70)),
              ],
            ),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _showQualitySheet,
                  child: Text(
                    'الجودة ${_sources.isNotEmpty ? _sources[_sourceIndex].quality : ''}',
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AkwamColors.teal),
                  ),
                ),
                const Spacer(),
                MomentsMenuButton(
                  social: _social,
                  controller: c,
                  offset: _offset,
                  total: _dur,
                  onSeek: (Duration d) {
                    unawaited(_seekReal(d));
                    _bumpControls();
                  },
                ),
                IconButton(
                  key: const Key('audioOnlyToggle'),
                  tooltip: 'صوت فقط',
                  icon: Icon(
                      AppPrefs.I.audioOnly
                          ? Icons.headphones_rounded
                          : Icons.headset_off_rounded,
                      color: AppPrefs.I.audioOnly
                          ? AkwamColors.teal
                          : Colors.white,
                      size: 20),
                  onPressed: _player == null ? null : _toggleAudioOnly,
                ),
                IconButton(
                  icon: Icon(
                    _muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _toggleMute,
                ),
                PopupMenuButton<double>(
                  tooltip: 'السرعة',
                  color: AppColors.surface,
                  icon: Text('${_speed.toStringAsFixed(1)}×',
                      style: TextStyle(
                          fontFamily: 'Plex',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  itemBuilder: (BuildContext ctx) => <PopupMenuEntry<double>>[
                    for (final double s in <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                      PopupMenuItem<double>(
                        value: s,
                        child: Text('${s.toStringAsFixed(2)}×',
                            style: TextStyle(
                                fontFamily: 'Plex',
                                fontSize: 12.5,
                                color: AppColors.text)),
                      ),
                  ],
                  onSelected: _setSpeed,
                ),
                IconButton(
                  icon: Icon(
                    _landscape
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: _toggleOrientation,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resolvingCard() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.black.withValues(alpha: 0.72),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(
                color: AkwamColors.teal, strokeWidth: 2.6),
            if (_status.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(_status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 12,
                      color: Colors.white70)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.black.withValues(alpha: 0.78),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 34),
            const SizedBox(height: 12),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 12.5,
                    height: 1.45,
                    color: Colors.white70)),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_sources.length > 1)
                  TextButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _showQualitySheet();
                    },
                    child: Text('اختر الجودة',
                        style: TextStyle(
                            fontFamily: 'Plex',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AkwamColors.teal)),
                  ),
                TextButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _playSource(_sourceIndex);
                  },
                  child: Text('إعادة المحاولة',
                      style: TextStyle(
                          fontFamily: 'Plex',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
