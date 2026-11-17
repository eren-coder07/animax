import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared gesture layer for the native players (anime + 18+).
///
/// Gestures:
///  * single tap        → toggle controls
///  * double tap        → seek −10 s (left half) / +10 s (right half)
///  * long press        → 2× speed boost while held
///  * vertical drag left side  → screen brightness
///  * vertical drag right side → player volume (fraction 0–1)
///
/// Feedback (seek ripple, 2× pill, brightness/volume HUD) is rendered by
/// this widget itself so both players get identical behaviour.
class PlayerGestureOverlay extends StatefulWidget {
  const PlayerGestureOverlay({
    super.key,
    required this.onTap,
    required this.onSeek,
    required this.onSpeedBoost,
    required this.onVolume,
    required this.onBrightness,
    required this.onLockTap,
    this.locked = false,
    required this.child,
  });

  final VoidCallback onTap;
  final ValueChanged<int> onSeek; // ±10
  final ValueChanged<bool> onSpeedBoost;
  final ValueChanged<double> onVolume; // delta −1..1
  final ValueChanged<double> onBrightness; // delta −1..1

  /// When locked only the unlock button works.
  final bool locked;
  final VoidCallback onLockTap;
  final Widget child;

  @override
  State<PlayerGestureOverlay> createState() => _PlayerGestureOverlayState();
}

class _PlayerGestureOverlayState extends State<PlayerGestureOverlay> {
  // Feedback state.
  int? _seekDir; // -1 / +1
  bool _boosting = false;
  double? _volHud; // 0..1
  double? _brightHud; // 0..1
  Timer? _hudTimer;

  double? _dragStartVol;
  double? _dragStartBright;

  void _flashHud() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() {
          _seekDir = null;
          _volHud = null;
          _brightHud = null;
          if (_boosting) {
            _boosting = false;
            widget.onSpeedBoost(false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.locked) {
      // Only the unlock button is interactive.
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          widget.child,
          Positioned(
            top: 8,
            left: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onLockTap,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.lock_rounded,
                      color: Colors.white, size: 19),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTapDown: (TapDownDetails d) {
            final RenderBox box = context.findRenderObject()! as RenderBox;
            final double x = d.localPosition.dx / box.size.width;
            final int dir = x < 0.5 ? -1 : 1;
            setState(() => _seekDir = dir);
            widget.onSeek(dir * 10);
            _flashHud();
          },
          onDoubleTap: () {},
          onLongPressStart: (LongPressStartDetails d) {
            setState(() => _boosting = true);
            widget.onSpeedBoost(true);
          },
          onLongPressEnd: (LongPressEndDetails d) {
            setState(() => _boosting = false);
            widget.onSpeedBoost(false);
          },
          onVerticalDragStart: (DragStartDetails d) {
            final RenderBox box = context.findRenderObject()! as RenderBox;
            final double x = d.localPosition.dx / box.size.width;
            if (x < 0.5) {
              _dragStartBright = _brightHud ?? SystemBrightness.current;
            } else {
              _dragStartVol = _volHud ?? 1.0;
            }
          },
          onVerticalDragUpdate: (DragUpdateDetails d) {
            final RenderBox box = context.findRenderObject()! as RenderBox;
            final double x = d.localPosition.dx / box.size.width;
            final double dy = -d.delta.dy / box.size.height; // up = +
            if (x < 0.5 && _dragStartBright != null) {
              setState(() => _brightHud =
                  (_dragStartBright! + dy * 1.5).clamp(0.01, 1.0));
              SystemBrightness.set(_brightHud!);
            } else if (x >= 0.5 && _dragStartVol != null) {
              setState(() => _volHud =
                  (_dragStartVol! + dy * 1.5).clamp(0.0, 1.0));
              widget.onVolume(_volHud!);
            }
            _flashHud();
          },
          onVerticalDragEnd: (DragEndDetails d) {
            _dragStartBright = null;
            _dragStartVol = null;
          },
          child: widget.child,
        ),
        // Seek ripple
        if (_seekDir != null)
          Align(
            alignment: _seekDir! < 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _seekDir! < 0
                          ? Icons.fast_rewind_rounded
                          : Icons.fast_forward_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    const SizedBox(height: 2),
                    Text('${_seekDir! < 0 ? '-' : '+'}10s',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        // 2× pill
        if (_boosting)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text('2× speed',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
        // Brightness HUD (left edge)
        if (_brightHud != null)
          Align(
            alignment: Alignment.centerLeft,
            child: _hud(Icons.brightness_6_rounded, _brightHud!),
          ),
        // Volume HUD (right edge)
        if (_volHud != null)
          Align(
            alignment: Alignment.centerRight,
            child: _hud(
                _volHud! <= 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                _volHud!),
          ),
      ],
    );
  }

  Widget _hud(IconData icon, double value) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 26),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            SizedBox(
              width: 90,
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: value,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Screen-brightness bridge (MethodChannel `animax/app` — see MainActivity).
class SystemBrightness {
  SystemBrightness._();

  static const MethodChannel _ch = MethodChannel('animax/app');
  static double _last = 0.5;

  static double get current => _last;

  static Future<void> set(double value) async {
    _last = value.clamp(0.01, 1.0);
    try {
      await _ch
          .invokeMethod<bool>('setBrightness', <String, dynamic>{
        'value': _last,
      });
    } catch (_) {
      // Channel unavailable (tests / non-Android) — ignore.
    }
  }

  static Future<void> reset() async {
    try {
      await _ch.invokeMethod<bool>('setBrightness', <String, dynamic>{
        'value': null,
      });
    } catch (_) {}
  }
}

/// Picture-in-Picture bridge.
Future<bool> enterPipMode() async {
  try {
    const MethodChannel ch = MethodChannel('animax/app');
    final bool? ok = await ch.invokeMethod<bool>('enterPip');
    return ok ?? false;
  } catch (_) {
    return false;
  }
}
