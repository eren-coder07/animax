import 'package:flutter/material.dart';

import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/animax_logo.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return SafeArea(
      child: ListenableBuilder(
        listenable: state,
        builder: (BuildContext context, _) {
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const AnimaxLogo(size: 34, withWordmark: true),
                    const SizedBox(width: 10),
                    _BackendChip(mode: state.backendChip),
                    const Spacer(),
                    IconBubble(Icons.search_rounded,
                        onTap: () => Navigator.pushNamed(context, '/search')),
                    const SizedBox(width: 10),
                    IconBubble(Icons.notifications_none_rounded,
                        badge: true,
                        onTap: () => Navigator.pushNamed(context, '/notifications')),
                  ],
                ),
              ),
          const SizedBox(height: 26),
          if (state.catalog.isEmpty)
            _SyncBanner(state: state)
          else ...<Widget>[
          SectionHeader(
            title: 'Top Hits Anime',
            onSeeAll: () => Navigator.pushNamed(context, '/catalog',
                arguments: ('Top Hits Anime', state.topHits)),
          ),
          SizedBox(
            height: 306,
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: state.topHits.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (BuildContext context, int i) {
                final Anime anime = state.topHits[i];
                return GestureDetector(
                  onTap: () =>
                      Navigator.pushNamed(context, '/details', arguments: anime),
                  child: SizedBox(
                    width: 236,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Hero(
                            tag: 'poster-${anime.id}',
                            child: PosterImage(
                              anime: anime,
                              radius: 18,
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 10,
                                    left: 10,
                                    child: ScoreBadge(score: anime.score),
                                  ),
                                  Positioned(
                                    bottom: -14,
                                    left: 14,
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 84,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        height: 1.0,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withValues(alpha: 0.55),
                                            blurRadius: 18,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          anime.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyBold.copyWith(fontSize: 13.5),
                        ),
                        Text(anime.genres.take(3).join('. '),
                            style: AppText.label, maxLines: 1),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 26),
          SectionHeader(
            title: 'New Episode Releases',
            onSeeAll: () => Navigator.pushNamed(context, '/catalog',
                arguments: ('New Episode Releases', state.newEpisodes)),
          ),
          SizedBox(
            height: 250,
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: state.newEpisodes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (BuildContext context, int i) {
                final Anime anime = state.newEpisodes[i];
                return PosterCard(
                  anime: anime,
                  width: 136,
                  subtitle:
                      anime.isMovie ? 'Movie • ${anime.duration}' : 'Episode ${anime.episodeCount}',
                );
              },
            ),
          ),
          const SizedBox(height: 26),
          SectionHeader(
            title: 'Popular This Season',
            onSeeAll: () => Navigator.pushNamed(context, '/catalog',
                arguments: ('Popular This Season', state.catalog)),
          ),
          SizedBox(
            height: 250,
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: state.catalog.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (BuildContext context, int i) {
                final Anime anime =
                    state.catalog[(i * 5 + 3) % state.catalog.length];
                return PosterCard(anime: anime, width: 136, showPlay: true);
              },
            ),
          ),
          ],
            ],
          );
        },
      ),
    );
  }
}

/// Shown when the catalog is empty (sync failed or still loading) —
/// the home screen carries no bundled sample content.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final bool offline = state.backendMode == BackendMode.offline;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: offline
                ? Colors.redAccent.withValues(alpha: 0.4)
                : AppColors.stroke),
      ),
      child: Column(
        children: [
          Icon(
            offline ? Icons.wifi_off_rounded : Icons.sync_rounded,
            color: offline ? Colors.redAccent : AppColors.green,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            offline ? 'Couldn\'t sync with the API' : 'Syncing…',
            style: AppText.bodyBold.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            offline
                ? (state.syncError ??
                    'The backend could not be reached. Check your connection and retry.')
                : state.backendMessage,
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(fontSize: 11),
          ),
          if (offline) ...<Widget>[
            const SizedBox(height: 14),
            GhostChip(
              label: 'Retry sync',
              active: true,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              onTap: () => state.refreshFromApi(withSchedule: true),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small status chip next to the logo — tap to open Backend settings.
class _BackendChip extends StatelessWidget {
  const _BackendChip({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context) {
    final bool live = mode == 'LIVE';
    final bool syncing = mode == 'SYNC…';
    final bool bad = mode == 'OFFLINE';
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/backend'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: live
              ? AppColors.green.withValues(alpha: 0.15)
              : bad
                  ? Colors.red.withValues(alpha: 0.14)
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: live
                  ? AppColors.green.withValues(alpha: 0.5)
                  : bad
                      ? Colors.red.withValues(alpha: 0.4)
                      : AppColors.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (syncing)
              const SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                    strokeWidth: 1.6, color: AppColors.green),
              )
            else
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: live
                      ? AppColors.green
                      : bad
                          ? Colors.redAccent
                          : AppColors.muted,
                ),
              ),
            const SizedBox(width: 5),
            Text(mode,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: bad ? Colors.redAccent : AppColors.sub)),
          ],
        ),
      ),
    );
  }
}
