import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../widgets/mb_ui.dart';

/// Plays a downloaded video from the device — no internet needed.
class OfflinePlayerScreen extends StatefulWidget {
  const OfflinePlayerScreen({super.key, required this.item});
  final DownloadItem item;

  @override
  State<OfflinePlayerScreen> createState() => _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState extends State<OfflinePlayerScreen> {
  VideoPlayerController? _c;
  String? _error;
  bool _controls = true;
  bool _landscape = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _open();
  }

  Future<void> _open() async {
    final String u = widget.item.resultUri;
    final VideoPlayerController c = u.startsWith('content://')
        ? VideoPlayerController.contentUri(Uri.parse(u))
        : VideoPlayerController.file(File(u));
    _c = c;
    c.addListener(() {
      if (mounted) setState(() {});
    });
    try {
      await c.initialize();
      await c.play();
      _bump();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذّر تشغيل الملف — ربما حُذف من الجهاز.');
      }
    }
  }

  void _bump() {
    _hide?.cancel();
    setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) {
        setState(() => _controls = false);
      }
    });
  }

  void _toggleOrientation() {
    _landscape = !_landscape;
    SystemChrome.setPreferredOrientations(_landscape
        ? <DeviceOrientation>[
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight
          ]
        : <DeviceOrientation>[DeviceOrientation.portraitUp]);
    setState(() {});
  }

  void _seekBy(int s) {
    final VideoPlayerController? c = _c;
    if (c == null || !c.value.isInitialized) return;
    c.seekTo(c.value.position + Duration(seconds: s));
    _bump();
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(
        <DeviceOrientation>[DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _c;
    final bool ready = c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Directionality(
        textDirection: TextDirection.ltr,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _bump,
          onDoubleTapDown: (TapDownDetails d) => _seekBy(
              d.localPosition.dx < MediaQuery.sizeOf(context).width / 2
                  ? -10
                  : 10),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Center(
                child: ready
                    ? AspectRatio(
                        aspectRatio: c.value.aspectRatio == 0
                            ? 16 / 9
                            : c.value.aspectRatio,
                        child: VideoPlayer(c))
                    : _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                    fontFamily: kFont,
                                    fontSize: 15,
                                    color: Colors.white)),
                          )
                        : const CircularProgressIndicator(
                            color: AppColors.brandGreen),
              ),
              AnimatedOpacity(
                opacity: _controls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controls,
                  child: _overlay(c, ready),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlay(VideoPlayerController? c, bool ready) {
    final Duration pos = ready ? c!.value.position : Duration.zero;
    final Duration dur = ready ? c!.value.duration : Duration.zero;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xAA000000), Color(0x00000000), Color(0xAA000000)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                      widget.item.subtitle.isEmpty
                          ? widget.item.title
                          : '${widget.item.title} · ${widget.item.subtitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                          fontFamily: kFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
                IconButton(
                  tooltip: 'إرسال لصديق',
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: () => DownloadManager.I.shareFile(widget.item),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.offline_pin_rounded,
                      color: AppColors.brandGreen, size: 22),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  iconSize: 38,
                  icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                  onPressed: () => _seekBy(-10),
                ),
                const SizedBox(width: 22),
                IconButton(
                  iconSize: 56,
                  icon: Icon(
                      ready && c!.value.isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: Colors.white),
                  onPressed: !ready
                      ? null
                      : () {
                          c!.value.isPlaying ? c.pause() : c.play();
                          _bump();
                        },
                ),
                const SizedBox(width: 22),
                IconButton(
                  iconSize: 38,
                  icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                  onPressed: () => _seekBy(10),
                ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 6, 6),
              child: Row(
                children: <Widget>[
                  Text(_fmt(pos),
                      style: const TextStyle(
                          fontFamily: kFont, fontSize: 12, color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: dur.inMilliseconds <= 0
                          ? 0
                          : pos.inMilliseconds
                              .clamp(0, dur.inMilliseconds)
                              .toDouble(),
                      max: dur.inMilliseconds <= 0
                          ? 1
                          : dur.inMilliseconds.toDouble(),
                      activeColor: AppColors.brandGreen,
                      inactiveColor: Colors.white24,
                      onChanged: !ready
                          ? null
                          : (double v) {
                              c!.seekTo(Duration(milliseconds: v.round()));
                              _bump();
                            },
                    ),
                  ),
                  Text(_fmt(dur),
                      style: const TextStyle(
                          fontFamily: kFont, fontSize: 12, color: Colors.white)),
                  IconButton(
                    icon: Icon(
                        _landscape
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        color: Colors.white),
                    onPressed: _toggleOrientation,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
