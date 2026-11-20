import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/akwam_api.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../widgets/player_gestures.dart';
import '../widgets/download_button.dart';
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _positionTicker?.cancel();
    final VideoPlayerController? c = _player;
    _player = null;
    c?.dispose();
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
          ? 'Loading qualities…'
          : 'Loading episode ${episode.number}…';
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
        _error = 'Cannot reach Akwam — check your connection.';
      });
      return;
    }
    if (sources.isEmpty) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'No playable quality found for this title.';
      });
      return;
    }

    // 2. Resolve the first quality into a direct stream URL.
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _status = 'Loading…';
    });
    await _playSource(0, resumeAt: resumeAt);

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

  Future<void> _playSource(int index, {Duration? resumeAt}) async {
    if (index < 0 || index >= _sources.length) return;
    _positionTicker?.cancel();
    await _disposePlayer();
    if (!mounted) return;
    setState(() {
      _sourceIndex = index;
      _resolving = true;
      _error = null;
      _status = 'Loading…';
    });

    String url;
    try {
      url = await AkwamApi.I.resolveStream(_sources[index].watchPath);
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
        _error = 'Cannot reach Akwam — check your connection.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _status = '';
      _streamUrl = url;
    });
    final bool isHls = url.contains('.m3u8');
    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: <String, String>{
        'User-Agent': AkwamApi.ua,
        'Referer': '${AkwamApi.base}/',
      },
      formatHint: isHls ? VideoFormat.hls : VideoFormat.other,
    );
    _player = controller;
    controller.addListener(() => _playerListener(controller));
    setState(() {});
    try {
      await controller.initialize();
    } catch (_) {
      if (!mounted) return;
      // This quality failed — automatically try the next one.
      if (index + 1 < _sources.length) {
        await _playSource(index + 1, resumeAt: resumeAt);
        return;
      }
      await _disposePlayer();
      setState(() {
        _resolving = false;
        _error = 'Player failed to open the stream. Try another quality.';
      });
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    if (resumeAt != null && resumeAt > Duration.zero) {
      try {
        await controller.seekTo(resumeAt);
      } catch (_) {}
    }
    controller.setVolume(_muted ? 0 : 1);
    if (_speed != 1.0) controller.setPlaybackSpeed(_speed);
    await controller.play();
    _setKeepScreenOn(true);
    _positionTicker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
    _bumpControls();
    setState(() {
      _resolving = false;
      _status = '';
    });
  }

  Future<void> _disposePlayer() async {
    final VideoPlayerController? c = _player;
    _player = null;
    try {
      await c?.dispose();
    } catch (_) {}
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
      _autoNextEpisode();
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
      final Duration pos = _player?.value.position ?? Duration.zero;
      if (_streamRetries <= 1) {
        await _disposePlayer();
        if (!mounted) return;
        setState(() {
          _resolving = true;
          _status = '';
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        _recovering = false;
        await _playSource(_sourceIndex, resumeAt: pos);
        return;
      }
      _recovering = false;
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = 'Playback failed — try another quality.';
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
    _player?.seekTo(Duration(milliseconds: ms.round()));
    _bumpControls();
  }

  void _seekBy(int seconds) {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    final Duration target = c.value.position + Duration(seconds: seconds);
    c.seekTo(target < Duration.zero ? Duration.zero : target);
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
              child: Text('Quality — Akwam',
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
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (i != _sourceIndex) {
                    _playSource(i,
                        resumeAt: _player?.value.position);
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
        if (_episode != null) 'Episode ${_episode!.number}',
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
                    fontFamily: 'Poppins',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
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
        _dragging ? Duration(milliseconds: _dragValue.round()) : (c?.value.position ?? Duration.zero);
    final Duration duration = c?.value.duration ?? Duration.zero;
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
                        fontFamily: 'Poppins',
                        fontSize: 10.5,
                        color: Colors.white70)),
                Expanded(
                  child: SliderTheme(
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
                ),
                Text(_fmt(duration),
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.5,
                        color: Colors.white70)),
              ],
            ),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _showQualitySheet,
                  child: Text(
                    'HQ ${_sources.isNotEmpty ? _sources[_sourceIndex].quality : ''}',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AkwamColors.teal),
                  ),
                ),
                const Spacer(),
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
                  tooltip: 'Speed',
                  color: AppColors.surface,
                  icon: Text('${_speed.toStringAsFixed(1)}×',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  itemBuilder: (BuildContext ctx) => <PopupMenuEntry<double>>[
                    for (final double s in <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                      PopupMenuItem<double>(
                        value: s,
                        child: Text('${s.toStringAsFixed(2)}×',
                            style: TextStyle(
                                fontFamily: 'Poppins',
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
                      fontFamily: 'Poppins',
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
                    fontFamily: 'Poppins',
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
                    child: Text('Pick quality',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AkwamColors.teal)),
                  ),
                TextButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _playSource(_sourceIndex);
                  },
                  child: Text('Retry',
                      style: TextStyle(
                          fontFamily: 'Poppins',
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
