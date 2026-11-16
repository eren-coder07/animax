import 'package:flutter/material.dart';

/// Animax design tokens sampled from the UI kit reference.
class AppColors {
  AppColors._();

  static const Color bg = Color(0xFF0B0F0D);
  static const Color surface = Color(0xFF141917);
  static const Color surfaceHi = Color(0xFF1D2420);
  static const Color stroke = Color(0xFF242C27);

  static const Color green = Color(0xFF04C14A);
  static const Color greenDeep = Color(0xFF026E2C);
  static const Color ink = Color(0xFF06130A); // dark text on green

  static const Color text = Color(0xFFFFFFFF);
  static const Color sub = Color(0xFFA9B1AB);
  static const Color muted = Color(0xFF6B736D);
  static const Color danger = Color(0xFFFF5A5A);
  static const Color amber = Color(0xFFFFB020);

  static const LinearGradient greenGrad = LinearGradient(
    colors: [Color(0xFF05CE51), Color(0xFF02752E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.55, 1.0],
    colors: [Colors.transparent, Color(0x660B0F0D), AppColors.bg],
  );
}

/// Typography shortcuts (Poppins).
class AppText {
  AppText._();

  static const TextStyle h1 = TextStyle(
      fontFamily: 'Poppins', fontSize: 26, fontWeight: FontWeight.w800, height: 1.25);
  static const TextStyle h2 = TextStyle(
      fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, height: 1.3);
  static const TextStyle h3 = TextStyle(
      fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, height: 1.35);
  static const TextStyle body = TextStyle(
      fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w400, height: 1.6, color: AppColors.sub);
  static const TextStyle bodyBold = TextStyle(
      fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, height: 1.55);
  static const TextStyle label = TextStyle(
      fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.muted);
  static const TextStyle button = TextStyle(
      fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text);
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final ThemeData base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.green,
        secondary: AppColors.green,
        surface: AppColors.surface,
        onPrimary: AppColors.ink,
        onSurface: AppColors.text,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: 'Poppins',
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.text),
        titleTextStyle: TextStyle(
            fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.stroke, thickness: 1, space: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.green : AppColors.surfaceHi),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHi,
        contentTextStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
