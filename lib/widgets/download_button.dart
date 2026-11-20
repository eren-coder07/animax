import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/download_manager.dart';

/// Download action used by the players and the comic screens.
///
/// Reflects the live state of the matching download: idle → download
/// icon, running → progress ring, done → check (tap opens Downloads),
/// paused/failed → retry.
class DownloadIconButton extends StatelessWidget {
  const DownloadIconButton({
    super.key,
    this.url = '',
    this.chapterId = '',
    required this.onStart,
    this.color = Colors.white,
    this.size = 22,
    this.enabled = true,
  });

  /// Identity of the download (video source URL or comic chapter id).
  final String url;
  final String chapterId;

  /// Queues the download (called when nothing matching exists yet).
  final Future<void> Function() onStart;
  final Color color;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadManager.I,
      builder: (BuildContext context, _) {
        final DownloadItem? d = (url.isEmpty && chapterId.isEmpty)
            ? null
            : DownloadManager.I.find(url: url, chapterId: chapterId);
        Widget icon;
        String tip;
        VoidCallback? tap;
        if (d == null) {
          icon = Icon(Icons.download_rounded,
              color: enabled ? color : color.withValues(alpha: 0.35),
              size: size);
          tip = 'Download';
          tap = enabled
              ? () async {
                  await onStart();
                  if (context.mounted) showDownloadQueuedSnack(context);
                }
              : null;
        } else if (d.status == DownloadStatus.done) {
          icon = Icon(Icons.download_done_rounded,
              color: AppColors.accent, size: size);
          tip = 'Downloaded';
          tap = () => Navigator.of(context).pushNamed('/downloads');
        } else if (d.isActive) {
          icon = SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                CircularProgressIndicator(
                  value: d.status == DownloadStatus.running && d.progress > 0
                      ? d.progress
                      : null,
                  strokeWidth: 2.4,
                  color: AppColors.accent,
                  backgroundColor: color.withValues(alpha: 0.2),
                ),
                Icon(Icons.arrow_downward_rounded,
                    color: color, size: size * 0.55),
              ],
            ),
          );
          tip = 'Downloading ${(d.progress * 100).round()}%';
          tap = () => Navigator.of(context).pushNamed('/downloads');
        } else {
          icon = Icon(Icons.download_rounded, color: AppColors.amber, size: size);
          tip = d.status == DownloadStatus.failed
              ? 'Download failed — tap to retry'
              : 'Paused — tap to resume';
          tap = () {
            DownloadManager.I.resume(d);
            showDownloadQueuedSnack(context);
          };
        }
        return IconButton(tooltip: tip, onPressed: tap, icon: icon);
      },
    );
  }
}

void showDownloadQueuedSnack(BuildContext context) {
  final ScaffoldMessengerState? m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: const Text('Downloading — saved to Download/Animax when done'),
    behavior: SnackBarBehavior.floating,
    action: SnackBarAction(
      label: 'View',
      onPressed: () => Navigator.of(context).pushNamed('/downloads'),
    ),
  ));
}
