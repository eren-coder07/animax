import 'package:flutter/material.dart';

import '../core/app_prefs.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../core/episode_alerts.dart';
import '../core/social.dart';
import '../widgets/animax_logo.dart';
import '../widgets/mb_ui.dart';
import 'akwam_tab.dart';
import 'cartoon_tab.dart';
import 'clips_screen.dart';
import 'comic_tab.dart';
import 'downloads_screen.dart';
import 'global_search_screen.dart';
import 'hentai_tab.dart';
import 'home_tab.dart';
import 'profile_tab.dart';

/// Root shell: 3-tab bottom bar — الرئيسية · التحميلات · حسابي.
/// Home holds a search pill and category tabs (Akwam feed first).
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
    const String version = '2.7.0';
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
        return Scaffold(
          backgroundColor: AppColors.bg,
          extendBody: true,
          body: IndexedStack(
            index: state.navIndex.clamp(0, 3),
            children: const <Widget>[
              HomeScreen(),
              ClipsFeedScreen(),
              DownloadsScreen(asTab: true),
              ProfileTab(),
            ],
          ),
          bottomNavigationBar: _BottomBar(state: state),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Bottom bar
// -----------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    const List<(IconData, IconData, String)> items = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
      (Icons.video_library_outlined, Icons.video_library_rounded, 'مقاطع'),
      (Icons.download_outlined, Icons.download_rounded, 'التحميلات'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'حسابي'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2191A1F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[DownloadManager.I, Inbox.I, EpisodeAlerts.I]),
            builder: (BuildContext context, _) => Row(
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavItem(
                      icon: items[i].$1,
                      activeIcon: items[i].$2,
                      label: items[i].$3,
                      active: state.navIndex == i,
                      dot: (i == 2 && DownloadManager.I.activeCount > 0) ||
                          (i == 3 &&
                              (state.notices.isNotEmpty ||
                                  Inbox.I.unread > 0 ||
                                  EpisodeAlerts.I.alerts.isNotEmpty)),
                      onTap: () => state.setTab(i),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.dot = false,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget ic = Icon(active ? activeIcon : icon,
        size: 25, color: active ? Colors.white : AppColors.sub);
    if (active) {
      ic = ShaderMask(
        shaderCallback: (Rect r) => AppColors.brandGrad.createShader(r),
        blendMode: BlendMode.srcIn,
        child: ic,
      );
    }
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              ic,
              if (dot)
                const PositionedDirectional(
                  top: -1,
                  end: -3,
                  child: SizedBox(
                    width: 8,
                    height: 8,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: AppColors.badge, shape: BoxShape.circle)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(label,
              maxLines: 1,
              style: TextStyle(
                  fontFamily: kFont,
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? Colors.white : AppColors.sub)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Home: search pill + category tabs
// -----------------------------------------------------------------------------

/// One Home category tab.
typedef _Category = ({String label, bool adult, Widget Function() build});

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final List<_Category> _cats = <_Category>[
    (label: 'الرائج', adult: false, build: () => const AkwamTab()),
    (label: 'أفلام', adult: false, build: () => const AkwamGrid(feed: AkwamFeed.movies)),
    (label: 'مسلسلات', adult: false, build: () => const AkwamGrid(feed: AkwamFeed.series)),
    (label: 'برامج', adult: false, build: () => const AkwamGrid(feed: AkwamFeed.shows)),
    (label: 'أنمي', adult: false, build: () => const HomeTab()),
    (label: 'كرتون', adult: false, build: () => const CartoonTab()),
    (label: 'مانغا', adult: false, build: () => const ComicTab()),
    (label: '+18', adult: false, build: () => const HentaiTab()),
  ];

  /// Built lazily on first visit, then kept alive.
  final Map<int, Widget> _built = <int, Widget>{};

  static const List<String> _hints = <String>[
    'الهيبة', 'ولاد رزق 3', 'One Piece', 'باب الحارة', 'Breaking Bad',
  ];
  int _hint = 0;

  @override
  void initState() {
    super.initState();
    _hint = DateTime.now().second % _hints.length;
  }

  @override
  Widget build(BuildContext context) {
    // HomeScreen is a const child of the shell, so it must listen to the
    // app state itself — otherwise category taps never rebuild it.
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (BuildContext context, _) => _buildHome(context),
    );
  }

  Widget _buildHome(BuildContext context) {
    final AppState state = AppState.I;
    final int cat = state.homeCategory.clamp(0, _cats.length - 1);
    _built.putIfAbsent(cat, () => _cats[cat].build());
    return ColoredBox(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // ---- Logo + search pill ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: <Widget>[
                  const AnimaxLogo(size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const GlobalSearchScreen())),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHi,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.search_rounded,
                                color: Colors.white, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_hints[_hint],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: kFont,
                                      fontSize: 15,
                                      color: Color(0xFFD5D6DA))),
                            ),
                            const Text('بحث',
                                style: TextStyle(
                                    fontFamily: kFont,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.brandGreen)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ---- Category tabs ----
            SizedBox(
              height: 42,
              child: ListView.builder(
                key: const Key('categoryBar'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: _cats.length,
                itemBuilder: (BuildContext c, int i) {
                  final bool on = i == cat;
                  return GestureDetector(
                    onTap: () => state.setCategory(i),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: Row(
                        children: <Widget>[
                          Text(_cats[i].label,
                              style: TextStyle(
                                  fontFamily: kFont,
                                  fontSize: on ? 17 : 15.5,
                                  fontWeight:
                                      on ? FontWeight.w700 : FontWeight.w500,
                                  color: on ? Colors.white : AppColors.sub)),
                          if (_cats[i].adult) ...<Widget>[
                            const SizedBox(width: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 0),
                              decoration: BoxDecoration(
                                color: AppColors.badge,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('18',
                                  style: TextStyle(
                                      fontFamily: kFont,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // ---- Section body ----
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: EmbeddedSection(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 70),
                    child: IndexedStack(
                      index: cat,
                      children: <Widget>[
                        for (int i = 0; i < _cats.length; i++)
                          _built[i] ?? const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "What's new" dialog — shown once per version after entering.
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key, required this.version});

  final String version;

  static const List<String> highlights = <String>[
    '🏆 «الأكثر مشاهدة على أنيماكس» في الرئيسية',
    '⬇️ تحميل الحلقة التالية تلقائيًا على Wi-Fi لمشاهدتها بدون إنترنت',
    '🛡️ حظر المستخدمين والإبلاغ عن المقاطع والتعليقات',
    '👥 اكتشف صنّاع المقاطع وتابعهم',
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
          Text('الجديد في الإصدار $version',
              style: const TextStyle(
                  fontFamily: 'Plex',
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
                            fontFamily: 'Plex',
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
          child: Text('هيا بنا',
              style: TextStyle(
                  fontFamily: 'Plex',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent)),
        ),
      ],
    );
  }
}
