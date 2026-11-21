import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/social.dart';
import '../widgets/mb_ui.dart' show kFont;
import '../widgets/social_bar.dart' show UserAvatar;
import 'clips_screen.dart' show ClipsViewer;
import 'user_profile_screen.dart';

/// "النشاطات": who liked, commented on, replied to or reposted your clips,
/// liked your comments or followed you.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  @override
  void initState() {
    super.initState();
    Inbox.I.refresh().then((_) => Inbox.I.markSeen());
  }

  static String ago(DateTime? at) {
    if (at == null) return '';
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'الآن';
    if (d.inMinutes < 60) return 'منذ ${d.inMinutes} د';
    if (d.inHours < 24) return 'منذ ${d.inHours} س';
    return 'منذ ${d.inDays} يوم';
  }

  static IconData iconOf(String type) => switch (type) {
    'clipLike' || 'commentLike' => Icons.favorite_rounded,
    'comment' => Icons.chat_bubble_rounded,
    'follow' => Icons.person_add_alt_1_rounded,
    'reply' => Icons.quickreply_rounded,
    'repost' => Icons.repeat_rounded,
    _ => Icons.notifications_rounded,
  };

  Future<void> _open(InboxItem it) async {
    if (it.clipId.isEmpty) {
      openUserProfile(context, it.from);
      return;
    }
    final VideoClip? c = await Social.clipById(it.clipId)
        .catchError((Object _) => null);
    if (!mounted) return;
    if (c == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا المقطع لم يعد متاحًا.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClipsViewer(clips: <VideoClip>[c]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('النشاطات'),
      ),
      body: ListenableBuilder(
        listenable: Inbox.I,
        builder: (BuildContext context, _) {
          final List<InboxItem> items = Inbox.I.items;
          if (items.isEmpty) {
            return RefreshIndicator(
              color: AppColors.brandGreen,
              onRefresh: Inbox.I.refresh,
              child: ListView(
                children: <Widget>[
                  const SizedBox(height: 140),
                  Center(
                    child: Inbox.I.loading
                        ? const CircularProgressIndicator(
                            color: AppColors.brandGreen,
                          )
                        : const Padding(
                            padding: EdgeInsets.all(30),
                            child: Text(
                              'لا توجد نشاطات بعد. عندما يعجب أحد بمقاطعك أو يعلّق أو يتابعك ستظهر هنا.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: kFont,
                                fontSize: 15,
                                height: 1.6,
                                color: AppColors.sub,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.brandGreen,
            onRefresh: Inbox.I.refresh,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.stroke),
              itemBuilder: (BuildContext c, int i) {
                final InboxItem it = items[i];
                return Dismissible(
                  key: ValueKey<String>(it.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => Inbox.I.remove(it),
                  background: Container(
                    color: const Color(0xFF5A1F1F),
                    alignment: AlignmentDirectional.centerEnd,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                    ),
                  ),
                  child: ListTile(
                    onTap: () => _open(it),
                    leading: GestureDetector(
                      onTap: () => openUserProfile(c, it.from),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          UserAvatar(name: it.name, size: 44),
                          PositionedDirectional(
                            bottom: -2,
                            end: -2,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                iconOf(it.type),
                                size: 13,
                                color: AppColors.brandGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    title: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '${it.name} ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: it.sentence),
                        ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kFont,
                        fontSize: 14.5,
                        height: 1.45,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      ago(it.at),
                      style: const TextStyle(
                        fontFamily: kFont,
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
