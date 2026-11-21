import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/download_manager.dart';
import 'mb_ui.dart';

/// "مشاركة سريعة" — the fastest ways to get a video to a friend:
///  1. send the video file itself (instantly when downloaded, otherwise it
///     downloads and the share sheet opens automatically when done),
///  2. share a direct playable link (opens in any browser / VLC),
///  3. share the title as text.
///
/// [source]/[ref] describe a details-page item (resolved on demand);
/// for a stream already playing pass `source: 'url'` with [url]/[headers].
Future<void> showQuickShare(
  BuildContext context, {
  required String title,
  String subtitle = '',
  String poster = '',
  required String source,
  Map<String, String> ref = const <String, String>{},
  String url = '',
  Map<String, String> headers = const <String, String>{},
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _QuickShareSheet(
      title: title,
      subtitle: subtitle,
      poster: poster,
      source: source,
      ref: ref,
      url: url,
      headers: headers,
    ),
  );
}

class _QuickShareSheet extends StatefulWidget {
  const _QuickShareSheet({
    required this.title,
    required this.subtitle,
    required this.poster,
    required this.source,
    required this.ref,
    required this.url,
    required this.headers,
  });

  final String title;
  final String subtitle;
  final String poster;
  final String source;
  final Map<String, String> ref;
  final String url;
  final Map<String, String> headers;

  @override
  State<_QuickShareSheet> createState() => _QuickShareSheetState();
}

class _QuickShareSheetState extends State<_QuickShareSheet> {
  bool _linkBusy = false;

  String get _key => widget.source == 'url'
      ? widget.url
      : '${widget.source}:${widget.ref.values.join('|')}';

  String get _name => widget.subtitle.isEmpty
      ? widget.title
      : '${widget.title} — ${widget.subtitle}';

  Future<void> _fallbackCopy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم نسخ $what — الصقه في أي محادثة')));
    }
  }

  Future<void> _sendFile() async {
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);
    final bool opened = await DownloadManager.I.quickShareFile(
      source: widget.source,
      ref: widget.ref,
      url: widget.url,
      headers: widget.headers,
      title: widget.title,
      subtitle: widget.subtitle,
      poster: widget.poster,
    );
    nav.pop();
    if (!opened) {
      msg.showSnackBar(const SnackBar(
        content: Text('جارٍ التحميل — ستُفتح المشاركة تلقائيًا عند الانتهاء'),
        duration: Duration(seconds: 3),
      ));
    }
  }

  Future<void> _sendLink() async {
    setState(() => _linkBusy = true);
    String link = widget.url;
    try {
      if (link.isEmpty) {
        link = await DownloadManager.I.directLink(widget.source, widget.ref);
      }
    } catch (_) {
      link = '';
    }
    if (!mounted) return;
    setState(() => _linkBusy = false);
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر تجهيز الرابط — حاول مرة أخرى')));
      return;
    }
    final String text = '🎬 $_name\n'
        'رابط المشاهدة المباشر (يفتح في المتصفح أو VLC):\n$link';
    Navigator.of(context).pop();
    if (!await DownloadManager.I.shareText(text)) {
      await _fallbackCopy(text, 'الرابط');
    }
  }

  Future<void> _sendTitle() async {
    final String text = '🎬 $_name\nشاهده الآن على أنيماكس';
    Navigator.of(context).pop();
    if (!await DownloadManager.I.shareText(text)) {
      await _fallbackCopy(text, 'النص');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadManager.I,
      builder: (BuildContext c, _) {
        final DownloadItem? d =
            DownloadManager.I.find(key: _key, url: widget.url);
        final bool ready = d?.status == DownloadStatus.done;
        final bool active = d?.isActive ?? false;
        final String fileHint = ready
            ? 'الملف جاهز — يُرسل فورًا لواتساب أو تيليجرام'
            : active
                ? 'جارٍ التحميل ${(d!.progress * 100).round()}% — تُفتح المشاركة تلقائيًا'
                : 'يُحمَّل ثم تُفتح المشاركة تلقائيًا';
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                          width: 44, height: 64, child: NetImage(widget.poster)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('مشاركة سريعة',
                              style: TextStyle(
                                  fontFamily: kFont,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          Text(_name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: kFont,
                                  fontSize: 13.5,
                                  color: AppColors.sub)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Option(
                  icon: ready
                      ? Icons.send_rounded
                      : Icons.download_for_offline_rounded,
                  gradient: true,
                  title: ready ? 'إرسال ملف الفيديو' : 'تحميل وإرسال الفيديو',
                  hint: fileHint,
                  onTap: _sendFile,
                ),
                const SizedBox(height: 10),
                _Option(
                  icon: Icons.link_rounded,
                  title: 'مشاركة رابط مباشر',
                  hint: 'يشاهده صديقك فورًا في المتصفح بدون تطبيق',
                  busy: _linkBusy,
                  onTap: _linkBusy ? null : _sendLink,
                ),
                const SizedBox(height: 10),
                _Option(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'مشاركة الاسم',
                  hint: 'رسالة نصية بعنوان العمل',
                  onTap: _sendTitle,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.hint,
    this.onTap,
    this.gradient = false,
    this.busy = false,
  });
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback? onTap;
  final bool gradient;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHi,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: gradient ? AppColors.brandGrad : null,
                  color: gradient ? null : AppColors.surface,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: AppColors.brandGreen))
                    : Icon(icon,
                        color: gradient ? const Color(0xFF07130D) : Colors.white,
                        size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: const TextStyle(
                            fontFamily: kFont,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    Text(hint,
                        maxLines: 2,
                        style: const TextStyle(
                            fontFamily: kFont,
                            fontSize: 12.5,
                            color: AppColors.sub)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.sub),
            ],
          ),
        ),
      ),
    );
  }
}
