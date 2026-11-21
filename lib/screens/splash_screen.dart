import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_prefs.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/cloud.dart';
import '../core/library_store.dart';
import '../core/social.dart';
import '../widgets/animax_logo.dart';
import '../widgets/mb_ui.dart';

/// Splash with live connection steps:
///  1. الاتصال بالخادم — reaches the Firebase backend,
///  2. استعادة الحساب — restores the signed-in session + profile,
///  3. تجهيز المحتوى — local library + background content sync.
/// Never blocks on a slow network: an unreachable server shows
/// "وضع عدم الاتصال" and the app still opens.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

enum _Step { pending, running, ok, offline }

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  final List<String> _labels = <String>[
    'الاتصال بالخادم',
    'استعادة الحساب',
    'تجهيز المحتوى',
  ];
  final List<_Step> _steps = <_Step>[_Step.pending, _Step.pending, _Step.pending];

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _set(int i, _Step s) {
    if (mounted) setState(() => _steps[i] = s);
  }

  Future<void> _start() async {
    final Stopwatch sw = Stopwatch()..start();
    // Local data first (fast, needed by everything).
    try {
      await AppPrefs.I.load().timeout(const Duration(seconds: 3));
    } catch (_) {}

    // 1. Backend connection.
    _set(0, _Step.running);
    final bool online = await CloudDb.I.ping();
    _set(0, online ? _Step.ok : _Step.offline);

    // 2. Account session.
    _set(1, _Step.running);
    try {
      await CloudAuth.I.restore().timeout(const Duration(seconds: 6));
      if (online && CloudAuth.I.signedIn) {
        unawaited(Social.ensureProfile());
        unawaited(BingoStore.I.load());
      }
    } catch (_) {}
    _set(1, _Step.ok);

    // 3. Content.
    _set(2, _Step.running);
    try {
      await LibraryStore.I.load().timeout(const Duration(seconds: 3));
    } catch (_) {}
    unawaited(AppState.I.bootstrap().catchError((Object _) => false));
    _set(2, _Step.ok);

    final int left = 1400 - sw.elapsedMilliseconds;
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
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Spacer(flex: 3),
            FadeTransition(
              opacity: fade,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1).animate(fade),
                child: const Column(
                  children: <Widget>[
                    AnimaxLogo(size: 88),
                    SizedBox(height: 18),
                    Text('أنيماكس',
                        style: TextStyle(
                            fontFamily: kFont,
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    SizedBox(height: 6),
                    Text('أفلام · مسلسلات · أنمي · مانغا · مقاطع',
                        style: TextStyle(
                            fontFamily: kFont,
                            fontSize: 15,
                            color: AppColors.sub)),
                  ],
                ),
              ),
            ),
            const Spacer(flex: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < _labels.length; i++)
                    _StepRow(label: _labels[i], step: _steps[i]),
                ],
              ),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.step});
  final String label;
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (step) {
      _Step.pending => const Icon(Icons.circle_outlined,
          size: 18, color: AppColors.muted),
      _Step.running => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.brandGreen)),
      _Step.ok => const Icon(Icons.check_circle_rounded,
          size: 18, color: AppColors.brandGreen),
      _Step.offline => const Icon(Icons.cloud_off_rounded,
          size: 18, color: AppColors.star),
    };
    final String suffix = step == _Step.offline ? ' — وضع عدم الاتصال' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          icon,
          const SizedBox(width: 10),
          Text('$label$suffix',
              style: TextStyle(
                  fontFamily: kFont,
                  fontSize: 14,
                  color: step == _Step.pending ? AppColors.muted : Colors.white)),
        ],
      ),
    );
  }
}
