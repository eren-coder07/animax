import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Shimmer skeleton placeholder used while catalogs / details load.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.radius = 14,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, _) {
        final double t = _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.6 + 2.4 * t, -0.4),
              end: Alignment(-0.4 + 2.4 * t, 0.4),
              colors: <Color>[
                AppColors.surface,
                AppColors.surfaceHi,
                AppColors.surface,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A horizontal row of poster-sized skeletons.
class PosterRowSkeleton extends StatelessWidget {
  const PosterRowSkeleton({super.key, this.height = 186});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, _) => const ShimmerBox(width: 130),
      ),
    );
  }
}
