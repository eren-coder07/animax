import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/app_prefs.dart';
import '../core/cloud.dart';
import '../core/social.dart';
import '../screens/auth_screen.dart';
import '../screens/user_profile_screen.dart';
import 'mb_ui.dart';

/// Views · like · comments for any item (Akwam, anime, cartoon, manga, 18+).
class SocialBar extends StatefulWidget {
  const SocialBar({
    super.key,
    required this.itemKey,
    required this.title,
    this.viewsLabel = 'مشاهدة',
  });

  /// e.g. `akwam:/movie/1/x`, `anime:123`, `manga:uuid`.
  final String itemKey;
  final String title;

  /// "مشاهدة" for videos, "قراءة" for manga.
  final String viewsLabel;

  @override
  State<SocialBar> createState() => _SocialBarState();
}

class _SocialBarState extends State<SocialBar> {
  ItemStats _s = const ItemStats();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    CloudAuth.I.addListener(_load);
  }

  @override
  void didUpdateWidget(SocialBar old) {
    super.didUpdateWidget(old);
    if (old.itemKey != widget.itemKey) _load();
  }

  @override
  void dispose() {
    CloudAuth.I.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ItemStats s = await Social.stats(widget.itemKey);
      if (mounted) setState(() => _s = s);
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_busy || !await requireLogin(context)) return;
    final bool like = !_s.liked;
    setState(() {
      _busy = true;
      _s = ItemStats(
          views: _s.views,
          likes: (_s.likes + (like ? 1 : -1)).clamp(0, 1 << 31),
          comments: _s.comments,
          liked: like);
    });
    try {
      await Social.setLike(widget.itemKey, like);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comments() async {
    await showComments(context,
        threadPath: 'comments',
        threadKey: widget.itemKey,
        counterPath: 'items/${CloudDb.key(widget.itemKey)}',
        title: widget.title);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String text,
            {VoidCallback? onTap, Color color = Colors.white}) =>
        Material(
          color: AppColors.surfaceHi,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 19, color: color),
                  const SizedBox(width: 6),
                  Text(text,
                      style: TextStyle(
                          fontFamily: kFont, fontSize: 14, color: color)),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: <Widget>[
          chip(Icons.visibility_outlined,
              '${compactCount(_s.views)} ${widget.viewsLabel}'),
          chip(_s.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              compactCount(_s.likes),
              onTap: _toggleLike,
              color: _s.liked ? const Color(0xFFFF4D6D) : Colors.white),
          chip(Icons.chat_bubble_outline_rounded,
              '${compactCount(_s.comments)} تعليق',
              onTap: _comments),
        ],
      ),
    );
  }
}

/// Comments sheet for an item or a clip.
Future<void> showComments(
  BuildContext context, {
  required String threadPath,
  required String threadKey,
  required String counterPath,
  required String title,
  String ownerUid = '',
  String clipId = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: _CommentsSheet(
          threadPath: threadPath,
          threadKey: threadKey,
          counterPath: counterPath,
          title: title,
          ownerUid: ownerUid,
          clipId: clipId,
        ),
      ),
    ),
  );
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.threadPath,
    required this.threadKey,
    required this.counterPath,
    required this.title,
    this.ownerUid = '',
    this.clipId = '',
  });
  final String threadPath;
  final String threadKey;
  final String counterPath;
  final String title;

  /// Owner of the commented clip (gets an inbox notice).
  final String ownerUid;
  final String clipId;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _ctl = TextEditingController();
  List<Comment>? _list;
  final Map<String, bool> _liked = <String, bool>{};
  final Map<String, int> _likes = <String, int>{};
  String? _error;
  bool _sending = false;

  /// Next comment is marked as a spoiler.
  bool _spoiler = false;
  final Set<String> _revealed = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<Comment> l =
          await Social.comments(widget.threadPath, widget.threadKey);
      if (!mounted) return;
      setState(() {
        _list = l;
        for (final Comment c in l) {
          _likes[c.id] = c.likes;
        }
      });
      for (final Comment c in l.take(40)) {
        Social.commentLiked(widget.threadPath, widget.threadKey, c.id)
            .then((bool v) {
          if (mounted && v) setState(() => _liked[c.id] = true);
        }).catchError((Object _) {});
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _send() async {
    if (!await requireLogin(context)) return;
    setState(() => _sending = true);
    try {
      final Comment c = await Social.addComment(widget.threadPath,
          widget.threadKey, widget.counterPath, _ctl.text,
          spoiler: _spoiler,
          ownerUid: widget.ownerUid,
          title: widget.title,
          clipId: widget.clipId);
      _ctl.clear();
      _spoiler = false;
      setState(() => _list = <Comment>[c, ...?_list]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(Comment c) async {
    if (!await requireLogin(context)) return;
    final bool like = !(_liked[c.id] ?? false);
    setState(() {
      _liked[c.id] = like;
      _likes[c.id] = ((_likes[c.id] ?? 0) + (like ? 1 : -1)).clamp(0, 1 << 31);
    });
    try {
      await Social.setCommentLike(
          widget.threadPath, widget.threadKey, c.id, like,
          authorUid: c.uid, text: c.text);
    } catch (_) {}
  }

  static String _ago(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'الآن';
    if (d.inMinutes < 60) return 'منذ ${d.inMinutes} د';
    if (d.inHours < 24) return 'منذ ${d.inHours} س';
    return 'منذ ${d.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    final String me = CloudAuth.I.user?.uid ?? '';
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text('التعليقات · ${widget.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: kFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _list == null
              ? Center(
                  child: _error != null
                      ? Text(_error!,
                          style: const TextStyle(
                              fontFamily: kFont, color: AppColors.sub))
                      : const CircularProgressIndicator(
                          color: AppColors.brandGreen))
              : _list!.isEmpty
                  ? const Center(
                      child: Text('لا توجد تعليقات بعد — كن أول من يعلّق!',
                          style: TextStyle(
                              fontFamily: kFont,
                              fontSize: 15,
                              color: AppColors.sub)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _list!.length,
                      itemBuilder: (BuildContext c, int i) {
                        final Comment cm = _list![i];
                        final bool liked = _liked[cm.id] ?? false;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              GestureDetector(
                                onTap: () => openUserProfile(c, cm.uid),
                                child: UserAvatar(name: cm.name, size: 36),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        GestureDetector(
                                          onTap: () =>
                                              openUserProfile(c, cm.uid),
                                          child: Text(cm.name,
                                              style: const TextStyle(
                                                  fontFamily: kFont,
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.sub)),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(_ago(cm.at),
                                            style: const TextStyle(
                                                fontFamily: kFont,
                                                fontSize: 12,
                                                color: AppColors.muted)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    if (cm.spoiler &&
                                        cm.uid != me &&
                                        AppPrefs.I.spoilerShield &&
                                        !_revealed.contains(cm.id))
                                      GestureDetector(
                                        key: const Key('spoilerComment'),
                                        onTap: () =>
                                            setState(() => _revealed.add(cm.id)),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: <Widget>[
                                            ImageFiltered(
                                              imageFilter: ui.ImageFilter.blur(
                                                  sigmaX: 6, sigmaY: 6),
                                              child: Text(cm.text,
                                                  style: const TextStyle(
                                                      fontFamily: kFont,
                                                      fontSize: 15,
                                                      height: 1.5,
                                                      color: Colors.white)),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.black87,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: const Text(
                                                  '🛡️ حرق — اضغط للكشف',
                                                  style: TextStyle(
                                                      fontFamily: kFont,
                                                      fontSize: 12.5,
                                                      color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Text(cm.text,
                                          style: const TextStyle(
                                              fontFamily: kFont,
                                              fontSize: 15,
                                              height: 1.5,
                                              color: Colors.white)),
                                    if (cm.uid == me)
                                      GestureDetector(
                                        onTap: () async {
                                          await Social.deleteComment(
                                              widget.threadPath,
                                              widget.threadKey,
                                              widget.counterPath,
                                              cm);
                                          setState(() => _list!.remove(cm));
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.only(top: 4),
                                          child: Text('حذف',
                                              style: TextStyle(
                                                  fontFamily: kFont,
                                                  fontSize: 12.5,
                                                  color: AppColors.muted)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _toggleLike(cm),
                                child: Column(
                                  children: <Widget>[
                                    Icon(
                                        liked
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        size: 20,
                                        color: liked
                                            ? const Color(0xFFFF4D6D)
                                            : AppColors.sub),
                                    Text(compactCount(_likes[cm.id] ?? 0),
                                        style: const TextStyle(
                                            fontFamily: kFont,
                                            fontSize: 11.5,
                                            color: AppColors.sub)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: <Widget>[
                IconButton(
                  key: const Key('spoilerToggle'),
                  tooltip: _spoiler ? 'مُعلَّم كحرق' : 'علّم كحرق',
                  icon: Icon(
                      _spoiler ? Icons.shield_rounded : Icons.shield_outlined,
                      color: _spoiler ? AppColors.brandGreen : AppColors.sub),
                  onPressed: () => setState(() => _spoiler = !_spoiler),
                ),
                Expanded(
                  child: TextField(
                    controller: _ctl,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    style: const TextStyle(
                        fontFamily: kFont, fontSize: 15, color: Colors.white),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: CloudAuth.I.signedIn
                          ? (_spoiler ? 'تعليق يحتوي حرقًا…' : 'أضف تعليقًا…')
                          : 'سجّل الدخول لتعليق…',
                      hintStyle: const TextStyle(
                          fontFamily: kFont, color: AppColors.muted),
                      filled: true,
                      fillColor: AppColors.surfaceHi,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: const BoxDecoration(
                        gradient: AppColors.brandGrad, shape: BoxShape.circle),
                    child: IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF07130D)))
                          : const Icon(Icons.send_rounded,
                              color: Color(0xFF07130D)),
                      onPressed: _sending ? null : _send,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Letter avatar with a stable gradient per name.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.size = 40});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    const List<List<Color>> palettes = <List<Color>>[
      <Color>[Color(0xFF1FC8EE), Color(0xFF2EE58B)],
      <Color>[Color(0xFFFF7A59), Color(0xFFFF4D6D)],
      <Color>[Color(0xFF8B5CF6), Color(0xFF2E90FA)],
      <Color>[Color(0xFFFFC21A), Color(0xFFFF7A59)],
      <Color>[Color(0xFF2EE58B), Color(0xFF16A34A)],
    ];
    final List<Color> p =
        palettes[name.codeUnits.fold<int>(0, (int a, int b) => a + b) % palettes.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: p),
      ),
      child: Text(name.isEmpty ? '؟' : name.characters.first.toUpperCase(),
          style: TextStyle(
              fontFamily: kFont,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
              color: Colors.white)),
    );
  }
}
