import 'package:flutter/material.dart';

import '../core/akwam_api.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../widgets/mb_ui.dart';
import 'akwam_tab.dart';

/// Downloads: in-progress list with progress + status, finished files with
/// filter chips, free-space readout, empty state and suggestions.
/// Finished files live in the public `Download/Animax/…` folder.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, this.asTab = false});

  /// Shown as a bottom-bar tab (no back button).
  final bool asTab;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

enum _Filter { all, video, comic }

class _DownloadsScreenState extends State<DownloadsScreen> {
  _Filter _filter = _Filter.all;
  bool _manage = false;
  int _free = -1;
  Future<List<AkwamItem>>? _suggest;

  @override
  void initState() {
    super.initState();
    DownloadManager.I.freeSpace().then((int b) {
      if (mounted) setState(() => _free = b);
    });
    _suggest = AkwamApi.I.recent().catchError((Object _) => <AkwamItem>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: DownloadManager.I,
          builder: (BuildContext context, _) {
            final List<DownloadItem> all = DownloadManager.I.items;
            final List<DownloadItem> active = all
                .where((DownloadItem d) => d.status != DownloadStatus.done)
                .toList();
            final List<DownloadItem> done = all
                .where((DownloadItem d) =>
                    d.status == DownloadStatus.done &&
                    (_filter == _Filter.all ||
                        (_filter == _Filter.video &&
                            d.kind == DownloadKind.video) ||
                        (_filter == _Filter.comic &&
                            d.kind == DownloadKind.comic)))
                .toList();
            return ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: <Widget>[
                _header(context, all),
                Divider(height: 1, color: AppColors.stroke),
                if (active.isNotEmpty) ...<Widget>[
                  _sectionTitle('جارٍ التحميل (${active.length})',
                      trailing: GestureDetector(
                        onTap: () => setState(() => _manage = !_manage),
                        child: Text(_manage ? 'تم' : 'إدارة',
                            style: const TextStyle(
                                fontFamily: kFont,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brandGreen)),
                      )),
                  for (final DownloadItem d in active)
                    _ActiveRow(item: d, manage: _manage),
                ],
                _sectionTitle('تم التحميل',
                    trailing: _free > 0
                        ? Text('${_size(_free)} متاح',
                            style: const TextStyle(
                                fontFamily: kFont,
                                fontSize: 14,
                                color: AppColors.sub))
                        : null),
                _chips(),
                if (done.isEmpty)
                  _empty(context)
                else
                  for (final DownloadItem d in done) _DoneRow(item: d),
                _suggestions(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, List<DownloadItem> all) {
    final bool anyDone =
        all.any((DownloadItem d) => d.status == DownloadStatus.done);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      child: Row(
        children: <Widget>[
          if (!widget.asTab)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          const Expanded(
            child: Text('التحميلات',
                style: TextStyle(
                    fontFamily: kFont,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          if (anyDone)
            Material(
              color: AppColors.surfaceHi,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () async {
                  for (final DownloadItem d in all
                      .where((DownloadItem d) => d.status == DownloadStatus.done)
                      .toList()) {
                    await DownloadManager.I.remove(d);
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.cleaning_services_rounded,
                          size: 18, color: AppColors.brandGreen),
                      SizedBox(width: 6),
                      Text('مسح القائمة',
                          style: TextStyle(
                              fontFamily: kFont,
                              fontSize: 14,
                              color: AppColors.brandGreen)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 22, 14, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(t,
                  style: const TextStyle(
                      fontFamily: kFont,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
            ?trailing,
          ],
        ),
      );

  Widget _chips() {
    Widget chip(String label, _Filter f) {
      final bool on = _filter == f;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 10),
        child: GestureDetector(
          onTap: () => setState(() => _filter = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: on ? Colors.white : AppColors.surfaceHi,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(label,
                style: TextStyle(
                    fontFamily: kFont,
                    fontSize: 15,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                    color: on ? Colors.black : const Color(0xFFD5D6DA))),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: <Widget>[
        chip('الكل', _Filter.all),
        chip('فيديو', _Filter.video),
        chip('مانغا PDF', _Filter.comic),
      ]),
    );
  }

  Widget _empty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 10),
      child: Column(
        children: <Widget>[
          Container(
            width: 96,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.inventory_2_outlined,
                size: 44, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          const Text('ستظهر تحميلاتك هنا',
              style: TextStyle(
                  fontFamily: kFont, fontSize: 15.5, color: AppColors.sub)),
          const SizedBox(height: 16),
          Material(
            color: AppColors.surfaceHi,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => AppState.I.setCategory(0),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                child: Text('اكتشف أفلامًا ومسلسلات للتحميل',
                    style: TextStyle(
                        fontFamily: kFont, fontSize: 15, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestions() {
    return FutureBuilder<List<AkwamItem>>(
      future: _suggest,
      builder: (BuildContext c, AsyncSnapshot<List<AkwamItem>> snap) {
        final List<AkwamItem> items =
            (snap.data ?? const <AkwamItem>[]).take(9).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _sectionTitle('مقترح لك'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 8,
                childAspectRatio: 0.56,
                children: <Widget>[
                  for (final AkwamItem it in items) AkwamCard(item: it),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
              child: Material(
                color: AppColors.surfaceHi,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    _suggest = AkwamApi.I
                        .recent(page: 2)
                        .catchError((Object _) => <AkwamItem>[]);
                  }),
                  child: const SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.refresh_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text('تحديث المقترحات',
                            style: TextStyle(
                                fontFamily: kFont,
                                fontSize: 15.5,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _size(int bytes) {
  if (bytes <= 0) return '';
  const List<String> units = <String>['بايت', 'ك.ب', 'م.ب', 'ج.ب'];
  double v = bytes.toDouble();
  int u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(v >= 100 || u == 0 ? 0 : 1)} ${units[u]}';
}

/// Keeps a file path in reading order inside Arabic (RTL) text by wrapping
/// it in Unicode left-to-right isolate marks.
String _ltr(String s) => '\u2066$s\u2069';

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, this.showPlay = true});
  final DownloadItem item;
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    final bool comic = item.kind == DownloadKind.comic;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 150,
        height: 86,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (item.poster.isNotEmpty)
              NetImage(item.poster)
            else
              ColoredBox(
                color: AppColors.surfaceHi,
                child: Icon(
                    comic ? Icons.picture_as_pdf_rounded : Icons.movie_rounded,
                    color: AppColors.muted,
                    size: 30),
              ),
            if (showPlay)
              Center(
                child: Icon(
                    comic ? Icons.menu_book_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                    shadows: const <Shadow>[
                      Shadow(color: Colors.black54, blurRadius: 8)
                    ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveRow extends StatelessWidget {
  const _ActiveRow({required this.item, required this.manage});
  final DownloadItem item;
  final bool manage;

  @override
  Widget build(BuildContext context) {
    final DownloadManager m = DownloadManager.I;
    final bool running = item.status == DownloadStatus.running;
    final bool failed = item.status == DownloadStatus.failed;
    final bool paused = item.status == DownloadStatus.paused;
    String status;
    Color statusColor = AppColors.sub;
    switch (item.status) {
      case DownloadStatus.queued:
        status = 'في الانتظار';
      case DownloadStatus.running:
        status = item.progress > 0
            ? '${(item.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
            : 'جارٍ البدء…';
        statusColor = AppColors.brandGreen;
      case DownloadStatus.paused:
        status = 'متوقف';
        statusColor = AppColors.badge;
      case DownloadStatus.failed:
        status = 'فشل';
        statusColor = AppColors.badge;
      case DownloadStatus.done:
        status = '';
    }
    final String sizes = item.total > 0
        ? '${_size(item.received)} / ${_size(item.total)}'
        : (item.received > 0 ? _size(item.received) : '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Thumb(item: item, showPlay: false),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 86,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                      item.subtitle.isEmpty
                          ? item.title
                          : '${item.subtitle} ${item.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: kFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const Spacer(),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: running && item.progress <= 0
                          ? null
                          : item.progress.clamp(0, 1),
                      color: AppColors.brandGreen,
                      backgroundColor: AppColors.surfaceHi,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                            failed && item.error.isNotEmpty ? item.error : sizes,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: kFont,
                                fontSize: 13,
                                color: failed ? AppColors.badge : AppColors.sub)),
                      ),
                      Text(status,
                          style: TextStyle(
                              fontFamily: kFont,
                              fontSize: 13.5,
                              color: statusColor)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 86,
            child: Center(
              child: manage
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.badge),
                      onPressed: () => m.remove(item),
                    )
                  : GestureDetector(
                      onTap: () => (paused || failed) ? m.resume(item) : m.pause(item),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                            gradient: AppColors.brandGrad,
                            shape: BoxShape.circle),
                        child: Icon(
                            (paused || failed)
                                ? Icons.arrow_downward_rounded
                                : Icons.pause_rounded,
                            size: 20,
                            color: const Color(0xFF07130D)),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.item});
  final DownloadItem item;

  Future<void> _open(BuildContext context) async {
    final bool ok = await DownloadManager.I.open(item);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(item.resultLocation.isEmpty
            ? 'لا يوجد تطبيق لفتح هذا الملف.'
            : 'محفوظ في ${_ltr(item.resultLocation)}'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DownloadManager m = DownloadManager.I;
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Row(
          children: <Widget>[
            _Thumb(item: item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: kFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  if (item.subtitle.isNotEmpty)
                    Text(item.subtitle,
                        maxLines: 1,
                        style: const TextStyle(
                            fontFamily: kFont,
                            fontSize: 13.5,
                            color: AppColors.sub)),
                  const SizedBox(height: 4),
                  Text(
                      item.received > 0
                          ? _size(item.received)
                          : (item.kind == DownloadKind.comic ? 'PDF' : 'MP4'),
                      style: const TextStyle(
                          fontFamily: kFont,
                          fontSize: 12.5,
                          color: AppColors.muted)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.sub),
              color: AppColors.surfaceHi,
              onSelected: (String v) async {
                if (v == 'open') {
                  await _open(context);
                } else if (v == 'forget') {
                  await m.remove(item);
                } else if (v == 'delete') {
                  await m.remove(item, deleteFile: true);
                }
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'open', child: Text('فتح')),
                PopupMenuItem<String>(
                    value: 'forget', child: Text('إزالة من القائمة')),
                PopupMenuItem<String>(
                    value: 'delete', child: Text('حذف الملف')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
