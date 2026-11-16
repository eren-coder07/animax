import 'package:flutter/material.dart';

import '../core/app_prefs.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/library_store.dart';
import 'calendar_tab.dart';
import 'cartoon_tab.dart';
import 'cinema_tab.dart';
import 'comic_tab.dart';
import 'hentai_tab.dart';
import 'home_tab.dart';
import 'profile_tab.dart';

/// Root navigation shell — 7 sections: Home, Calendar, Cinema, Cartoons,
/// Comics, 18+ and Profile. Also hosts the once-per-version What's-new
/// dialog shown shortly after entering.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();

  static const List<({IconData icon, String label})> _tabs = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.calendar_month_rounded, label: 'Calendar'),
    (icon: Icons.theaters_rounded, label: 'Cinema'),
    (icon: Icons.animation_rounded, label: 'Cartoons'),
    (icon: Icons.menu_book_rounded, label: 'Comics'),
    (icon: Icons.eighteen_up_rating_rounded, label: '18+'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        _maybeShowWhatsNew();
      });
    });
  }

  Future<void> _maybeShowWhatsNew() async {
    const String version = '1.9.0';
    if (AppPrefs.I.lastSeenVersion == version) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dctx) => const WhatsNewDialog(version: version),
    );
    AppPrefs.I.set('lastSeenVersion', version);
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[state, AppPrefs.I]),
      builder: (BuildContext context, _) {
        final Color accent = AppColors.accent;
        return Scaffold(
          body: IndexedStack(
            index: state.navIndex,
            children: const [
              HomeTab(),
              CalendarTab(),
              CinemaTab(),
              CartoonTab(),
              ComicTab(),
              HentaiTab(),
              ProfileTab(),
            ],
          ),
          bottomNavigationBar: _BottomNav(state: state, accent: accent),
        );
      },
    );
  }
}

/// The 7-tab bottom navigation with the new-episode badge dot.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.state, required this.accent});

  final AppState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final List<({IconData icon, String label})> tabs = HomeShell._tabs;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: List<Widget>.generate(tabs.length, (int i) {
              final bool active = state.navIndex == i;
              final bool isCinemaTab = i == 2;
              final Color activeColor =
                  isCinemaTab ? const Color(0xFFE50914) : accent;
              return Expanded(
                child: InkWell(
                  onTap: () => state.setTab(i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _tabIcon(tabs[i].icon, i, active, activeColor),
                      const SizedBox(height: 4),
                      Text(
                        tabs[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9.5,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? activeColor : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _tabIcon(IconData icon, int i, bool active, Color activeColor) {
    final Widget ic =
        Icon(icon, size: 22, color: active ? activeColor : AppColors.muted);
    if (i == 1 && AppPrefs.I.navBadges && LibraryStore.I.history.isNotEmpty) {
      return Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          ic,
          Positioned(
            top: -1,
            right: -3,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: AppColors.danger, shape: BoxShape.circle),
            ),
          ),
        ],
      );
    }
    return ic;
  }
}

/// "What's new in v1.9.0" — shown once per version after entering.
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key, required this.version});

  final String version;

  static const List<String> highlights = <String>[
    'Comics section — thousands of manga from MangaDex with a real reader',
    'Cartoons section — animated movies & series with multi-server playback',
    'Cinema fix — 7 servers with automatic fallback (no more "verification failed")',
    'Player gestures — double-tap seek, swipe brightness/volume, 2× boost',
    'My Library — watchlist, history, ratings and stats',
    'Accent colors, AMOLED mode and a fresh home with hero carousel',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: <Widget>[
          Icon(Icons.auto_awesome_rounded,
              color: AppColors.accent, size: 22),
          const SizedBox(width: 10),
          Text('What\'s new in v$version',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String h in highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.circle, size: 5, color: AppColors.accent),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(h,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            height: 1.45,
                            color: AppColors.sub)),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Let\'s go',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent)),
        ),
      ],
    );
  }
}
