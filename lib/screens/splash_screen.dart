import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_prefs.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/library_store.dart';
import '../widgets/animax_logo.dart';
import '../widgets/buttons.dart';

/// Splash — synchronizes the app with the API backend before entering.
///
/// The logo shows a live sync status while [AppState.bootstrap] loads the
/// catalog, release calendar and notifications from the backend. The app
/// only continues once the sync finishes; if the backend cannot be reached,
/// the splash turns into an error card with a Retry action.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..forward();

  bool _failed = false;
  bool _retrying = false;
  bool _scheduleStep = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  Future<void> _sync() async {
    setState(() {
      _retrying = true;
      _failed = false;
      _scheduleStep = false;
    });
    // Preferences + personal library must be ready before any screen builds.
    await AppPrefs.I.load();
    await LibraryStore.I.load();
    // Listen so the status line tracks the repository's own messages.
    final AppState state = AppState.I;
    void listener() {
      if (!mounted) return;
      // The schedule phase starts once the catalog message flips to Connected.
      setState(() => _scheduleStep =
          state.isConnected && state.backendMode == BackendMode.connected);
    }

    state.addListener(listener);
    final bool ok = await state.bootstrap().timeout(
          const Duration(seconds: 40),
          onTimeout: () => false,
        );
    state.removeListener(listener);
    if (!mounted) return;
    if (ok) {
      await _enter();
    } else {
      setState(() {
        _failed = true;
        _retrying = false;
      });
    }
  }

  Future<void> _enter() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool onboarded = prefs.getBool('animax_onboarded') ?? false;
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, onboarded ? '/shell' : '/onboarding');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: CurvedAnimation(
                    parent: _controller, curve: Curves.easeOutBack),
                child: const AnimaxLogo(size: 84),
              ),
              const SizedBox(height: 18),
              const Text('Animax', style: AppText.h1),
              const SizedBox(height: 4),
              const Text('Anime. Anytime. Anywhere.', style: AppText.label),
              const SizedBox(height: 34),
              if (_failed)
                _SyncError(onRetry: _sync)
              else ...<Widget>[
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.6, color: AppColors.accent),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _retrying
                        ? (_scheduleStep
                            ? 'Preparing content…'
                            : state.backendMessage)
                        : 'Starting…',
                    textAlign: TextAlign.center,
                    style: AppText.label.copyWith(
                        fontSize: 11.5, color: AppColors.sub),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Preparing content',
                  style: AppText.label.copyWith(
                      fontSize: 10,
                      color: AppColors.muted,
                      letterSpacing: 0.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Backend unreachable — reason + retry / continue actions.
class _SyncError extends StatelessWidget {
  const _SyncError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: Colors.redAccent, size: 34),
            const SizedBox(height: 10),
            Text('Content unavailable',
                style: AppText.bodyBold.copyWith(fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              'The content library could not be reached. Check your internet connection.',
              textAlign: TextAlign.center,
              style: AppText.label.copyWith(fontSize: 11),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Retry sync',
              expanded: true,
              onTap: onRetry,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: GhostChip(
                label: 'Continue offline',
                padding: const EdgeInsets.symmetric(vertical: 13),
                onTap: () {
                  // Enter anyway — tabs show their own offline/retry states.
                  Navigator.pushReplacementNamed(context, '/shell');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
