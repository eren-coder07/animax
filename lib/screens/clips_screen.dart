import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/akwam_api.dart';
import '../core/app_data.dart';
import '../core/api_html.dart' show AnimeWatchId;
import '../core/app_state.dart';
import '../core/hh_api.dart';
import '../core/app_theme.dart';
import '../core/cloud.dart';
import '../core/download_manager.dart';
import '../core/social.dart';
import '../widgets/mb_ui.dart';
import '../widgets/social_bar.dart';
import 'auth_screen.dart';
import 'user_profile_screen.dart';

/// Index of the Clips tab in the bottom bar.
const int kClipsTab = 1;

// =============================================================================
// Feed tab
// =============================================================================

class ClipsFeedScreen extends StatefulWidget {
  const ClipsFeedScreen({super.key});

  @override
  State<ClipsFeedScreen> createState() => _ClipsFeedScreenState();
}

class _ClipsFeedScreenState extends State<ClipsFeedScreen> {
  List<VideoClip>? _clips;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final List<VideoClip> c = await Social.clipsFeed();
      if (mounted) setState(() => _clips = c);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (BuildContext context, _) {
        final bool visible = AppState.I.navIndex == kClipsTab;
        final List<VideoClip>? c = _clips;
        if (c == null) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: _error != null
                  ? _Retry(message: _error!, onRetry: _load)
                  : const CircularProgressIndicator(color: AppColors.brandGreen),
            ),
          );
        }
        if (c.isEmpty) {
          return ColoredBox(
            color: AppColors.bg,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.content_cut_rounded,
                        size: 56, color: AppColors.brandGreen),
                    const SizedBox(height: 14),
                    const Text('لا توجد مقاطع بعد',
                        style: TextStyle(
                            fontFamily: kFont,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 8),
                    const Text(
                        'اصنع أول مقطع: افتح أي فيلم أو حلقة واضغط ✂️ في المشغّل لقص 10 ثوانٍ ومشاركتها.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: kFont,
                            fontSize: 14.5,
                            height: 1.6,
                            color: AppColors.sub)),
                    const SizedBox(height: 18),
                    GradientButton(
                        label: 'تحديث', icon: Icons.refresh_rounded, onTap: _load),
                  ],
                ),
              ),
            ),
          );
        }
        return ClipsPager(clips: c, active: visible, onRefresh: _load);
      },
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message,
              style: const TextStyle(fontFamily: kFont, color: AppColors.sub)),
          const SizedBox(height: 12),
          GradientButton(label: 'إعادة المحاولة', height: 42, onTap: onRetry),
        ],
      );
}

/// Full-screen viewer (from a profile grid).
class ClipsViewer extends StatelessWidget {
  const ClipsViewer({super.key, required this.clips, this.initial = 0});
  final List<VideoClip> clips;
  final int initial;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            ClipsPager(clips: clips, initial: initial, active: true),
            SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      );
}

/// Vertical swipe pager — only the visible clip plays.
class ClipsPager extends StatefulWidget {
  const ClipsPager({
    super.key,
    required this.clips,
    this.initial = 0,
    this.active = true,
    this.onRefresh,
  });
  final List<VideoClip> clips;
  final int initial;
  final bool active;
  final Future<void> Function()? onRefresh;

  @override
  State<ClipsPager> createState() => _ClipsPagerState();
}

class _ClipsPagerState extends State<ClipsPager> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.brandGreen,
      onRefresh: widget.onRefresh ?? () async {},
      child: PageView.builder(
        controller: _pc,
        scrollDirection: Axis.vertical,
        itemCount: widget.clips.length,
        onPageChanged: (int i) => setState(() => _page = i),
        itemBuilder: (BuildContext c, int i) => ClipPage(
          key: ValueKey<String>(widget.clips[i].id),
          clip: widget.clips[i],
          playing: widget.active && i == _page,
        ),
      ),
    );
  }
}

// =============================================================================
// One clip
// =============================================================================

class ClipPage extends StatefulWidget {
  const ClipPage({super.key, required this.clip, required this.playing});
  final VideoClip clip;
  final bool playing;

  @override
  State<ClipPage> createState() => _ClipPageState();
}

class _ClipPageState extends State<ClipPage> {
  static final Map<String, ({String url, Map<String, String> headers, bool isHls})>
      _resolved = <String, ({String url, Map<String, String> headers, bool isHls})>{};

  VideoPlayerController? _c;
  String? _error;
  bool _liked = false;
  bool _reposted = false;
  late int _likes = widget.clip.likes;
  late int _comments = widget.clip.comments;
  late int _reposts = widget.clip.reposts;
  bool _counted = false;
  bool _muted = false;
  bool _opening = false;

  /// Opens the clip's full movie / series page, pausing the clip meanwhile.
  Future<void> _openSource() async {
    if (_opening) return;
    _opening = true;
    final bool wasPlaying = _c?.value.isPlaying ?? false;
    await _c?.pause();
    try {
      if (!mounted) return;
      await openClipSource(context, widget.clip);
    } finally {
      _opening = false;
      if (wasPlaying && mounted && widget.playing) await _c?.play();
    }
  }

  @override
  void initState() {
    super.initState();
    Social.clipState(widget.clip.id).then((({bool liked, bool reposted}) s) {
      if (mounted) {
        setState(() {
          _liked = s.liked;
          _reposted = s.reposted;
        });
      }
    }).catchError((Object _) {});
    if (widget.playing) _start();
  }

  @override
  void didUpdateWidget(ClipPage old) {
    super.didUpdateWidget(old);
    if (widget.playing && !old.playing) {
      _c == null ? _start() : _c!.play();
    } else if (!widget.playing && old.playing) {
      _c?.pause();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final VideoClip clip = widget.clip;
    try {
      final ({String url, Map<String, String> headers, bool isHls}) st =
          _resolved[clip.id] ??
              await DownloadManager.I.resolveStream(clip.source, clip.ref);
      _resolved[clip.id] = st;
      if (!mounted) return;
      final VideoPlayerController c = VideoPlayerController.networkUrl(
        Uri.parse(st.url),
        httpHeaders: st.headers,
        formatHint: st.isHls ? VideoFormat.hls : VideoFormat.other,
      );
      _c = c;
      await c.initialize();
      await c.seekTo(Duration(milliseconds: clip.startMs));
      await c.setVolume(_muted ? 0 : 1);
      c.addListener(_loop);
      if (widget.playing) await c.play();
      if (mounted) setState(() {});
      if (!_counted) {
        _counted = true;
        unawaited(Social.countClipView(clip.id));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'المصدر غير متاح حاليًا لهذا المقطع.');
      }
    }
  }

  /// Loops inside [startMs, endMs].
  void _loop() {
    final VideoPlayerController? c = _c;
    if (c == null || !c.value.isInitialized) return;
    final int pos = c.value.position.inMilliseconds;
    if (pos >= widget.clip.endMs || pos < widget.clip.startMs - 1500) {
      c.seekTo(Duration(milliseconds: widget.clip.startMs));
    }
    if (mounted) setState(() {});
  }

  Future<void> _like() async {
    if (!await requireLogin(context)) return;
    final bool like = !_liked;
    setState(() {
      _liked = like;
      _likes = (_likes + (like ? 1 : -1)).clamp(0, 1 << 31);
    });
    try {
      await Social.setClipLike(widget.clip.id, like);
    } catch (_) {}
  }

  Future<void> _repost() async {
    if (!await requireLogin(context)) return;
    final bool r = !_reposted;
    setState(() {
      _reposted = r;
      _reposts = (_reposts + (r ? 1 : -1)).clamp(0, 1 << 31);
    });
    try {
      await Social.setRepost(widget.clip.id, r);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(r ? 'أُعيد نشر المقطع في ملفك' : 'أُلغيت إعادة النشر'),
            duration: const Duration(seconds: 2)));
      }
    } catch (_) {}
  }

  Future<void> _comment() async {
    await showComments(context,
        threadPath: 'clipComments',
        threadKey: widget.clip.id,
        counterPath: 'clips/${widget.clip.id}',
        title: widget.clip.title);
    final dynamic n = await CloudDb.I
        .get('clips/${widget.clip.id}/comments')
        .catchError((Object _) => null);
    if (mounted && n is num) setState(() => _comments = n.toInt());
  }

  Future<void> _share() => showClipShare(context, widget.clip);

  @override
  Widget build(BuildContext context) {
    final VideoClip clip = widget.clip;
    final VideoPlayerController? c = _c;
    final bool ready = c != null && c.value.isInitialized;
    final double progress = ready
        ? ((c.value.position.inMilliseconds - clip.startMs) /
                (clip.endMs - clip.startMs))
            .clamp(0.0, 1.0)
        : 0;
    return GestureDetector(
      onTap: () {
        if (!ready) return;
        c.value.isPlaying ? c.pause() : c.play();
        setState(() {});
      },
      onDoubleTap: () {
        if (!_liked) _like();
      },
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (!ready) Opacity(opacity: 0.35, child: NetImage(clip.poster)),
            if (ready)
              Center(
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                  child: VideoPlayer(c),
                ),
              )
            else
              Center(
                child: _error != null
                    ? Text(_error!,
                        style: const TextStyle(
                            fontFamily: kFont, color: Colors.white))
                    : const CircularProgressIndicator(
                        color: AppColors.brandGreen),
              ),
            if (ready && !c.value.isPlaying)
              const Center(
                  child: Icon(Icons.play_arrow_rounded,
                      size: 80, color: Colors.white70)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: <double>[0, 0.6, 1],
                  colors: <Color>[
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xCC000000)
                  ],
                ),
              ),
            ),
            // Actions column.
            PositionedDirectional(
              end: 8,
              bottom: 110,
              child: Column(
                children: <Widget>[
                  _action(
                      _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      compactCount(_likes),
                      _like,
                      color: _liked ? const Color(0xFFFF4D6D) : Colors.white),
                  _action(Icons.chat_bubble_rounded, compactCount(_comments), _comment),
                  _action(Icons.repeat_rounded, compactCount(_reposts), _repost,
                      color: _reposted ? AppColors.brandGreen : Colors.white),
                  _action(Icons.share_rounded, 'مشاركة', _share),
                  _action(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      '', () {
                    setState(() => _muted = !_muted);
                    _c?.setVolume(_muted ? 0 : 1);
                  }),
                ],
              ),
            ),
            // Creator + title.
            PositionedDirectional(
              start: 14,
              end: 80,
              bottom: 26,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  GestureDetector(
                    onTap: () => openUserProfile(context, clip.uid),
                    child: Row(
                      children: <Widget>[
                        UserAvatar(name: clip.name, size: 34),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text('@${clip.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: kFont,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _openSource,
                    child: Text(clip.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: kFont,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white54,
                            color: Colors.white)),
                  ),
                  if (clip.label.isNotEmpty)
                    Text(clip.label,
                        style: const TextStyle(
                            fontFamily: kFont, fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text('${compactCount(clip.views)} مشاهدة',
                      style: const TextStyle(
                          fontFamily: kFont, fontSize: 12.5, color: Colors.white60)),
                  const SizedBox(height: 10),
                  Material(
                    key: const Key('clipWatchFull'),
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _openSource,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.play_circle_fill_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 6),
                            Text('شاهد كاملًا',
                                style: TextStyle(
                                    fontFamily: kFont,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Progress of the 10 s window.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2.5,
                color: AppColors.brandGreen,
                backgroundColor: Colors.white12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {Color color = Colors.white}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            children: <Widget>[
              Icon(icon, color: color, size: 32,
                  shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 6)]),
              if (label.isNotEmpty)
                Text(label,
                    style: const TextStyle(
                        fontFamily: kFont,
                        fontSize: 12.5,
                        color: Colors.white,
                        shadows: <Shadow>[Shadow(color: Colors.black54, blurRadius: 6)])),
            ],
          ),
        ),
      );
}

/// Small grid tile for a clip (profiles).
class ClipThumb extends StatelessWidget {
  const ClipThumb(
      {super.key, required this.clip, required this.onTap, this.reposted = false});
  final VideoClip clip;
  final VoidCallback onTap;
  final bool reposted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            NetImage(clip.poster),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0xCC000000)],
                ),
              ),
            ),
            if (reposted)
              const PositionedDirectional(
                top: 6,
                start: 6,
                child: Icon(Icons.repeat_rounded, color: AppColors.brandGreen, size: 18),
              ),
            PositionedDirectional(
              start: 6,
              end: 6,
              bottom: 6,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                  Text(compactCount(clip.views),
                      style: const TextStyle(
                          fontFamily: kFont, fontSize: 12, color: Colors.white)),
                  const Spacer(),
                  const Icon(Icons.favorite_rounded, color: Colors.white, size: 13),
                  const SizedBox(width: 2),
                  Text(compactCount(clip.likes),
                      style: const TextStyle(
                          fontFamily: kFont, fontSize: 12, color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Sharing a clip
// =============================================================================

Future<void> showClipShare(BuildContext context, VideoClip clip) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (BuildContext sheet) => SafeArea(
      top: false,
      child: _ClipShareSheet(clip: clip),
    ),
  );
}

class _ClipShareSheet extends StatefulWidget {
  const _ClipShareSheet({required this.clip});
  final VideoClip clip;

  @override
  State<_ClipShareSheet> createState() => _ClipShareSheetState();
}

class _ClipShareSheetState extends State<_ClipShareSheet> {
  bool _busy = false;
  String _status = '';

  Future<void> _sendFile() async {
    setState(() {
      _busy = true;
      _status = 'جارٍ قص المقطع…';
    });
    try {
      final DownloadItem it = await DownloadManager.I.saveClipFile(
        source: widget.clip.source,
        ref: widget.clip.ref,
        startMs: widget.clip.startMs,
        endMs: widget.clip.endMs,
        title: widget.clip.title,
        subtitle: widget.clip.label,
        poster: widget.clip.poster,
      );
      if (mounted) Navigator.pop(context);
      await DownloadManager.I.shareFile(it);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = e.toString();
        });
      }
    }
  }

  Future<void> _sendText() async {
    final String t = '🎬 ${widget.clip.title}'
        '${widget.clip.label.isEmpty ? '' : ' — ${widget.clip.label}'}\n'
        'مقطع من @${widget.clip.name} على أنيماكس';
    Navigator.pop(context);
    await DownloadManager.I.shareText(t);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('مشاركة المقطع',
              style: TextStyle(
                  fontFamily: kFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 12),
          GradientButton(
            label: _busy ? 'لحظة…' : 'إرسال ملف المقطع (واتساب، تيليجرام…)',
            icon: Icons.send_rounded,
            height: 50,
            expand: true,
            onTap: _busy ? null : _sendFile,
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: kFont, fontSize: 13, color: AppColors.sub)),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _sendText,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.stroke),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('مشاركة كنص',
                style: TextStyle(fontFamily: kFont, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Making a clip (from a player)
// =============================================================================

/// Opens the clip maker at the current playback [position].
Future<void> showClipMaker(
  BuildContext context, {
  required Duration position,
  required Duration duration,
  required String title,
  String label = '',
  String poster = '',
  required String kind,
  required String source,
  required Map<String, String> ref,
}) async {
  if (!await requireLogin(context)) return;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: _ClipMaker(
        position: position,
        duration: duration,
        title: title,
        label: label,
        poster: poster,
        kind: kind,
        source: source,
        ref: ref,
      ),
    ),
  );
}

class _ClipMaker extends StatefulWidget {
  const _ClipMaker({
    required this.position,
    required this.duration,
    required this.title,
    required this.label,
    required this.poster,
    required this.kind,
    required this.source,
    required this.ref,
  });
  final Duration position;
  final Duration duration;
  final String title;
  final String label;
  final String poster;
  final String kind;
  final String source;
  final Map<String, String> ref;

  @override
  State<_ClipMaker> createState() => _ClipMakerState();
}

class _ClipMakerState extends State<_ClipMaker> {
  late int _len = 10; // seconds
  late double _start; // seconds
  bool _busy = false;

  int get _durS =>
      widget.duration.inSeconds <= 0 ? 1 << 20 : widget.duration.inSeconds;

  @override
  void initState() {
    super.initState();
    // Default: the last 10 seconds before the pause point.
    _start = (widget.position.inSeconds - _len).clamp(0, _durS - 1).toDouble();
  }

  static String _fmt(int s) {
    final int m = s ~/ 60, ss = s % 60;
    final int h = m ~/ 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m % 60)}:${two(ss)}' : '${two(m)}:${two(ss)}';
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    final int s = _start.round();
    final int e = (s + _len).clamp(s + 1, _durS);
    try {
      await Social.createClip(VideoClip(
        title: widget.title,
        label: '${widget.label.isEmpty ? '' : '${widget.label} · '}${_fmt(s)}',
        poster: widget.poster,
        kind: widget.kind,
        source: widget.source,
        ref: widget.ref,
        startMs: s * 1000,
        endMs: e * 1000,
      ));
      if (!mounted) return;
      final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      m.showSnackBar(SnackBar(
        content: const Text('تم نشر المقطع ✂️'),
        persist: false,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
            label: 'عرض', onPressed: () => AppState.I.setTab(kClipsTab)),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final int pos = widget.position.inSeconds;
    final double lo = (pos - 60).clamp(0, _durS).toDouble();
    final double hi = (pos + 60).clamp(lo + 1, _durS.toDouble()).toDouble();
    final int s = _start.round().clamp(lo.toInt(), hi.toInt());
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('✂️ اصنع مقطعًا',
                style: TextStyle(
                    fontFamily: kFont,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: kFont, fontSize: 14, color: AppColors.sub)),
            const SizedBox(height: 16),
            Text('من ${_fmt(s)} إلى ${_fmt(s + _len)}  ·  $_len ثوانٍ',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: kFont,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandGreen)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Slider(
                value: s.toDouble().clamp(lo, hi),
                min: lo,
                max: hi,
                activeColor: AppColors.brandGreen,
                onChanged: (double v) => setState(() => _start = v),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (final int l in <int>[3, 5, 10])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: ChoiceChip(
                      label: Text('$l ث',
                          style: const TextStyle(fontFamily: kFont)),
                      selected: _len == l,
                      onSelected: (_) => setState(() => _len = l),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            GradientButton(
              label: _busy ? 'جارٍ النشر…' : 'نشر المقطع',
              icon: Icons.upload_rounded,
              height: 50,
              expand: true,
              onTap: _busy ? null : _publish,
            ),
            const SizedBox(height: 8),
            const Text('سيظهر في تبويب «مقاطع» ويمكن للجميع الإعجاب والتعليق وإعادة النشر.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: kFont, fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Opens the details page of the movie / series a clip was cut from.
/// New clips carry the page in their ref; older ones fall back to a
/// catalog lookup or a title search.
Future<void> openClipSource(BuildContext context, VideoClip clip) async {
  final NavigatorState nav = Navigator.of(context);
  final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);
  void fail() => msg.showSnackBar(const SnackBar(
      content: Text('تعذّر فتح صفحة هذا الفيديو حاليًا.')));
  switch (clip.source) {
    case 'akwam':
      AkwamItem? item;
      final String path = clip.ref['item'] ?? '';
      if (path.isNotEmpty) {
        item = AkwamApi.itemFromPath(path, title: clip.title, poster: clip.poster);
      }
      if (item == null) {
        msg.showSnackBar(const SnackBar(
            duration: Duration(seconds: 2), content: Text('جارٍ فتح الصفحة…')));
        try {
          item = await AkwamApi.I.itemForWatch(clip.ref['path'] ?? '',
              title: clip.title, poster: clip.poster);
        } catch (_) {}
        if (item == null) {
          try {
            item = bestAkwamMatch(await AkwamApi.I.search(clip.title), clip.title);
          } catch (_) {}
        }
        msg.hideCurrentSnackBar();
      }
      if (item == null) return fail();
      await nav.pushNamed('/akwam-details', arguments: item);
      return;
    case 'anime':
      final String wid = clip.ref['watchId'] ?? '';
      Anime? a;
      for (final Anime x in AppState.I.catalog) {
        if (x.watchId == wid) {
          a = x;
          break;
        }
      }
      final String slug = clip.ref['slug'] ?? wid;
      if (a == null && slug.isEmpty) return fail();
      await nav.pushNamed('/details',
          arguments: a ??
              Anime(
                id: slug,
                title: clip.title,
                poster: clip.poster,
                score: 0,
                year: '',
                genres: const <String>[],
                synopsis: '',
                slug: slug,
              ));
      return;
    case 'hh':
      final String slug = clip.ref['slug'] ?? '';
      if (slug.isEmpty) return fail();
      await nav.pushNamed('/hh-details',
          arguments: HhSeries(id: 0, slug: slug, title: clip.title, thumb: clip.poster));
      return;
  }
  fail();
}

/// The search result whose title is exactly [title] (ignoring case and
/// spacing), or null — a wrong page is worse than none.
AkwamItem? bestAkwamMatch(List<AkwamItem> results, String title) {
  if (results.isEmpty) return null;
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final String t = norm(title);
  for (final AkwamItem r in results) {
    if (norm(r.title) == t) return r;
  }
  return null;
}
