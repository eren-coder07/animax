import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/app_theme.dart';
import '../core/hh_api.dart';
import '../core/hls_quality.dart';
import '../core/stream_resolver.dart' show ResolvedStream;
import '../widgets/player_gestures.dart';
import 'hentai_tab.dart';

/// Native (ExoPlayer) player for the +18 section.
///
/// Resolves the episode's direct HLS playlist from hentaihaven.xxx and plays
/// it with the platform player through `video_player` — no WebView. Includes
/// prev/next episode navigation, speed, mute, and immersive fullscreen.
class HhPlayerScreen extends StatefulWidget {
  const HhPlayerScreen({super.key});

  @override
  State<HhPlayerScreen> createState() => _HhPlayerScreenState();
}

class _HhPlayerScreenState extends State<HhPlayerScreen>
    with WidgetsBindingObserver {
  HhSeries _series =
      const HhSeries(id: 0, slug: '', title: '', thumb: '');
  int _episode = 1;
  List<HhEpisode> _episodes = const <HhEpisode>[];

  VideoPlayerController? _player;
  HhStream? _stream;
  bool _resolving = true;
  String? _error;
  String _status = '';

  bool _landscape = false;
  bool _controlsVisible = true;
  bool _muted = false;
  double _speed = 1.0;
  Timer? _hideTimer;
  Timer? _positionTicker;

  /// Scrub state — seek fires once on release (ExoPlayer stutters when
  /// seeked on every drag tick).
  bool _dragging = false;
  double _dragValue = 0;

  /// Mid-stream recovery state (see [_onStreamDied]).
  bool _recovering = false;
  int _streamRetries = 0;

  static const MethodChannel _channel = MethodChannel('animax/app');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// Pause playback when the app goes to the background.
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
    if (args is ({HhSeries series, int episode})) {
      if (args.series.slug != _series.slug ||
          args.episode != _episode) {
        _series = args.series;
        _episode = args.episode;
        _loadEpisodeList();
        _open(_episode);
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

  Future<void> _loadEpisodeList() async {
    if (_series.slug.isEmpty) return;
    try {
      final List<HhEpisode> eps = await HentaiApi.I.episodes(_series.slug);
      if (!mounted) return;
      setState(() => _episodes = eps);
    } catch (_) {
      // Navigation simply stays unavailable.
    }
  }

  // ----- Playback -----

  Future<void> _open(int episode, {Duration? resumeAt}) async {
    _positionTicker?.cancel();
    _hideTimer?.cancel();
    await _disposePlayer();
    if (!mounted) return;
    setState(() {
      _episode = episode;
      _stream = null;
      _error = null;
      _resolving = true;
      _status = 'Loading…';
    });
    HhStream? stream;
    String? error;
    try {
      stream = await HentaiApi.I.resolveStream(_series.slug, episode);
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach the source — check your connection.';
    }
    if (!mounted) return;
    if (stream == null) {
      setState(() {
        _resolving = false;
        _error = error ?? 'Stream unavailable.';
      });
      return;
    }
    setState(() {
      _stream = stream;
      _status = '';
    });
    // Bandwidth-based auto quality: on HLS master playlists pick the variant
    // that fits the measured throughput (Wi-Fi/cellular aware).
    String playUrl = stream.url;
    try {
      final ResolvedStream auto = await HlsQuality.autoSelect(ResolvedStream(
        url: stream.url,
        qualities: <String, String>{'Auto': stream.url},
        referer: '${HentaiApi.frontBase}/',
      ));
      playUrl = auto.url;
    } catch (_) {}
    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      Uri.parse(playUrl),
      httpHeaders: <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        'Referer': '${HentaiApi.frontBase}/',
      },
      // HLS is intentional: ExoPlayer cannot infer it from the CDN path.
      formatHint: stream.isHls ? VideoFormat.hls : VideoFormat.other,
    );
    _player = controller;
    controller.addListener(() => _playerListener(controller));
    setState(() {});
    try {
      await controller.initialize();
    } catch (e) {
      if (!mounted) return;
      await _disposePlayer();
      setState(() {
        _resolving = false;
        _error = 'Player failed to open the stream.\n$e';
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
    _positionTicker =
        Timer.periodic(const Duration(milliseconds: 400), (_) {
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

  /// Runtime listener: catches mid-playback failures and auto-advances on
  /// completion (before this, a dying stream froze on a black frame).
  void _playerListener(VideoPlayerController c) {
    if (!mounted || _player != c) return;
    final VideoPlayerValue v = c.value;
    if (v.hasError && !_resolving) {
      _onStreamDied(v.errorDescription ?? 'unknown error');
      return;
    }
    if (v.isCompleted && !_resolving) {
      _autoNextEpisode();
    }
  }

  void _autoNextEpisode() {
    if (!_BottomControls._hasEp(this, 1)) return;
    _switchEpisode(_episode + 1);
  }

  /// Mid-stream failure recovery: re-open the stream once (CDN hiccups),
  /// then give up with a visible error.
  Future<void> _onStreamDied(String detail) async {
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
        if (!mounted) return;
        _recovering = false;
        await _open(_episode, resumeAt: pos);
        return;
      }
      _recovering = false;
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = 'Playback failed: $detail';
        });
      }
    } catch (_) {
      _recovering = false;
    }
  }

  Future<void> _retry() => _open(_episode);

  void _setKeepScreenOn(bool keep) {
    _channel
        .invokeMethod<bool>('setKeepScreenOn', <String, dynamic>{'keep': keep})
        .catchError((Object e) => false);
  }

  void _switchEpisode(int n) {
    if (n == _episode) return;
    _open(n);
  }

  // ----- Controls -----

  void _bumpControls() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    final bool playing = _player?.value.isInitialized == true &&
        _player!.value.isPlaying;
    _hideTimer = Timer(
        Duration(milliseconds: playing ? 3500 : 60000), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _togglePlay() {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    c.value.isPlaying ? c.pause() : c.play();
    _bumpControls();
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

  void _seekBy(int seconds) {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    final Duration target = c.value.position +
        Duration(seconds: seconds);
    c.seekTo(
        target < Duration.zero ? Duration.zero : target);
    _bumpControls();
  }

  /// Gesture-layer hooks (PlayerGestureOverlay).
  void _seekRel(int seconds) => _seekBy(seconds);

  bool _locked = false;

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
    c.setVolume(value);
    if (value > 0 && _muted) {
      setState(() => _muted = false);
    }
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

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  // ----- Build -----

  @override
  Widget build(BuildContext context) {
    final String episodeLabel = 'Episode $_episode'
        '${_episodes.isNotEmpty ? ' of ${_episodes.length}' : ''}';
    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayerGestureOverlay(
        onTap: _bumpControls,
        onSeek: _seekRel,
        onSpeedBoost: _onSpeedBoost,
        onVolume: _onVolume,
        onBrightness: (double _) {},
        locked: _locked,
        onLockTap: _toggleLock,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _VideoArea(state: this),
            // Controls overlay
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Column(
                  children: <Widget>[
                    _TopBar(state: this, episodeLabel: episodeLabel),
                    const Spacer(),
                    _CenterControls(state: this),
                    _BottomControls(state: this),
                  ],
                ),
              ),
            ),
            // Resolving / error overlays
            if (_resolving) _ResolvingCard(state: this),
            if (!_resolving && _error != null) _ErrorCard(state: this),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Video area
// =============================================================================

class _VideoArea extends StatelessWidget {
  const _VideoArea({required this.state});

  final _HhPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = state._player;
    if (player == null || !player.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (state._stream?.poster.isNotEmpty == true)
            Image.network(state._stream!.poster,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFF101010)))
          else
            const ColoredBox(color: Color(0xFF101010)),
        ],
      );
    }
    final VideoPlayerValue v = player.value;
    return Center(
      child: AspectRatio(
        aspectRatio: v.aspectRatio <= 0 ? 16 / 9 : v.aspectRatio,
        child: VideoPlayer(player),
      ),
    );
  }
}

// =============================================================================
// Overlays
// =============================================================================

class _ResolvingCard extends StatelessWidget {
  const _ResolvingCard({required this.state});

  final _HhPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(
              color: HhColors.red, strokeWidth: 2.6),
          const SizedBox(height: 14),
          Text(state._status,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.state});

  final _HhPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded,
                color: HhColors.red, size: 42),
            const SizedBox(height: 14),
            Text('Playback failed',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 8),
            Text(state._error ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    height: 1.6,
                    color: Colors.white70)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: state._retry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: HhColors.red,
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text('Retry',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Controls
// =============================================================================

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, required this.episodeLabel});

  final _HhPlayerScreenState state;
  final String episodeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
      child: Row(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (state._landscape) {
                state._toggleOrientation();
              } else {
                Navigator.pop(context);
              }
            },
            child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(state._series.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(episodeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.5,
                        color: Colors.white70)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              state._muted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: state._toggleMute,
          ),
          IconButton(
            icon: Icon(
              state._locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: state._locked ? HhColors.red : Colors.white,
              size: 20,
            ),
            tooltip: state._locked ? 'Unlock controls' : 'Lock controls',
            onPressed: state._toggleLock,
          ),
          IconButton(
            icon: const Icon(Icons.picture_in_picture_rounded,
                color: Colors.white, size: 20),
            tooltip: 'Picture-in-Picture',
            onPressed: () async {
              await enterPipMode();
            },
          ),
          PopupMenuButton<double>(
            color: AppColors.surface,
            icon: const Icon(Icons.speed_rounded,
                color: Colors.white, size: 22),
            onSelected: state._setSpeed,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<double>>[
              for (final double s in <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                PopupMenuItem<double>(
                  value: s,
                  child: Text(
                      '${s}x${state._speed == s ? '  ✓' : ''}',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Colors.white)),
                ),
            ],
          ),
          IconButton(
            icon: Icon(
              state._landscape
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: Colors.white,
              size: 24,
            ),
            onPressed: state._toggleOrientation,
          ),
        ],
      ),
    );
  }
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.state});

  final _HhPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = state._player;
    final bool ready = player?.value.isInitialized == true;
    final bool playing = ready && player!.value.isPlaying;
    final bool buffering = ready && player!.value.isBuffering;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _RoundControl(
            icon: Icons.replay_10_rounded, onTap: () => state._seekBy(-10)),
        const SizedBox(width: 26),
        GestureDetector(
          onTap: state._togglePlay,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.45),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: buffering
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.2),
                  )
                : Icon(
                    ready && playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
          ),
        ),
        const SizedBox(width: 26),
        _RoundControl(
            icon: Icons.forward_10_rounded, onTap: () => state._seekBy(10)),
      ],
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.state});

  final _HhPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = state._player;
    final bool ready = player?.value.isInitialized == true;
    final VideoPlayerValue v = player?.value ?? const VideoPlayerValue.uninitialized();
    final Duration pos = ready ? v.position : Duration.zero;
    final Duration dur = ready && v.duration > Duration.zero
        ? v.duration
        : Duration(milliseconds: state._stream?.durationMs ?? 0);
    final double maxMs = dur.inMilliseconds.toDouble();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(state._fmt(pos),
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.white)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.4,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 13),
                    inactiveTrackColor: Colors.white24,
                    activeTrackColor: HhColors.red,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    // Scrub-safe: seek only on release.
                    value: maxMs > 0
                        ? (state._dragging
                                ? state._dragValue
                                : pos.inMilliseconds.toDouble())
                            .clamp(0, maxMs)
                        : 0,
                    max: maxMs > 0 ? maxMs : 1,
                    onChanged: maxMs > 0
                        ? (double ms) {
                            state.dragTo(ms);
                          }
                        : null,
                    onChangeEnd: maxMs > 0
                        ? (double ms) {
                            state.endDrag(state._player!, ms);
                          }
                        : null,
                  ),
                ),
              ),
              Text(dur > Duration.zero ? state._fmt(dur) : 'LIVE',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.white)),
            ],
          ),
          if (state._episodes.length > 1) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _EpNavButton(
                  label: 'Prev ep',
                  enabled: _hasEp(state, -1),
                  onTap: () => state._switchEpisode(state._episode - 1),
                ),
                _EpNavButton(
                  label: 'Next ep',
                  enabled: _hasEp(state, 1),
                  onTap: () => state._switchEpisode(state._episode + 1),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static bool _hasEp(_HhPlayerScreenState state, int delta) {
    final int n = state._episode + delta;
    if (state._episodes.isEmpty) return n >= 1;
    return state._episodes.any((HhEpisode e) => e.number == n);
  }
}

class _EpNavButton extends StatelessWidget {
  const _EpNavButton(
      {required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
      ),
    );
  }
}
