/// Platform-aware video playback for Animax.
///
/// `video_player` (ExoPlayer on Android, AVFoundation on iOS/macOS) ships
/// **no Windows implementation**, so on Windows this swaps in `media_kit`
/// (libmpv): the player screens keep the exact same code, only the engine
/// underneath changes. Android keeps ExoPlayer and behaves exactly like
/// before.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

/// Immutable playback snapshot used by the player screens.
///
/// Mirrors the subset of `VideoPlayerValue` Animax actually reads: position,
/// duration, buffering, playing, initialized and aspect ratio.
@immutable
class AnimaxPlayerValue {
  const AnimaxPlayerValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.aspectRatio = 0,
  });

  /// Same shape as `VideoPlayerValue.uninitialized()`.
  const AnimaxPlayerValue.uninitialized() : this();

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;

  /// Width / height of the video; `0` while unknown (stages fall back to 16:9).
  final double aspectRatio;

  AnimaxPlayerValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    double? aspectRatio,
  }) {
    return AnimaxPlayerValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }
}

/// Engine-agnostic player handle shared by both player screens.
///
/// Created through [AnimaxPlayerController.create]; the returned
/// implementation depends on the host platform:
///
/// * Windows → mpv through `media_kit` (+ `media_kit_libs_windows_video`).
/// * Everywhere else → `video_player` exactly as before.
abstract class AnimaxPlayerController extends ChangeNotifier {
  factory AnimaxPlayerController.create() {
    if (Platform.isWindows) return _MpvPlayerController();
    return _ExoPlayerController();
  }

  AnimaxPlayerController._();

  /// Latest playback snapshot; the UI rebuilds through [notifyListeners].
  AnimaxPlayerValue get value;

  /// Opens [url] and waits until the stream is actually playable — throws
  /// when the engine cannot open it (screens then fall back to the next
  /// server, mirroring `initialize()` throwing on `video_player`).
  Future<void> load(
    String url, {
    Map<String, String> headers = const <String, String>{},
    bool isHls = false,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);

  /// [volume] is 0..1 (matches `video_player` semantics).
  Future<void> setVolume(double volume);
  Future<void> setPlaybackSpeed(double speed);

  @override
  Future<void> dispose();
}

/// Platform video surface for an [AnimaxPlayerController].
///
/// Mobile renders the classic `VideoPlayer` texture; Windows renders the
/// `media_kit` `Video` widget with **no** built-in controls — Animax paints
/// its own overlay on top, exactly like on Android.
class AnimaxVideo extends StatelessWidget {
  const AnimaxVideo({super.key, required this.player});

  final AnimaxPlayerController player;

  @override
  Widget build(BuildContext context) {
    if (player is _MpvPlayerController) {
      return Video(
        controller: (player as _MpvPlayerController).videoController,
        controls: NoVideoControls,
        fit: BoxFit.contain,
      );
    }
    final VideoPlayerController? native =
        (player as _ExoPlayerController)._native;
    if (native == null) return const SizedBox.shrink();
    return VideoPlayer(native);
  }
}

// ---------------------------------------------------------------------------
// video_player backend — Android / iOS / macOS (unchanged behavior)
// ---------------------------------------------------------------------------

class _ExoPlayerController extends AnimaxPlayerController {
  _ExoPlayerController() : super._();

  VideoPlayerController? _native;
  AnimaxPlayerValue _value = const AnimaxPlayerValue();
  bool _disposed = false;

  @override
  AnimaxPlayerValue get value => _value;

  void _sync() {
    if (_disposed) return;
    final VideoPlayerController? c = _native;
    if (c == null) return;
    final VideoPlayerValue v = c.value;
    _value = AnimaxPlayerValue(
      isInitialized: v.isInitialized,
      isPlaying: v.isPlaying,
      isBuffering: v.isBuffering,
      position: v.position,
      duration: v.duration,
      aspectRatio: v.aspectRatio,
    );
    notifyListeners();
  }

  @override
  Future<void> load(
    String url, {
    Map<String, String> headers = const <String, String>{},
    bool isHls = false,
  }) async {
    if (_disposed) return;
    _value = const AnimaxPlayerValue(isBuffering: true);
    notifyListeners();
    final VideoPlayerController c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers,
      // ExoPlayer cannot infer HLS from the backend's CDN paths; the explicit
      // hint forces the correct media parser.
      formatHint: isHls ? VideoFormat.hls : VideoFormat.other,
    );
    _native = c;
    c.addListener(_sync);
    try {
      await c.initialize();
    } catch (_) {
      c.removeListener(_sync);
      if (identical(_native, c) && !_disposed) {
        _native = null;
        _value = const AnimaxPlayerValue();
        notifyListeners();
      }
      try {
        await c.dispose();
      } catch (_) {}
      rethrow;
    }
    c.removeListener(_sync);
    if (identical(_native, c) && !_disposed) {
      _sync();
    } else {
      // A newer load() (or dispose) superseded this controller.
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  @override
  Future<void> play() async => _native?.play();
  @override
  Future<void> pause() async => _native?.pause();
  @override
  Future<void> seekTo(Duration position) async => _native?.seekTo(position);
  @override
  Future<void> setVolume(double volume) async => _native?.setVolume(volume);
  @override
  Future<void> setPlaybackSpeed(double speed) async =>
      _native?.setPlaybackSpeed(speed);

  @override
  Future<void> dispose() async {
    _disposed = true;
    final VideoPlayerController? c = _native;
    _native = null;
    c?.removeListener(_sync);
    try {
      await c?.dispose();
    } catch (_) {}
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// media_kit backend — Windows (libmpv)
// ---------------------------------------------------------------------------

class _MpvPlayerController extends AnimaxPlayerController {
  _MpvPlayerController() : super._() {
    final Player player = Player();
    _player = player;
    videoController = VideoController(player);
    final PlayerStream s = player.stream;
    _subs = <StreamSubscription<dynamic>>[
      s.position.listen((Duration d) => _set(position: d)),
      s.duration.listen((Duration d) => _set(duration: d)),
      s.playing.listen((bool b) => _set(isPlaying: b)),
      s.buffering.listen((bool b) => _set(isBuffering: b)),
      s.completed.listen((bool done) {
        if (done) _set(isPlaying: false);
      }),
      s.videoParams.listen((VideoParams p) {
        final int w = p.w ?? 0;
        final int h = p.h ?? 0;
        _set(aspectRatio: (w > 0 && h > 0) ? w / h : 0);
      }),
    ];
  }

  Player? _player;
  late final VideoController videoController;
  List<StreamSubscription<dynamic>> _subs =
      const <StreamSubscription<dynamic>>[];
  AnimaxPlayerValue _value = const AnimaxPlayerValue();
  bool _disposed = false;

  /// mpv opens dead URLs without raising anything — this is how long [load]
  /// waits for a real readiness signal before giving up and letting the
  /// screen fall through to the next server.
  static const Duration _openTimeout = Duration(seconds: 12);

  @override
  AnimaxPlayerValue get value => _value;

  void _set({
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    double? aspectRatio,
  }) {
    if (_disposed) return;
    _value = AnimaxPlayerValue(
      isInitialized: _value.isInitialized,
      isPlaying: isPlaying ?? _value.isPlaying,
      isBuffering: isBuffering ?? _value.isBuffering,
      position: position ?? _value.position,
      duration: duration ?? _value.duration,
      aspectRatio: aspectRatio ?? _value.aspectRatio,
    );
    notifyListeners();
  }

  @override
  Future<void> load(
    String url, {
    Map<String, String> headers = const <String, String>{},
    bool isHls = false,
  }) async {
    if (_disposed) return;
    final Player p = _player!;
    _value = const AnimaxPlayerValue(isBuffering: true);
    notifyListeners();

    // HLS/MP4 needs no explicit format hint — mpv demuxes it automatically.
    await p.open(Media(url, httpHeaders: headers), play: false);

    final Completer<String> failed = Completer<String>();
    final StreamSubscription<String> errSub =
        p.stream.error.listen((String e) {
      if (!failed.isCompleted) failed.complete(e);
    });

    bool ready = false;
    final Stopwatch sw = Stopwatch()..start();
    while (!_disposed &&
        !failed.isCompleted &&
        sw.elapsed < _openTimeout &&
        !ready) {
      if (_value.duration > Duration.zero || _value.aspectRatio > 0) {
        ready = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    await errSub.cancel();
    if (_disposed) return;

    if (!ready) {
      final String reason =
          failed.isCompleted ? await failed.future : 'timed out opening';
      if (!_disposed) {
        _value = const AnimaxPlayerValue();
        notifyListeners();
      }
      throw Exception('media_kit: $reason — ${Uri.parse(url).host}');
    }

    _value = _value.copyWith(isInitialized: true);
    notifyListeners();
  }

  @override
  Future<void> play() async {
    if (!_disposed) await _player!.play();
  }

  @override
  Future<void> pause() async {
    if (!_disposed) await _player!.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (!_disposed) await _player!.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_disposed) await _player!.setVolume((volume * 100).clamp(0, 100));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    if (!_disposed) await _player!.setRate(speed);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final List<StreamSubscription<dynamic>> subs = _subs;
    _subs = const <StreamSubscription<dynamic>>[];
    for (final StreamSubscription<dynamic> sub in subs) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    super.dispose();
  }
}
