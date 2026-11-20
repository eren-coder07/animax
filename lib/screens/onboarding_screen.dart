import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../widgets/buttons.dart';

Future<void> _markOnboarded() async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('animax_onboarded', true);
  } catch (_) {
    // Best-effort — the user just sees onboarding once more.
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: IconButton(
                onPressed: () async {
                  await _markOnboarded();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/shell');
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
                children: [
                  const Text('أخبرنا بما تحب', style: AppText.h1),
                  const SizedBox(height: 8),
                  Text(
                    'اختر التصنيفات التي تحبها — سنبني صفحتك الرئيسية حولها. يمكنك تغييرها في أي وقت من الإعدادات.',
                    style: AppText.body,
                  ),
                  const SizedBox(height: 24),
                  ListenableBuilder(
                    listenable: state,
                    builder: (context, _) => Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: AnimaxData.genres
                          .map((String g) => SelectChip(
                                label: g,
                                selected: state.pickedGenres.contains(g),
                                onTap: () => state.toggleGenre(g),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
              child: Row(
                children: [
                  Expanded(
                    child: GhostChip(
                      label: 'تخطّي',
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      onTap: () async {
                        await _markOnboarded();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/shell');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: 'متابعة',
                      expanded: true,
                      onTap: () async {
                        await _markOnboarded();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/shell');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
