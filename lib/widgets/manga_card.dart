import 'package:flutter/material.dart';

import 'mb_ui.dart';
import '../core/app_theme.dart';
import '../core/manga_api.dart';

/// Portrait poster card for manga titles (2:3 cover ratio).
class MangaCard extends StatelessWidget {
  const MangaCard({super.key, required this.manga, this.onTap, this.width = 124});

  final MangaItem manga;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ??
          () => Navigator.pushNamed(context, '/comic-details',
              arguments: manga),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Image.network(
                        manga.cover,
                        fit: BoxFit.cover,
                        loadingBuilder: (BuildContext context, Widget child,
                                ImageChunkEvent? progress) =>
                            progress == null
                                ? child
                                : ColoredBox(
                                    color: AppColors.surface,
                                    child: child),
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.surface,
                          alignment: Alignment.center,
                          child: Text(
                            manga.title.isNotEmpty ? manga.title[0] : '?',
                            style: TextStyle(
                                fontFamily: 'Plex',
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: AppColors.accent),
                          ),
                        ),
                      ),
                      if (manga.followedCount > 0)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.favorite_rounded,
                                    size: 10, color: AppColors.accent),
                                const SizedBox(width: 3),
                                Text(manga.followedLabel,
                                    style: const TextStyle(
                                        fontFamily: 'Plex',
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              manga.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodyBold.copyWith(
                  fontSize: 12, color: AppColors.text),
            ),
            Text(
              manga.tags.isEmpty
                  ? (manga.year.isEmpty ? 'مانغا' : manga.year)
                  : manga.tags.take(2).map((MangaTag t) => t.name).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal catalog row with header (mirrors cinema rows but for manga).
class MangaRow extends StatelessWidget {
  const MangaRow({
    super.key,
    required this.title,
    required this.future,
  });

  final String title;
  final Future<List<MangaItem>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MangaItem>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<MangaItem>> snap) {
        final bool loading = snap.connectionState != ConnectionState.done;
        final List<MangaItem> list = snap.data ?? const <MangaItem>[];
        if (!loading && list.isEmpty) return const SizedBox.shrink();
        return PosterRow<MangaItem>(
          title: title,
          items: list,
          loading: loading,
          itemBuilder: (BuildContext c, MangaItem m, double w) => PosterTile(
            title: m.title,
            image: m.cover,
            width: w,
            viewsKey: 'manga:${m.id}',
            onTap: () =>
                Navigator.pushNamed(c, '/comic-details', arguments: m),
          ),
        );
      },
    );
  }
}
