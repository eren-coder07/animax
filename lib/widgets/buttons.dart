import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Solid green pill button — kit's "Play" / "Continue" / "Login" button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.playIcon = false,
    this.expanded = false,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onTap;
  final bool playIcon;
  final bool expanded;
  final double height;

  @override
  Widget build(BuildContext context) {
    final Widget button = Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(height / 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(height / 2),
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (playIcon) ...[
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: AppColors.accentInk, shape: BoxShape.circle),
                  child: Icon(Icons.play_arrow_rounded, color: AppColors.accent, size: 20),
                ),
                const SizedBox(width: 10),
              ],
              Text(label, style: AppText.button),
            ],
          ),
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Outlined pill — kit's "+ My List" / "Skip" chip. Turns green-check when active.
class GhostChip extends StatelessWidget {
  const GhostChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.accent : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(color: active ? AppColors.accent : AppColors.stroke, width: 1.4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active) ...[
                Icon(Icons.check_rounded, size: 16, color: AppColors.accentInk),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.ink : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable round chip used on Onboarding / Sort & Filter screens.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent : AppColors.surface,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.ink : AppColors.sub,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small green score badge with star — "★ 9.8".
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, this.small = false});

  final double score;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 2.5 : 4),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(small ? 6 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: AppColors.ink, size: small ? 10 : 13),
          const SizedBox(width: 2),
          Text(
            score.toStringAsFixed(1),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: small ? 9.5 : 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
