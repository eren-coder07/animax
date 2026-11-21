import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// The Animax "A" mark — rounded green triangle with a notch, drawn in code.
class AnimaxLogo extends StatelessWidget {
  const AnimaxLogo({super.key, this.size = 34, this.withWordmark = false});

  final double size;
  final bool withWordmark;

  @override
  Widget build(BuildContext context) {
    final Widget mark = CustomPaint(
      size: Size(size, size),
      painter: _LogoPainter(),
    );
    if (!withWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Text(
          'أنيماكس',
          style: AppText.h1.copyWith(fontSize: 22),
        ),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint paint = Paint()..color = AppColors.accent;
    final Path path = Path()
      ..moveTo(w * 0.475, h * 0.06)
      ..quadraticBezierTo(w * 0.5, h * -0.02, w * 0.525, h * 0.06) // rounded apex
      ..lineTo(w * 0.985, h * 0.86)
      ..quadraticBezierTo(w * 1.015, h * 0.94, w * 0.92, h * 0.94)
      ..lineTo(w * 0.60, h * 0.94)
      ..lineTo(w * 0.535, h * 0.78)
      ..quadraticBezierTo(w * 0.5, h * 0.68, w * 0.465, h * 0.78) // inner notch
      ..lineTo(w * 0.40, h * 0.94)
      ..lineTo(w * 0.08, h * 0.94)
      ..quadraticBezierTo(w * -0.015, h * 0.94, w * 0.015, h * 0.86)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
