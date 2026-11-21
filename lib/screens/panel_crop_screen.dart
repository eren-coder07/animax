import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../core/panels.dart';
import '../core/social.dart';
import '../widgets/mb_ui.dart' show kFont, NetImage;
import 'auth_screen.dart';
import 'clips_screen.dart' show ClipReply, kClipsTab;

/// Opens the panel cropper for one manga page; publishes a panel clip.
Future<void> showPanelCropper(
  BuildContext context, {
  required String imageUrl,
  required String mangaId,
  required String mangaTitle,
  required String cover,
  required String chapterId,
  required String chapterLabel,
  required int page,
}) async {
  if (!await requireLogin(context)) return;
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PanelCropScreen(
        imageUrl: imageUrl,
        mangaId: mangaId,
        mangaTitle: mangaTitle,
        cover: cover,
        chapterId: chapterId,
        chapterLabel: chapterLabel,
        page: page,
      ),
    ),
  );
}

class PanelCropScreen extends StatefulWidget {
  const PanelCropScreen({
    super.key,
    required this.imageUrl,
    required this.mangaId,
    required this.mangaTitle,
    required this.cover,
    required this.chapterId,
    required this.chapterLabel,
    required this.page,
  });

  final String imageUrl;
  final String mangaId;
  final String mangaTitle;
  final String cover;
  final String chapterId;
  final String chapterLabel;
  final int page;

  @override
  State<PanelCropScreen> createState() => _PanelCropScreenState();
}

enum _Drag { move, tl, tr, bl, br }

class _PanelCropScreenState extends State<PanelCropScreen> {
  Size? _img; // natural image size
  Rect _r = const Rect.fromLTWH(0.1, 0.3, 0.8, 0.35); // normalized
  _Drag? _drag;
  bool _busy = false;
  final TextEditingController _caption = TextEditingController();
  ImageStream? _stream;
  ImageStreamListener? _listener;

  static const double _minSide = 0.08;

  @override
  void initState() {
    super.initState();
    final ImageStream st = NetworkImage(widget.imageUrl)
        .resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener((ImageInfo info, bool _) {
      if (mounted) {
        setState(
          () => _img = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ),
        );
      }
    }, onError: (Object _, StackTrace? _) {});
    st.addListener(_listener!);
    _stream = st;
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _caption.dispose();
    super.dispose();
  }

  /// Where the image is drawn (BoxFit.contain) inside [box].
  Rect _imageRect(Size box) {
    final Size img = _img!;
    final double s = (box.width / img.width) < (box.height / img.height)
        ? box.width / img.width
        : box.height / img.height;
    final Size d = Size(img.width * s, img.height * s);
    return Offset((box.width - d.width) / 2, (box.height - d.height) / 2) & d;
  }

  void _start(Offset p, Rect shown) {
    final Rect c = Rect.fromLTWH(
      shown.left + _r.left * shown.width,
      shown.top + _r.top * shown.height,
      _r.width * shown.width,
      _r.height * shown.height,
    );
    const double grab = 36;
    if ((p - c.topLeft).distance < grab) {
      _drag = _Drag.tl;
    } else if ((p - c.topRight).distance < grab) {
      _drag = _Drag.tr;
    } else if ((p - c.bottomLeft).distance < grab) {
      _drag = _Drag.bl;
    } else if ((p - c.bottomRight).distance < grab) {
      _drag = _Drag.br;
    } else if (c.inflate(8).contains(p)) {
      _drag = _Drag.move;
    } else {
      _drag = null;
    }
  }

  void _update(Offset delta, Rect shown) {
    final double dx = delta.dx / shown.width, dy = delta.dy / shown.height;
    double l = _r.left, t = _r.top, r = _r.right, b = _r.bottom;
    switch (_drag) {
      case _Drag.move:
        final double w = _r.width, h = _r.height;
        l = (l + dx).clamp(0.0, 1.0 - w);
        t = (t + dy).clamp(0.0, 1.0 - h);
        r = l + w;
        b = t + h;
      case _Drag.tl:
        l = (l + dx).clamp(0.0, r - _minSide);
        t = (t + dy).clamp(0.0, b - _minSide);
      case _Drag.tr:
        r = (r + dx).clamp(l + _minSide, 1.0);
        t = (t + dy).clamp(0.0, b - _minSide);
      case _Drag.bl:
        l = (l + dx).clamp(0.0, r - _minSide);
        b = (b + dy).clamp(t + _minSide, 1.0);
      case _Drag.br:
        r = (r + dx).clamp(l + _minSide, 1.0);
        b = (b + dy).clamp(t + _minSide, 1.0);
      case null:
        return;
    }
    setState(() => _r = Rect.fromLTRB(l, t, r, b));
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    final VideoClip? replyTo = ClipReply.pending;
    try {
      await Social.createClip(
        VideoClip(
          title: widget.mangaTitle,
          label: '${widget.chapterLabel} · صفحة ${widget.page + 1}',
          poster: widget.cover,
          kind: 'manga',
          source: 'manga',
          ref: Panels.refFor(
            mangaId: widget.mangaId,
            chapterId: widget.chapterId,
            page: widget.page,
            r: _r,
          ),
          startMs: 0,
          endMs: Panels.showMs,
          replyTo: replyTo?.id ?? '',
          caption: _caption.text.trim(),
        ),
      );
      if (replyTo != null) ClipReply.pending = null;
      if (!mounted) return;
      final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      m.showSnackBar(
        SnackBar(
          persist: false,
          duration: const Duration(seconds: 3),
          content: const Text('تم نشر اللوحة ✂️'),
          action: SnackBarAction(
            label: 'عرض',
            onPressed: () => AppState.I.setTab(kClipsTab),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('✂️ قص لوحة', style: TextStyle(fontFamily: kFont)),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              key: const Key('publishPanel'),
              onPressed: _img == null || _busy ? null : _publish,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('نشر', style: TextStyle(fontFamily: kFont)),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (ClipReply.pending != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: AppColors.brandGreen.withValues(alpha: 0.14),
              child: Text(
                'ردًا على @${ClipReply.pending!.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: kFont, color: Colors.white),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'اسحب الإطار أو زواياه لتحديد اللوحة التي تريد مشاركتها.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: kFont,
                fontSize: 13.5,
                color: AppColors.sub,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (BuildContext ctx, BoxConstraints c) {
                  if (_img == null) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brandGreen,
                      ),
                    );
                  }
                  final Size box = Size(c.maxWidth, c.maxHeight);
                  final Rect shown = _imageRect(box);
                  final Rect crop = Rect.fromLTWH(
                    shown.left + _r.left * shown.width,
                    shown.top + _r.top * shown.height,
                    _r.width * shown.width,
                    _r.height * shown.height,
                  );
                  return GestureDetector(
                    key: const Key('panelCropArea'),
                    onPanStart: (DragStartDetails d) =>
                        _start(d.localPosition, shown),
                    onPanUpdate: (DragUpdateDetails d) =>
                        _update(d.delta, shown),
                    onPanEnd: (_) => _drag = null,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fromRect(
                          rect: shown,
                          child: Image.network(
                            widget.imageUrl,
                            fit: BoxFit.fill,
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(painter: _CropPainter(crop)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: _caption,
                    maxLength: 150,
                    style: const TextStyle(
                      fontFamily: kFont,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'وصف اللوحة (اختياري)…',
                      hintStyle: TextStyle(
                        fontFamily: kFont,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 34,
                        height: 48,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: NetImage(widget.cover),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${widget.mangaTitle}\n${widget.chapterLabel} · صفحة ${widget.page + 1}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: kFont,
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.crop);
  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final Path dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(crop);
    canvas.drawPath(dim, Paint()..color = const Color(0xAA000000));
    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.brandGreen,
    );
    final Paint h = Paint()..color = AppColors.brandGreen;
    for (final Offset o in <Offset>[
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
    ]) {
      canvas.drawCircle(o, 9, h);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop;
}

/// A manga panel inside the Clips feed: the cropped region of the page,
/// scaled to fit, with a slow zoom ("Ken Burns") while it is on screen.
class PanelClipView extends StatefulWidget {
  const PanelClipView({
    super.key,
    required this.clip,
    required this.playing,
    this.onTick,
  });
  final VideoClip clip;
  final bool playing;

  /// Called on every animation frame (the feed redraws its progress bar).
  final VoidCallback? onTick;

  @override
  State<PanelClipView> createState() => PanelClipViewState();
}

class PanelClipViewState extends State<PanelClipView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: Panels.showMs),
  );
  String? _url;
  String? _error;

  /// 0..1 through the panel's display window (drives the feed progress bar).
  double get progress => _a.value;

  @override
  void initState() {
    super.initState();
    _a.addListener(() {
      if (mounted) setState(() {});
      widget.onTick?.call();
    });
    Panels.pageUrl(
          widget.clip.ref['chapterId'] ?? '',
          int.tryParse(widget.clip.ref['page'] ?? '') ?? 0,
        )
        .then((String u) {
          if (!mounted) return;
          setState(() => _url = u);
          if (widget.playing) _a.repeat();
        })
        .catchError((Object _) {
          if (mounted) {
            setState(() => _error = 'تعذّر تحميل اللوحة من MangaDex حاليًا.');
          }
        });
  }

  @override
  void didUpdateWidget(PanelClipView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_a.isAnimating && _url != null) _a.repeat();
    if (!widget.playing) _a.stop();
  }

  void togglePause() {
    _a.isAnimating ? _a.stop() : _a.repeat();
  }

  bool get paused => !_a.isAnimating;

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(fontFamily: kFont, color: Colors.white),
        ),
      );
    }
    if (_url == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandGreen),
      );
    }
    final Rect r = Panels.rectOf(widget.clip.ref);
    // Align(widthFactor/heightFactor) keeps only the crop of the page; the
    // alignment places the crop's origin. FittedBox scales it to the screen.
    final double ax = r.width >= 1 ? 0 : (r.left / (1 - r.width)) * 2 - 1;
    final double ay = r.height >= 1 ? 0 : (r.top / (1 - r.height)) * 2 - 1;
    final double zoom = 1 + 0.08 * Curves.easeInOut.transform(_a.value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 70, 10, 150),
      child: Center(
        child: Transform.scale(
          scale: zoom,
          child: FittedBox(
            fit: BoxFit.contain,
            child: ClipRect(
              child: Align(
                alignment: Alignment(ax, ay),
                widthFactor: r.width,
                heightFactor: r.height,
                child: Image.network(
                  _url!,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white24,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shares a panel clip as a real PNG of the cropped panel.
Future<void> sharePanelImage(BuildContext context, VideoClip clip) async {
  final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
  m.showSnackBar(
    const SnackBar(
      persist: false,
      duration: Duration(seconds: 2),
      content: Text('جارٍ تجهيز اللوحة…'),
    ),
  );
  try {
    final List<int> png = await Panels.panelPng(clip);
    final DownloadItem it = await DownloadManager.I.saveImageFile(
      png,
      title: clip.title,
      subtitle: clip.label,
      poster: clip.poster,
    );
    await DownloadManager.I.shareFile(it);
  } catch (_) {
    m.showSnackBar(
      const SnackBar(content: Text('تعذّر تجهيز اللوحة — حاول مرة أخرى.')),
    );
  }
}
