import 'package:flutter/material.dart';

import 'app_prefs.dart';

/// Animax design tokens.
///
/// [accent]/[bg]/[surface] are **getters**, not consts: they read the live
/// preference state so the accent-color picker and AMOLED mode apply instantly
/// across every screen without rebuilding the theme object. All screens
/// reference these tokens directly, which is why the getters return defaults
/// until [AppPrefs.I.load] completes.
class AppColors {
  AppColors._();

  // Default (Neo Green) tokens.
  static const Color _bgD = Color(0xFF0B0F0D);
  static const Color _surfaceD = Color(0xFF141917);
  static const Color _surfaceHiD = Color(0xFF1D2420);

  static bool get _amoled => AppPrefs.I.amoled;

  // ---- Dynamic backgrounds (AMOLED-aware) ---------------------------------
  static Color get bg => _amoled ? const Color(0xFF000000) : _bgD;
  static Color get surface => _amoled ? const Color(0xFF0A0A0A) : _surfaceD;
  static Color get surfaceHi =>
      _amoled ? const Color(0xFF151515) : _surfaceHiD;

  static const Color stroke = Color(0xFF242C27);

  // ---- Dynamic accent ------------------------------------------------------
  static AccentTheme get _a => AppPrefs.I.accent;
  static Color get accent => _a.color;
  static Color get accentDeep => _a.deep;
  static Color get accentInk => _a.ink;

  /// Dark text-on-accent (kept name-compatible with the old token).
  static Color get ink => _a.ink;
  static LinearGradient get accentGrad => LinearGradient(
        colors: <Color>[_a.color, _a.deep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // ---- Fixed text / signal colors ------------------------------------------
  static const Color text = Color(0xFFFFFFFF);
  static const Color sub = Color(0xFFA9B1AB);
  static const Color muted = Color(0xFF6B736D);
  static const Color danger = Color(0xFFFF5A5A);
  static const Color amber = Color(0xFFFFB020);

  /// Hero fade — safe as const because it only uses fixed colors.
  static const LinearGradient heroFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.55, 1.0],
    colors: [Colors.transparent, Color(0x660B0F0D), Color(0xFF0B0F0D)],
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

  /// Builds the dark theme from the current accent preference. Called again
  /// whenever the accent (or AMOLED) changes — see [AnimaxApp].
  static ThemeData dark() {
    final Color a = AppColors.accent;
    final Color aInk = AppColors.accentInk;
    final ThemeData base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.dark(
        primary: a,
        secondary: a,
        surface: AppColors.surface,
        onPrimary: aInk,
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
            (states) => states.contains(WidgetState.selected) ? aInk : AppColors.muted),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? a : AppColors.surfaceHi),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
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
