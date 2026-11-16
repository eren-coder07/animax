import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/app_theme.dart';
import '../core/egy_api.dart';
import 'egy_tab.dart' show EgyColors;

/// Native player for the EgyDead section (ExoPlayer via `video_player`).
///
/// Fixes baked in (also applied to the other players):
///  * **Lifecycle** — pauses when the app is backgrounded, resumes on return
///    (previously playback kept running or left a black surface).
///  * **Mid-stream errors** — the controller is monitored; a failing stream
///    auto-retries once, then falls through to the next server instead of
///    freezing on a black frame forever.
///  * **Seek bar scrubbing** — dragging only updates the thumb; the real
///    `seekTo` fires once on release (ExoPlayer otherwise stutters, seeking
///    on every drag tick).
///  * **CDN headers** — `Referer: https://egybestvid.com/` is sent on every
///    manifest + segment request; the CDN 403s without it (verified live).
///  * **Auto-next** — when an episode finishes, the next one starts
///    automatically when available.
class EgyPlayerScreen extends StatefulWidget {
  const EgyPlayerScreen({
    super.key,
    required this.title,
    required this.servers,
    this.season = 0,
    this.episode = 0,
    this.episodes = const <EgyEpisode>[],
  });

  final EgyTitle title;
  final List<EgyVideo> servers;
  final int season;
  final int episode;
  final List<EgyEpisode> episodes;

  @override
  State<EgyPlayerScreen> createState() => _EgyPlayerScreenState();
}

class _EgyPlayerScreenState extends State<EgyPlayerScreen>
    with WidgetsBindingObserver {
  late List<EgyVideo> _servers;
  int _serverIndex = 0;
  int _retryCount = 0;

  VideoPlayerController? _player;
  ResolvedStream? _stream;
  bool _resolving = true;
  String? _error;
  String _status = '';

  bool _landscape = false;
  bool _controlsVisible = true;
  bool _muted = false;
  bool _dragging = false;
  double _dragValue = 0;
  double _speed = 1.0;
  Timer? _hideTimer;

  static const MethodChannel _channel = MethodChannel('animax/app');

  /// Browser UA sent with every player request.
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _servers = widget.servers;
    unawaited(_open(_serverIndex));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
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

  // ----- Lifecycle (pause in background) -----

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
      // Do not force-play (respect the user's pause), just refresh the UI.
      if (mounted) setState(() {});
    }
  }

  // ----- Playback chain -----

  Future<void> _open(int serverIndex, {Duration? resumeAt}) async {
    _hideTimer?.cancel();
    await _disposePlayer();
    if (!mounted) return;
    setState(() {
      _serverIndex = serverIndex;
      _stream = null;
      _error = null;
      _resolving = true;
      _retryCount = 0;
      _status = 'Resolving ${_serverName(serverIndex)}…';
    });

    final EgyVideo video = _servers[serverIndex];
    ResolvedStream? rs;
    String? resolveError;
    try {
      await EgyApi.I.loadCookies();
      rs = await EgyApi.I.resolveVideo(video).timeout(
            const Duration(seconds: 18),
            onTimeout: () => null,
          );
    } on EgyChallengeException {
      resolveError = 'egydead.ca needs a Cloudflare check.\n'
          'Open the EgyDead tab and verify access, then try again.';
    } catch (e) {
      resolveError = 'Could not resolve a stream (${e.toString().split('\n').first}).';
    }

    if (!mounted) return;
    if (rs == null) {
      // Try the next server automatically before giving up.
      final int next = serverIndex + 1;
      if (next < _servers.length) {
        setState(() {
          _status = '${_serverName(serverIndex)} unavailable — trying '
              '${_serverName(next)}…';
        });
        unawaited(_open(next));
        return;
      }
      setState(() {
        _resolving = false;
        _error = resolveError ?? 'No playable stream found.';
      });
      return;
    }

    setState(() {
      _stream = rs;
      _status = 'Connecting…';
    });
    await _startPlayer(rs, resumeAt: resumeAt);
  }

  Future<void> _startPlayer(ResolvedStream rs, {Duration? resumeAt}) async {
    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      Uri.parse(rs.url),
      httpHeaders: <String, String>{
        'User-Agent': _ua,
        if (rs.referer.isNotEmpty) 'Referer': rs.referer,
      },
      formatHint: rs.isHls ? VideoFormat.hls : VideoFormat.other,
    );
    _player = controller;
    controller.addListener(() => _playerListener(controller));
    setState(() {});
    try {
      await controller.initialize();
    } catch (e) {
      if (!mounted) return;
      await _handleStartupFailure(e.toString());
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
    if (_speed != 1.0) await controller.setPlaybackSpeed(_speed);
    await controller.play();
    _setKeepScreenOn(true);
    _bumpControls();
    setState(() {
      _resolving = false;
      _status = '';
    });
  }

  /// initialize() failed — retry once, then fall through to the next server.
  Future<void> _handleStartupFailure(String detail) async {
    await _disposePlayer();
    _retryCount++;
    if (_retryCount <= 1) {
      setState(() => _status = 'Retrying stream…');
      final ResolvedStream? rs = _stream;
      if (rs != null) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        await _startPlayer(rs);
        return;
      }
    }
    final int next = _serverIndex + 1;
    if (next < _servers.length) {
      setState(() {
        _status = '${_serverName(_serverIndex)} failed — trying '
            '${_serverName(next)}…';
      });
      unawaited(_open(next));
      return;
    }
    if (mounted) {
      setState(() {
        _resolving = false;
        _error = 'Player could not open the stream.\n$detail';
      });
    }
  }

  /// Runtime listener: catches mid-playback errors + auto-next on completion.
  void _playerListener(VideoPlayerController c) {
    if (!mounted || _player != c) return;
    final VideoPlayerValue v = c.value;
    if (v.hasError && !_resolving) {
      // Mid-stream failure (expired signed URL, network drop…).
      _onStreamDied(v.errorDescription ?? 'unknown error');
      return;
    }
    if (v.isCompleted && !_resolving) {
      _autoNext();
    }
    // Rebuild for position/buffering ticks when controls are visible.
    if (_controlsVisible && mounted) setState(() {});
  }

  bool _recovering = false;

  /// Whether a next episode exists for the auto-advance row.
  bool get _hasNext {
    if (widget.episode <= 0) return false;
    final List<EgyEpisode> eps = widget.episodes;
    final int idx = eps.indexWhere((EgyEpisode e) => e.number == widget.episode);
    return idx >= 0 && idx + 1 < eps.length && eps[idx + 1].videos.isNotEmpty;
  }

  Future<void> _onStreamDied(String detail) async {
    if (_recovering) return;
    _recovering = true;
    try {
      _retryCount++;
      if (_retryCount <= 2) {
        // Same server: signed URLs can expire mid-play — re-resolve.
        final Duration pos = _player?.value.position ?? Duration.zero;
        await _disposePlayer();
        if (!mounted) return;
        setState(() {
          _resolving = true;
          _status = 'Stream interrupted — reconnecting…';
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        _recovering = false;
        await _open(_serverIndex, resumeAt: pos);
        return;
      }
      final int next = _serverIndex + 1;
      if (next < _servers.length) {
        await _disposePlayer();
        if (!mounted) return;
        setState(() {
          _resolving = true;
          _status = 'Switching to ${_serverName(next)}…';
        });
        _recovering = false;
        await _open(next);
        return;
      }
      await _disposePlayer();
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

  Future<void> _disposePlayer() async {
    final VideoPlayerController? c = _player;
    _player = null;
    try {
      await c?.dispose();
    } catch (_) {}
  }

  void _autoNext() {
    if (widget.episode <= 0) return; // movies: nothing to advance
    final List<EgyEpisode> eps = widget.episodes;
    final int idx =
        eps.indexWhere((EgyEpisode e) => e.number == widget.episode);
    if (idx < 0 || idx + 1 >= eps.length) return;
    final EgyEpisode next = eps[idx + 1];
    if (next.videos.isEmpty) return;
    _setKeepScreenOn(false);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => EgyPlayerScreen(
        title: widget.title,
        servers: next.videos,
        season: widget.season,
        episode: next.number,
        episodes: eps,
      ),
    ));
  }

  // ----- Server switching (keeps position when swapping quality/server) -----

  Future<void> _switchServer(int index) async {
    if (index == _serverIndex || _resolving) return;
    final Duration pos =
        _player?.value.isInitialized == true ? _player!.value.position : Duration.zero;
    _retryCount = 0;
    await _open(index, resumeAt: pos > Duration.zero ? pos : null);
  }

  // ----- Controls -----

  void _setKeepScreenOn(bool keep) {
    _channel
        .invokeMethod<bool>('setKeepScreenOn', <String, dynamic>{'keep': keep})
        .catchError((Object e) => false);
  }

  void _bumpControls() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    final bool playing =
        _player?.value.isInitialized == true && _player!.value.isPlaying;
    _hideTimer = Timer(
      Duration(milliseconds: playing ? 3500 : 60000),
      () {
        if (mounted) setState(() => _controlsVisible = false);
      },
    );
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

  void _seekBy(int seconds) {
    final VideoPlayerController? c = _player;
    if (c == null || !c.value.isInitialized) return;
    Duration target = c.value.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (c.value.duration > Duration.zero && target > c.value.duration) {
      target = c.value.duration;
    }
    c.seekTo(target);
    _bumpControls();
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

  void _hide() {
    _hideTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = false);
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

  /// Retry button on the error card.
  void retryFromError() {
    setState(() {
      _error = null;
      _resolving = true;
    });
    _open(_serverIndex);
  }

  String _serverName(int i) {
    final EgyVideo v = _servers[i];
    return v.name.isEmpty ? 'server ${i + 1}' : v.name;
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
    final String subLabel = widget.season > 0
        ? 'S${widget.season} • E${widget.episode > 0 ? widget.episode : 1}'
        : 'Movie';
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_controlsVisible && _player?.value.isPlaying == true) {
            _hide();
          } else {
            _bumpControls();
          }
        },
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
                    _TopBar(state: this, subLabel: subLabel),
                    const Spacer(),
                    _CenterControls(state: this),
                    _BottomControls(state: this),
                  ],
                ),
              ),
            ),
            if (_resolving) _StatusCard(state: this),
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

  final _EgyPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = state._player;
    if (player == null || !player.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (state.widget.title.hasBackdrop)
            Image.network(state.widget.title.backdrop,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF101010)))
          else
            const ColoredBox(color: Color(0xFF101010)),
          const Center(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                  color: EgyColors.red, strokeWidth: 2.4),
            ),
          ),
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
// Top bar
// =============================================================================

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, required this.subLabel});

  final _EgyPlayerScreenState state;
  final String subLabel;

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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      child: Row(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (state._landscape) {
                state._toggleOrientation();
              } else {
                Navigator.of(context).pop();
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
                Text(state.widget.title.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(subLabel,
                    maxLines: 1,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.5,
                        color: Colors.white70)),
              ],
            ),
          ),
          if (state._servers.length > 1)
            _OverlayMenuButton<int>(
              icon: Icons.dns_rounded,
              label: '${state._serverIndex + 1}/${state._servers.length}',
              entries: <(String, VoidCallback)>[
                for (int i = 0; i < state._servers.length; i++)
                  (
                    state._servers[i].name.isEmpty
                        ? 'Server ${i + 1}'
                        : state._servers[i].name,
                    () => state._switchServer(i),
                  ),
              ],
            ),
          const SizedBox(width: 4),
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
        ],
      ),
    );
  }
}

// =============================================================================
// Center + bottom controls
// =============================================================================

class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.state});

  final _EgyPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = state._player;
    final bool playing = c?.value.isInitialized == true && c!.value.isPlaying;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.replay_10_rounded,
              color: Colors.white, size: 32),
          onPressed: () => state._seekBy(-10),
        ),
        const SizedBox(width: 26),
        InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: state._togglePlay,
          child: Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: EgyColors.red,
              shape: BoxShape.circle,
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ),
        const SizedBox(width: 26),
        IconButton(
          icon: const Icon(Icons.forward_10_rounded,
              color: Colors.white, size: 32),
          onPressed: () => state._seekBy(10),
        ),
      ],
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.state});

  final _EgyPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = state._player;
    if (player == null || !player.value.isInitialized) {
      return const SizedBox(height: 66);
    }
    final VideoPlayerValue v = player.value;
    final double max =
        v.duration.inMilliseconds > 0 ? v.duration.inMilliseconds.toDouble() : 1.0;
    final double pos = v.position.inMilliseconds
        .clamp(0, max.toInt())
        .toDouble();
    final double shown = state._dragging ? state._dragValue : pos;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 26, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // --- Seek bar (scrub-safe: seek fires on release) ---
          Row(
            children: <Widget>[
              Text(state._fmt(v.position),
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10.5,
                      color: Colors.white)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 13),
                    activeTrackColor: EgyColors.red,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: EgyColors.red,
                    overlayColor: EgyColors.red.withValues(alpha: 0.25),
                  ),
                  child: Slider(
                    value: shown,
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
              Text(state._fmt(v.duration),
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10.5,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 2),
          // --- Speed / fullscreen ---
          Row(
            children: <Widget>[
              _OverlayMenuButton<double>(
                icon: Icons.speed_rounded,
                label: '${_speedLabel(state._speed)}x',
                entries: const <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                    .map((double s) => (
                          '${_speedLabel(s)}x',
                          () => state._setSpeed(s),
                        ))
                    .toList(),
              ),
              if (state.widget.episode > 0 && state._hasNext)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextButton.icon(
                    onPressed: state._autoNext,
                    icon: const Icon(Icons.skip_next_rounded,
                        size: 18, color: Colors.white),
                    label: const Text('Next episode',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              const Spacer(),
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
}

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
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Status + error cards
// =============================================================================

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final _EgyPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: EgyColors.red, strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  state._status.isEmpty ? 'Loading…' : state._status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.state});

  final _EgyPlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded,
                color: EgyColors.red, size: 40),
            const SizedBox(height: 12),
            Text('Playback problem',
                style: AppText.bodyBold.copyWith(fontSize: 14)),
            const SizedBox(height: 6),
            Text(state._error!,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(fontSize: 11.5, height: 1.5)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                TextButton.icon(
                  onPressed: state.retryFromError,
                  icon: const Icon(Icons.refresh_rounded,
                      size: 18, color: Colors.white),
                  label: const Text('Retry',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          color: Colors.white)),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded,
                      size: 18, color: Colors.white70),
                  label: const Text('Back',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          color: Colors.white70)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
