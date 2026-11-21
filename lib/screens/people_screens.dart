import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/cloud.dart';
import '../core/social.dart';
import '../widgets/mb_ui.dart' show kFont, compactCount;
import '../widgets/social_bar.dart' show UserAvatar;
import 'auth_screen.dart';
import 'user_profile_screen.dart';

/// «اكتشف صنّاع المقاطع»: creators with the most followers, one-tap follow.
class CreatorsScreen extends StatefulWidget {
  const CreatorsScreen({super.key});

  @override
  State<CreatorsScreen> createState() => _CreatorsScreenState();
}

class _CreatorsScreenState extends State<CreatorsScreen> {
  late Future<List<UserProfile>> _f = Social.topCreators();
  final Map<String, bool> _following = <String, bool>{};

  Future<void> _toggle(UserProfile u) async {
    if (!await requireLogin(context)) return;
    final bool now = !(_following[u.uid] ?? u.isFollowing);
    setState(() => _following[u.uid] = now);
    try {
      await Social.setFollow(u.uid, now);
    } catch (e) {
      if (mounted) {
        setState(() => _following[u.uid] = !now);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('اكتشف صنّاع المقاطع'),
      ),
      body: RefreshIndicator(
        color: AppColors.brandGreen,
        onRefresh: () async {
          setState(() => _f = Social.topCreators());
          await _f;
        },
        child: FutureBuilder<List<UserProfile>>(
          future: _f,
          builder: (BuildContext context, AsyncSnapshot<List<UserProfile>> s) {
            if (s.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.brandGreen),
              );
            }
            final List<UserProfile> l = s.data ?? const <UserProfile>[];
            if (l.isEmpty) {
              return ListView(
                children: const <Widget>[
                  SizedBox(height: 140),
                  Center(
                    child: Text(
                      'لا يوجد صنّاع بعد — كن أول من ينشر مقطعًا!',
                      style: TextStyle(fontFamily: kFont, color: AppColors.sub),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: l.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.stroke),
              itemBuilder: (BuildContext c, int i) {
                final UserProfile u = l[i];
                final bool f = _following[u.uid] ?? u.isFollowing;
                return ListTile(
                  onTap: () => openUserProfile(c, u.uid),
                  leading: UserAvatar(name: u.name, size: 46),
                  title: Text(
                    u.name,
                    style: const TextStyle(
                      fontFamily: kFont,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    u.bio.isNotEmpty
                        ? u.bio
                        : '${compactCount(u.followers)} متابِع · ${compactCount(u.clips)} مقطع',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kFont,
                      color: AppColors.sub,
                    ),
                  ),
                  trailing: f
                      ? OutlinedButton(
                          onPressed: () => _toggle(u),
                          child: const Text(
                            'تتابعه',
                            style: TextStyle(
                              fontFamily: kFont,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : FilledButton(
                          key: ValueKey<String>('follow:${u.uid}'),
                          onPressed: () => _toggle(u),
                          child: const Text(
                            'متابعة',
                            style: TextStyle(fontFamily: kFont),
                          ),
                        ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Settings → blocked people (unblock).
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  final Map<String, String> _names = <String, String>{};

  @override
  void initState() {
    super.initState();
    for (final String uid in Blocks.I.blocked) {
      CloudDb.I.get('users/$uid/name').then((dynamic n) {
        if (mounted && n != null) setState(() => _names[uid] = n.toString());
      }, onError: (Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('المحظورون'),
      ),
      body: ListenableBuilder(
        listenable: Blocks.I,
        builder: (BuildContext context, _) {
          final List<String> l = Blocks.I.blocked.toList();
          if (l.isEmpty) {
            return const Center(
              child: Text(
                'لم تحظر أحدًا.',
                style: TextStyle(fontFamily: kFont, color: AppColors.sub),
              ),
            );
          }
          return ListView(
            children: <Widget>[
              for (final String uid in l)
                ListTile(
                  leading: UserAvatar(name: _names[uid] ?? '?', size: 40),
                  title: Text(
                    _names[uid] ?? 'مستخدم',
                    style: const TextStyle(
                      fontFamily: kFont,
                      color: Colors.white,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () => Blocks.I.unblock(uid),
                    child: const Text(
                      'إلغاء الحظر',
                      style: TextStyle(fontFamily: kFont),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
