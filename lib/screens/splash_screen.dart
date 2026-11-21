import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_prefs.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/library_store.dart';
import '../widgets/animax_logo.dart';
import '../widgets/mb_ui.dart';

/// Splash — loads local data (preferences, library) and enters the app
/// after a short brand animation. Network sync (anime catalog, schedule)
/// runs in the background so a slow or unreachable source never blocks
/// the app; each section shows its own loading / retry state instead.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      await AppPrefs.I.load().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await LibraryStore.I.load().timeout(const Duration(seconds: 3));
    } catch (_) {}
    // Background sync — never awaited here.
    unawaited(AppState.I.bootstrap().catchError((Object _) => false));
    final int left = 1100 - sw.elapsedMilliseconds;
    if (left > 0) await Future<void>.delayed(Duration(milliseconds: left));
    if (!mounted) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool onboarded = prefs.getBool('animax_onboarded') ?? false;
    if (!mounted) return;
    Navigator.pushReplacementNamed(
        context, onboarded ? '/shell' : '/onboarding');
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> fade =
        CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(fade),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const AnimaxLogo(size: 84),
                const SizedBox(height: 18),
                const Text('أنيماكس',
                    style: TextStyle(
                        fontFamily: kFont,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 6),
                const Text('أفلام · مسلسلات · أنمي · مانغا',
                    style: TextStyle(
                        fontFamily: kFont, fontSize: 15, color: AppColors.sub)),
                const SizedBox(height: 28),
                SizedBox(
                  width: 120,
                  height: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: AnimatedBuilder(
                      animation: _anim,
                      builder: (_, _) => Stack(
                        children: <Widget>[
                          Container(color: AppColors.surfaceHi),
                          FractionallySizedBox(
                            widthFactor: _anim.value,
                            child: Container(
                                decoration: const BoxDecoration(
                                    gradient: AppColors.brandGrad)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
