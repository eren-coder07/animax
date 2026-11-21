import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/cloud.dart';
import '../core/social.dart';
import '../widgets/mb_ui.dart';
import '../widgets/social_bar.dart';
import 'auth_screen.dart';
import 'clips_screen.dart';

void openUserProfile(BuildContext context, String uid) {
  if (uid.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UserProfileScreen(uid: uid)));
}

/// A user's page: avatar, counts, follow button, their clips + reposts.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.uid});
  final String uid;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  UserProfile? _p;
  List<VideoClip>? _clips;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final UserProfile? p = await Social.profile(widget.uid);
      final List<VideoClip> clips = await Social.clipsOf(widget.uid);
      if (!mounted) return;
      setState(() {
        _p = p;
        _clips = clips;
        if (p == null) _error = 'المستخدم غير موجود.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleFollow() async {
    final UserProfile? p = _p;
    if (p == null || _busy || !await requireLogin(context)) return;
    setState(() => _busy = true);
    try {
      await Social.setFollow(p.uid, !p.isFollowing);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UserProfile? p = _p;
    final bool me = CloudAuth.I.user?.uid == widget.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(backgroundColor: AppColors.bg, title: Text(p?.name ?? '')),
      body: p == null
          ? Center(
              child: _error != null
                  ? Text(_error!,
                      style: const TextStyle(
                          fontFamily: kFont, color: AppColors.sub))
                  : const CircularProgressIndicator(
                      color: AppColors.brandGreen))
          : RefreshIndicator(
              color: AppColors.brandGreen,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: <Widget>[
                  const SizedBox(height: 10),
                  Center(child: UserAvatar(name: p.name, size: 86)),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(p.name,
                        style: const TextStyle(
                            fontFamily: kFont,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _count(compactCount(p.followers), 'متابِع'),
                      _count(compactCount(p.following), 'يتابع'),
                      _count(compactCount(p.clips), 'مقطع'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!me)
                    Center(
                      child: SizedBox(
                        width: 200,
                        child: p.isFollowing
                            ? OutlinedButton(
                                onPressed: _busy ? null : _toggleFollow,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: AppColors.sub),
                                  shape: const StadiumBorder(),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text('تتابعه',
                                    style: TextStyle(
                                        fontFamily: kFont, fontSize: 15)),
                              )
                            : GradientButton(
                                label: 'متابعة',
                                icon: Icons.person_add_alt_1_rounded,
                                height: 46,
                                expand: true,
                                onTap: _busy ? null : _toggleFollow,
                              ),
                      ),
                    ),
                  const RowHeader('المقاطع وإعادة النشر'),
                  if (_clips == null)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.brandGreen)),
                    )
                  else if (_clips!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: Text('لا توجد مقاطع بعد.',
                            style: TextStyle(
                                fontFamily: kFont, color: AppColors.sub)),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.62,
                        children: <Widget>[
                          for (int i = 0; i < _clips!.length; i++)
                            ClipThumb(
                              clip: _clips![i],
                              reposted: _clips![i].uid != widget.uid,
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => ClipsViewer(
                                          clips: _clips!, initial: i))),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _count(String n, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          children: <Widget>[
            Text(n,
                style: const TextStyle(
                    fontFamily: kFont,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            Text(label,
                style: const TextStyle(
                    fontFamily: kFont, fontSize: 13, color: AppColors.sub)),
          ],
        ),
      );
}
