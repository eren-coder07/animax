import 'package:flutter/material.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(title, style: AppText.h2),
        ),
        SizedBox(
          height: 216,
          child: FutureBuilder<List<MangaItem>>(
            future: future,
            builder: (BuildContext context,
                AsyncSnapshot<List<MangaItem>> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Center(
                    child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: AppColors.accent)));
              }
              if (snap.hasError || (snap.data?.isEmpty ?? true)) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    snap.hasError
                        ? 'تعذّر التحميل — تحقّق من اتصالك.'
                        : 'لا شيء هنا حاليًا.',
                    style: AppText.label,
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: snap.data!.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (BuildContext c, int i) =>
                    MangaCard(manga: snap.data![i]),
              );
            },
          ),
        ),
      ],
    );
  }

}
