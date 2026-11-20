import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/download_manager.dart';

/// All downloads: progress, pause/resume, open, delete.
/// Finished files live in the public `Download/Animax/…` folder.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Downloads',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      body: ListenableBuilder(
        listenable: DownloadManager.I,
        builder: (BuildContext context, _) {
          final List<DownloadItem> items = DownloadManager.I.items;
          if (items.isEmpty) return const _Empty();
          final List<DownloadItem> active =
              items.where((DownloadItem d) => d.status != DownloadStatus.done).toList();
          final List<DownloadItem> done =
              items.where((DownloadItem d) => d.status == DownloadStatus.done).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: <Widget>[
              if (active.isNotEmpty) ...<Widget>[
                const _Header('In progress'),
                for (final DownloadItem d in active) _DownloadTile(item: d),
              ],
              if (done.isNotEmpty) ...<Widget>[
                const _Header('Saved on this device'),
                for (final DownloadItem d in done) _DownloadTile(item: d),
              ],
              const SizedBox(height: 10),
              const Text(
                'Files are saved to Download/Animax on your phone and open '
                'in any video player or PDF reader. Keep the app open while '
                'large videos download.',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    height: 1.5,
                    color: AppColors.muted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 8),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.sub)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.download_rounded,
                  color: AppColors.accent, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('No downloads yet',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text)),
            const SizedBox(height: 6),
            const Text(
              'Tap the download button in any player or on a comic '
              'chapter to save it for offline viewing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.sub),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.item});
  final DownloadItem item;

  static String _size(int bytes) {
    if (bytes <= 0) return '';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    double v = bytes.toDouble();
    int u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(v >= 100 || u == 0 ? 0 : 1)} ${units[u]}';
  }

  String get _statusText {
    final String size = _size(item.received);
    switch (item.status) {
      case DownloadStatus.queued:
        return 'Waiting…';
      case DownloadStatus.running:
        final String pct = item.progress > 0
            ? '${(item.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
            : 'Starting…';
        final String total = item.total > 0 ? ' of ${_size(item.total)}' : '';
        return size.isEmpty ? pct : '$pct · $size$total';
      case DownloadStatus.paused:
        return 'Paused${size.isEmpty ? '' : ' · $size'}';
      case DownloadStatus.failed:
        return item.error.isEmpty ? 'Failed' : item.error;
      case DownloadStatus.done:
        return item.resultLocation.isEmpty
            ? 'Saved'
            : 'Saved · ${item.resultLocation}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isComic = item.kind == DownloadKind.comic;
    final Color tint = isComic ? const Color(0xFF3DD6A0) : AppColors.accent;
    final bool failed = item.status == DownloadStatus.failed;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.status == DownloadStatus.done
            ? () => _open(context)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 54,
                  height: 72,
                  child: item.poster.isNotEmpty
                      ? Image.network(item.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _thumb(isComic, tint))
                      : _thumb(isComic, tint),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text)),
                    if (item.subtitle.isNotEmpty)
                      Text(item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.5,
                              color: AppColors.sub)),
                    const SizedBox(height: 6),
                    if (item.status != DownloadStatus.done)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            value: item.status == DownloadStatus.running &&
                                    item.progress <= 0
                                ? null
                                : item.progress.clamp(0, 1),
                            color: failed ? AppColors.danger : tint,
                            backgroundColor: AppColors.stroke,
                          ),
                        ),
                      ),
                    Text(_statusText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10.5,
                            color: failed ? AppColors.danger : AppColors.muted)),
                  ],
                ),
              ),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(bool isComic, Color tint) => Container(
        color: tint.withValues(alpha: 0.14),
        child: Icon(
            isComic ? Icons.picture_as_pdf_rounded : Icons.movie_rounded,
            color: tint),
      );

  Widget _actions(BuildContext context) {
    final DownloadManager m = DownloadManager.I;
    switch (item.status) {
      case DownloadStatus.queued:
      case DownloadStatus.running:
        return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          IconButton(
            tooltip: 'Pause',
            icon: const Icon(Icons.pause_rounded, color: AppColors.text),
            onPressed: () => m.pause(item),
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close_rounded, color: AppColors.muted),
            onPressed: () => m.remove(item),
          ),
        ]);
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          IconButton(
            tooltip: item.status == DownloadStatus.failed ? 'Retry' : 'Resume',
            icon: Icon(
                item.status == DownloadStatus.failed
                    ? Icons.refresh_rounded
                    : Icons.play_arrow_rounded,
                color: AppColors.text),
            onPressed: () => m.resume(item),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded, color: AppColors.muted),
            onPressed: () => m.remove(item),
          ),
        ]);
      case DownloadStatus.done:
        return PopupMenuButton<String>(
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
            PopupMenuItem<String>(value: 'open', child: Text('Open')),
            PopupMenuItem<String>(
                value: 'forget', child: Text('Remove from list')),
            PopupMenuItem<String>(
                value: 'delete', child: Text('Delete file')),
          ],
        );
    }
  }

  Future<void> _open(BuildContext context) async {
    final bool ok = await DownloadManager.I.open(item);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(item.resultLocation.isEmpty
            ? 'No app found to open this file.'
            : 'Saved at ${item.resultLocation}'),
      ));
    }
  }
}
