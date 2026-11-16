import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Circular translucent icon button used over heroes / headers.
class IconBubble extends StatelessWidget {
  const IconBubble(
    this.icon, {
    super.key,
    this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: AppColors.surface.withValues(alpha: 0.75),
          shape: const CircleBorder(
              side: BorderSide(color: AppColors.stroke, width: 1)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap ?? () {},
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 20, color: AppColors.text),
            ),
          ),
        ),
        if (badge)
          Positioned(
            top: 9,
            right: 10,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

/// Rounded filled text field (login / card / edit profile).
class FieldBox extends StatelessWidget {
  const FieldBox({
    super.key,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.controller,
    this.suffix,
    this.onChanged,
  });

  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextEditingController? controller;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.muted),
        prefixIcon: Icon(icon, size: 20, color: AppColors.muted),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),
    );
  }
}

/// Profile-style menu row: leading icon, label, trailing widget/chevron.
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 21, color: AppColors.accent),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: AppText.bodyBold.copyWith(fontSize: 14))),
            if (trailing != null)
              trailing!
            else if (showChevron)
              const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Empty-state placeholder (e.g. empty My List).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          Text(title, style: AppText.h3),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(message, textAlign: TextAlign.center, style: AppText.label),
          ),
        ],
      ),
    );
  }
}
