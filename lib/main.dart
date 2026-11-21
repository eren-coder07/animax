import 'core/data_budget.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'core/app_prefs.dart';
import 'core/app_theme.dart';
import 'core/download_manager.dart';
import 'core/net_quality.dart';
import 'core/manga_api.dart';
import 'screens/akwam_details_screen.dart';
import 'screens/akwam_player_screen.dart';
import 'screens/akwam_search_screen.dart';
import 'screens/calendar_tab.dart';
import 'screens/catalog_screen.dart';
import 'screens/comic_catalog_screen.dart';
import 'screens/comic_details_screen.dart';
import 'screens/comic_reader_screen.dart';
import 'screens/comic_tab.dart';
import 'screens/details_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/global_search_screen.dart';
import 'screens/help_center_screen.dart';
import 'screens/home_shell.dart';
import 'screens/hh_catalog_screen.dart';
import 'screens/hh_details_screen.dart';
import 'screens/hh_player_screen.dart';
import 'screens/hh_search_screen.dart';
import 'screens/library_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Bigger in-memory image cache: fewer re-downloads on slow connections.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 160 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 600;
  NetQuality.check();
  AppPrefs.I.ready.then((_) => DataBudget.I.start());
  // video_player has no Windows backend: route it through media_kit (mpv)
  // there. Android keeps ExoPlayer untouched.
  if (Platform.isWindows) {
    VideoPlayerMediaKit.ensureInitialized(windows: true);
  }
  // Restores the download queue and resumes anything left unfinished.
  DownloadManager.I.load();
  runApp(const AnimaxApp());
}

class AnimaxApp extends StatelessWidget {
  const AnimaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to preferences so accent color / AMOLED switches apply live.
    return ListenableBuilder(
      listenable: AppPrefs.I,
      builder: (BuildContext context, _) => MaterialApp(
        title: 'أنيماكس',
        debugShowCheckedModeBanner: false,
        // Arabic-first app: Arabic strings, right-to-left layout everywhere.
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.dark(),
        initialRoute: '/',
        routes: <String, WidgetBuilder>{
          '/': (_) => const SplashScreen(),
          '/onboarding': (_) => const OnboardingScreen(),
          '/shell': (_) => const HomeShell(),
          '/details': (_) => const DetailsScreen(),
          // Video players + comic reader keep a left-to-right layout (seek
          // bars, page order) inside the Arabic RTL app.
          '/player': (_) => const _Ltr(PlayerScreen()),
          '/search': (_) => const SearchScreen(),
          '/catalog': (_) => const CatalogScreen(),
          '/notifications': (_) => const NotificationsScreen(),
          '/help': (_) => const HelpCenterScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/library': (_) => const LibraryScreen(),
          '/downloads': (_) => const DownloadsScreen(),
          '/search-all': (_) => const GlobalSearchScreen(),
          '/calendar': (_) => const CalendarTab(),
          '/comics': (_) => const ComicTab(),
          '/comic-catalog': (_) => const ComicCatalogScreen(
              tag: null, title: 'Popular'),
          '/hh-catalog': (_) => const HhCatalogScreen(),
          '/hh-details': (_) => const HhDetailsScreen(),
          '/hh-player': (_) => const _Ltr(HhPlayerScreen()),
          '/hh-search': (_) => const HhSearchScreen(),
          '/akwam-search': (_) => const AkwamSearchScreen(),
          '/akwam-details': (_) => const AkwamDetailsScreen(),
          '/akwam-player': (_) => const _Ltr(AkwamPlayerScreen()),
        },
        // Comic screens take constructor arguments → onGenerateRoute.
        onGenerateRoute: (RouteSettings settings) {
          final Object? args = settings.arguments;
          if (settings.name == '/comic-details' && args is MangaItem) {
            return _page(ComicDetailsScreen(manga: args));
          }
          if (settings.name == '/comic-reader' && args is ReaderArgs) {
            return _page(_Ltr(ComicReaderScreen(
                manga: args.manga,
                chapters: args.chapters,
                startIndex: args.startIndex)));
          }
          return null;
        },
      ),
    );
  }

  PageRouteBuilder<dynamic> _page(Widget page) => PageRouteBuilder<dynamic>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (BuildContext c, Animation<double> a, Animation<double> b) =>
            page,
        transitionsBuilder: (BuildContext c, Animation<double> a,
                Animation<double> b, Widget child) =>
            FadeTransition(opacity: a, child: child),
      );
}

/// Route argument bundle for opening the reader by name.
class ReaderArgs {
  const ReaderArgs({
    required this.manga,
    required this.chapters,
    required this.startIndex,
  });
  final MangaItem manga;
  final List<MangaChapter> chapters;
  final int startIndex;
}

/// Forces a left-to-right layout for one screen inside the RTL app.
class _Ltr extends StatelessWidget {
  const _Ltr(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.ltr, child: child);
}
