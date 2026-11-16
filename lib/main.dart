import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'screens/backend_settings_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/details_screen.dart';
import 'screens/egy_gate_screen.dart';
import 'screens/egy_search_screen.dart';
import 'screens/help_center_screen.dart';
import 'screens/home_shell.dart';
import 'screens/hh_catalog_screen.dart';
import 'screens/hh_details_screen.dart';
import 'screens/hh_player_screen.dart';
import 'screens/hh_search_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const AnimaxApp());
}

class AnimaxApp extends StatelessWidget {
  const AnimaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Animax',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/onboarding': (_) => const OnboardingScreen(),
        '/shell': (_) => const HomeShell(),
        '/details': (_) => const DetailsScreen(),
        '/player': (_) => const PlayerScreen(),
        '/search': (_) => const SearchScreen(),
        '/catalog': (_) => const CatalogScreen(),
        '/notifications': (_) => const NotificationsScreen(),
        '/help': (_) => const HelpCenterScreen(),
        '/backend': (_) => const BackendSettingsScreen(),
        '/hh-catalog': (_) => const HhCatalogScreen(),
        '/hh-details': (_) => const HhDetailsScreen(),
        '/hh-player': (_) => const HhPlayerScreen(),
        '/hh-search': (_) => const HhSearchScreen(),
        '/egy-gate': (_) => const EgyGateScreen(),
        '/egy-search': (_) => const EgySearchScreen(),
      },
    );
  }
}
