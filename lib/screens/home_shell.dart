import 'package:flutter/material.dart';

import '../core/app_prefs.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/library_store.dart';
import 'akwam_tab.dart';
import 'calendar_tab.dart';
import 'cartoon_tab.dart';
import 'cinema_tab.dart';
import 'comic_tab.dart';
import 'hentai_tab.dart';
import 'home_tab.dart';
import 'profile_tab.dart';

/// Root navigation shell — 8 sections. The bottom bar shows Home, Cinema,
/// Akwam, More and Profile; Calendar, Cartoons, Comics and 18+ open from the
/// "More" sheet. Also hosts the once-per-version
/// What's-new dialog shown shortly after entering.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
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
    const String version = '1.9.1';
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
              AkwamTab(),
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

/// One navigable section. [index] is its slot in the shell's IndexedStack
/// (kept stable so `AppState.setTab(i)` callers keep working).
typedef _Section = ({
  int index,
  IconData icon,
  String label,
  String blurb,
  Color? tint,
});

/// Sections pinned to the bottom bar (order = left → right, with the
/// "More" button inserted before Profile).
const List<_Section> _primary = <_Section>[
  (index: 0, icon: Icons.home_rounded, label: 'Home', blurb: '', tint: null),
  (
    index: 2,
    icon: Icons.theaters_rounded,
    label: 'Cinema',
    blurb: '',
    tint: Color(0xFFE50914)
  ),
  (
    index: 3,
    icon: Icons.movie_filter_rounded,
    label: 'Akwam',
    blurb: '',
    tint: Color(0xFF18A2B8)
  ),
];

const _Section _profile = (
  index: 7,
  icon: Icons.person_rounded,
  label: 'Profile',
  blurb: '',
  tint: null
);

/// Sections reachable from the "More" sheet.
const List<_Section> _more = <_Section>[
  (
    index: 1,
    icon: Icons.calendar_month_rounded,
    label: 'Calendar',
    blurb: 'Airing schedule',
    tint: Color(0xFF7C8CFF)
  ),
  (
    index: 4,
    icon: Icons.animation_rounded,
    label: 'Cartoons',
    blurb: 'Animated shows',
    tint: Color(0xFFFFB020)
  ),
  (
    index: 5,
    icon: Icons.menu_book_rounded,
    label: 'Comics',
    blurb: 'Manga reader',
    tint: Color(0xFF3DD6A0)
  ),
  (
    index: 6,
    icon: Icons.eighteen_up_rating_rounded,
    label: '18+',
    blurb: 'Adults only',
    tint: Color(0xFFFF5A8A)
  ),
];

/// Compact 5-slot bottom bar: Home · Cinema · Akwam · More · Profile.
/// When a "More" section is open, the More slot takes on its icon + name.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.state, required this.accent});

  final AppState state;
  final Color accent;

  /// History-based "new episode" hint for the Calendar section.
  static bool get _calendarBadge =>
      AppPrefs.I.navBadges && LibraryStore.I.history.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final int current = state.navIndex;
    _Section? activeMore;
    for (final _Section s in _more) {
      if (s.index == current) activeMore = s;
    }
    final List<Widget> items = <Widget>[
      for (final _Section s in _primary)
        _NavItem(
          icon: s.icon,
          label: s.label,
          active: current == s.index,
          color: s.tint ?? accent,
          onTap: () => state.setTab(s.index),
        ),
      _NavItem(
        icon: activeMore?.icon ?? Icons.grid_view_rounded,
        label: activeMore?.label ?? 'More',
        active: activeMore != null,
        color: activeMore?.tint ?? accent,
        badge: activeMore == null && _calendarBadge,
        onTap: () => _MoreSheet.show(context, state, accent),
      ),
      _NavItem(
        icon: _profile.icon,
        label: _profile.label,
        active: current == _profile.index,
        color: accent,
        onTap: () => state.setTab(_profile.index),
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: <Widget>[
              for (final Widget w in items) Expanded(child: w),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bottom-bar slot: pill highlight behind the icon when active.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 56,
              height: 30,
              decoration: BoxDecoration(
                color: active
                    ? color.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              alignment: Alignment.center,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Icon(icon,
                      size: 23, color: active ? color : AppColors.muted),
                  if (badge)
                    Positioned(
                      top: -1,
                      right: -3,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.bg, width: 1.2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? color : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing the sections that don't fit on the bar.
class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.state, required this.accent});

  final AppState state;
  final Color accent;

  static Future<void> show(
      BuildContext context, AppState state, Color accent) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _MoreSheet(state: state, accent: accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text('More sections',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text)),
            ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.1,
              children: <Widget>[
                for (final _Section s in _more) _tile(context, s),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, _Section s) {
    final Color c = s.tint ?? accent;
    final bool active = state.navIndex == s.index;
    final bool badge = s.index == 1 && _BottomNav._calendarBadge;
    return Material(
      color: active ? c.withValues(alpha: 0.14) : AppColors.surfaceHi,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).pop();
          state.setTab(s.index);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: active ? c.withValues(alpha: 0.6) : AppColors.stroke),
          ),
          child: Row(
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(s.icon, color: c, size: 22),
                  ),
                  if (badge)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.surfaceHi, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text)),
                    Text(s.blurb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10.5,
                            color: AppColors.sub)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "What's new in v1.9.1" — shown once per version after entering.
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key, required this.version});

  final String version;

  static const List<String> highlights = <String>[
    'Akwam section — Arabic movies, series & shows from akwam.ss with native MP4 playback',
    'Cleaner app — all connection diagnostics and debug screens removed from the UI',
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
