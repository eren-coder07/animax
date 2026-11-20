import 'package:flutter/material.dart';

import '../core/app_data.dart';
import '../core/app_theme.dart';
import 'buttons.dart';

/// Poster tile with optional score badge + play overlay + Hero animation.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.anime,
    this.width = 130,
    this.height = 186,
    this.showPlay = false,
    this.showScore = true,
    this.subtitle,
    this.onTap,
  });

  final Anime anime;
  final double width;
  final double height;
  final bool showPlay;
  final bool showScore;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.pushNamed(context, '/details', arguments: anime),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Hero(
                tag: 'poster-${anime.id}',
                child: PosterImage(
                  anime: anime,
                  radius: 14,
                  child: Stack(
                    children: [
                      if (showScore)
                        Positioned(top: 8, left: 8, child: ScoreBadge(score: anime.score, small: true)),
                      if (showPlay)
                        Center(
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              anime.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodyBold.copyWith(fontSize: 12.5, color: AppColors.text),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(fontSize: 10.5),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rounded image with graceful fallback if the asset is missing.
/// Supports both bundled asset posters and remote http(s) posters.
class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.anime,
    this.radius = 14,
    this.child,
  });

  final Anime anime;
  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final Widget image = anime.isNetworkPoster
        ? Image.network(
            anime.poster,
            fit: BoxFit.cover,
            loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? progress) =>
                progress == null
                    ? child
                    : ColoredBox(color: AppColors.surface, child: child),
            errorBuilder: (_, _, _) => _Fallback(letter: anime.title.isNotEmpty ? anime.title[0] : '?'),
          )
        : Image.asset(
            anime.poster,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _Fallback(letter: anime.title.isNotEmpty ? anime.title[0] : '?'),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            ?child,
          ],
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [AppColors.surfaceHi, AppColors.accentDeep],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
            fontFamily: 'Cairo', fontSize: 42, fontWeight: FontWeight.w800, color: AppColors.accent),
      ),
    );
  }
}

/// Section title row — bold heading + green "See all".
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppText.h2)),
          GestureDetector(
            onTap: onSeeAll,
            child: Text('عرض الكل',
                style: AppText.bodyBold.copyWith(color: AppColors.accent, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
