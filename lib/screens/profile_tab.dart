import 'package:flutter/material.dart';

import '../core/akwam_api.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../core/app_prefs.dart';
import '../core/cloud.dart';
import '../core/library_store.dart';
import '../core/social.dart';
import '../widgets/animax_logo.dart';
import '../widgets/mb_ui.dart';
import '../widgets/social_bar.dart';
import 'activity_screen.dart';
import 'auth_screen.dart';
import 'bingo_screen.dart';
import 'league_screen.dart';
import 'user_profile_screen.dart';

/// "حسابي" — grouped cards: list, watch history (with thumbnails),
/// notifications, downloads, settings and help.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return ColoredBox(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            state,
            LibraryStore.I,
            DownloadManager.I,
            CloudAuth.I,
            BingoStore.I,
            AppPrefs.I,
            Inbox.I,
          ]),
          builder: (BuildContext context, _) {
            final LibraryStore lib = LibraryStore.I;
            final List<HistoryRow> hist = lib.history.take(6).toList();
            final int dl = DownloadManager.I.items.length;
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 100),
              children: <Widget>[
                _ProfileHeader(state: state),
                GroupCard(children: <Widget>[
                  if (CloudAuth.I.signedIn)
                    GroupRow(
                      key: const Key('activityRow'),
                      icon: Icons.favorite_border_rounded,
                      label: 'النشاطات',
                      badge: Inbox.I.unread,
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const ActivityScreen())),
                    ),
                  if (CloudAuth.I.signedIn)
                    GroupRow(
                      icon: Icons.account_circle_outlined,
                      label: 'ملفي الشخصي ومقاطعي',
                      onTap: () =>
                          openUserProfile(context, CloudAuth.I.user!.uid),
                    ),
                  GroupRow(
                    icon: Icons.grid_on_rounded,
                    label: 'بينغو المشاهدة',
                    value: '${BingoStore.I.done.length}/9',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const BingoScreen())),
                  ),
                  GroupRow(
                    icon: Icons.emoji_events_outlined,
                    label: 'دوري البينغو الأسبوعي',
                    value: '${BingoStore.I.score} نقطة',
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const LeagueScreen())),
                  ),
                  GroupRow(
                    icon: Icons.bolt_rounded,
                    label: 'وضع الماراثون',
                    value: AppPrefs.I.bingeMode ? 'مفعّل' : 'متوقف',
                    onTap: () => AppPrefs.I.set('bingeMode', !AppPrefs.I.bingeMode),
                  ),
                ]),
                GroupCard(children: <Widget>[
                  GroupRow(
                    icon: Icons.bookmark_border_rounded,
                    label: 'قائمتي',
                    value: '${lib.allEntries.length}',
                    onTap: () => Navigator.pushNamed(context, '/library'),
                  ),
                  GroupRow(
                    icon: Icons.history_rounded,
                    label: 'سجل المشاهدة',
                    onTap: () => Navigator.pushNamed(context, '/library'),
                    below: hist.isEmpty
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: SizedBox(
                              height: 92,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: hist.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (BuildContext c, int i) =>
                                    _HistoryThumb(row: hist[i]),
                              ),
                            ),
                          ),
                  ),
                  GroupRow(
                    icon: Icons.notifications_none_rounded,
                    label: 'الإشعارات',
                    badge: state.notices.length,
                    onTap: () =>
                        Navigator.pushNamed(context, '/notifications'),
                  ),
                ]),
                GroupCard(children: <Widget>[
                  GroupRow(
                    icon: Icons.download_outlined,
                    label: 'التحميلات',
                    value: '$dl',
                    onTap: () => state.setTab(2),
                  ),
                  GroupRow(
                    icon: Icons.insights_rounded,
                    label: 'الإحصاءات',
                    onTap: () => Navigator.pushNamed(context, '/library'),
                  ),
                ]),
                GroupCard(children: <Widget>[
                  GroupRow(
                    icon: Icons.settings_outlined,
                    label: 'الإعدادات',
                    onTap: () => Navigator.pushNamed(context, '/settings'),
                  ),
                  GroupRow(
                    icon: Icons.help_outline_rounded,
                    label: 'مركز المساعدة',
                    onTap: () => Navigator.pushNamed(context, '/help'),
                  ),
                  if (CloudAuth.I.signedIn)
                    GroupRow(
                      icon: Icons.logout_rounded,
                      label: 'تسجيل الخروج',
                      onTap: () => CloudAuth.I.signOut(),
                    ),
                  const GroupRow(
                    icon: Icons.info_outline_rounded,
                    label: 'الإصدار',
                    value: '2.5.0',
                  ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final CloudUser? u = CloudAuth.I.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Row(
        children: <Widget>[
          if (u != null)
            GestureDetector(
              onTap: () => openUserProfile(context, u.uid),
              child: UserAvatar(name: u.name, size: 64),
            )
          else
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                  gradient: AppColors.brandGrad, shape: BoxShape.circle),
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface, shape: BoxShape.circle),
                child: const Center(child: AnimaxLogo(size: 32)),
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: u == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('مرحبًا بك في أنيماكس',
                          style: TextStyle(
                              fontFamily: kFont,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 8),
                      GradientButton(
                        label: 'تسجيل الدخول / حساب جديد',
                        height: 38,
                        onTap: () => requireLogin(context),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(u.name.isEmpty ? 'مستخدم أنيماكس' : u.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: kFont,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(u.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                              fontFamily: kFont,
                              fontSize: 13,
                              color: AppColors.sub)),
                    ],
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white, size: 26),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }
}

class _HistoryThumb extends StatelessWidget {
  const _HistoryThumb({required this.row});
  final HistoryRow row;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (row.kind == 'akwam' && row.key.startsWith('akwam:')) {
          final AkwamItem? it = AkwamApi.itemFromPath(row.key.substring(6),
              title: row.title, poster: row.poster);
          if (it != null) {
            Navigator.pushNamed(context, '/akwam-details', arguments: it);
            return;
          }
        }
        Navigator.pushNamed(context, '/library');
      },
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                  width: 120, height: 66, child: NetImage(row.poster)),
            ),
            const SizedBox(height: 6),
            Text(row.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: kFont, fontSize: 13.5, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
