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

  Future<void> _edit(UserProfile p) async {
    final TextEditingController name = TextEditingController(text: p.name);
    final TextEditingController bio = TextEditingController(text: p.bio);
    final bool? save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              18, 18, 18, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('تعديل الملف الشخصي',
                  style: TextStyle(
                      fontFamily: kFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 14),
              TextField(
                key: const Key('editName'),
                controller: name,
                maxLength: 40,
                style: const TextStyle(fontFamily: kFont, color: Colors.white),
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              TextField(
                key: const Key('editBio'),
                controller: bio,
                maxLength: 160,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(fontFamily: kFont, color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'نبذة عنك', hintText: 'مثلاً: محب للأنمي والأفلام الكورية'),
              ),
              const SizedBox(height: 12),
              GradientButton(
                  label: 'حفظ',
                  height: 46,
                  expand: true,
                  onTap: () => Navigator.pop(ctx, true)),
            ],
          ),
        ),
      ),
    );
    if (save != true) return;
    try {
      await Social.updateProfile(name: name.text, bio: bio.text);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
                  if (p.bio.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(30, 6, 30, 0),
                      child: Text(p.bio,
                          key: const Key('profileBio'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontFamily: kFont,
                              fontSize: 14,
                              height: 1.5,
                              color: AppColors.sub)),
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
                  if (me)
                    Center(
                      child: OutlinedButton.icon(
                        key: const Key('editProfile'),
                        onPressed: () => _edit(p),
                        icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                        label: const Text('تعديل الملف الشخصي',
                            style: TextStyle(fontFamily: kFont, color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.sub),
                            shape: const StadiumBorder()),
                      ),
                    ),
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
