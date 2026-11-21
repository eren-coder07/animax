import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/mb_ui.dart';
import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/library_store.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/animax_logo.dart';

/// Home — hero carousel, Continue Watching, My List, Top Hits, New Episodes,
/// Popular This Season + a "Surprise me" shortcut.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final PageController _heroCtl = PageController();
  Timer? _heroTimer;
  int _heroPage = 0;

  @override
  void initState() {
    super.initState();
    _heroTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      final AppState state = AppState.I;
      final int count = state.catalog.take(5).length;
      if (count < 2 || !_heroCtl.hasClients) return;
      _heroPage = (_heroPage + 1) % count;
      _heroCtl.animateToPage(
        _heroPage,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroCtl.dispose();
    super.dispose();
  }

  void _openAnime(Anime anime) {
    if (anime.id.isEmpty) return;
    Navigator.pushNamed(context, '/details', arguments: anime);
  }

  void _surpriseMe() {
    final AppState state = AppState.I;
    if (state.catalog.isEmpty) return;
    final Anime pick =
        state.catalog[DateTime.now().microsecondsSinceEpoch % state.catalog.length];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('مفاجأة: ${pick.title}')));
    _openAnime(pick);
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[state, LibraryStore.I]),
        builder: (BuildContext context, _) {
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              const SizedBox(height: 16),
              if (!EmbeddedSection.of(context))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const AnimaxLogo(size: 34, withWordmark: true),
                    const SizedBox(width: 10),
                    _BackendChip(mode: state.backendChip),
                    const Spacer(),
                    IconBubble(Icons.shuffle_rounded,
                        onTap: _surpriseMe),
                    const SizedBox(width: 10),
                    IconBubble(Icons.search_rounded,
                        onTap: () => Navigator.pushNamed(context, '/search')),
                    const SizedBox(width: 10),
                    IconBubble(Icons.notifications_none_rounded,
                        badge: true,
                        onTap: () => Navigator.pushNamed(context, '/notifications')),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (state.catalog.isEmpty)
                _SyncBanner(state: state)
              else ...<Widget>[
                _HeroCarousel(state: state, controller: _heroCtl),
                const SizedBox(height: 24),
                _buildContinueWatching(),
                _buildMyList(),
                for (final (String title, List<Anime> list) in <(String, List<Anime>)>[
                  ('أنمي الأكثر مشاهدة', state.topHits),
                  ('حلقات جديدة', state.newEpisodes),
                  ('الأشهر هذا الموسم', state.catalog),
                ])
                  if (list.isNotEmpty)
                    PosterRow<Anime>(
                      title: title,
                      items: list,
                      onAll: () => Navigator.pushNamed(context, '/catalog',
                          arguments: (title, list)),
                      itemBuilder: (BuildContext c, Anime a, double w) =>
                          PosterTile(
                        title: a.title,
                        image: a.poster,
                        width: w,
                        rating: a.score,
                        badge: a.isMovie ? 'فيلم' : (a.episodeCount > 0 ? 'ح ${a.episodeCount}' : ''),
                        viewsKey: 'anime:${a.id}',
                        onTap: () => _openAnime(a),
                      ),
                    ),
              ],
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------- Continue Watching row

  Widget _buildContinueWatching() {
    final List<HistoryRow> rows = LibraryStore.I.history.take(10).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: <Widget>[
              Text('تابع المشاهدة', style: AppText.h2),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/library'),
                child: Text('المكتبة',
                    style: AppText.bodyBold.copyWith(
                        color: AppColors.accent, fontSize: 12.5)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (BuildContext c, int i) {
              final HistoryRow r = rows[i];
              final ProgressEntry p =
                  LibraryStore.I.progressForItem(r.key);
              final double frac = p.key == r.key ? p.fraction : 0;
              return GestureDetector(
                onTap: () {
                  if (r.kind == 'anime') {
                    Navigator.pushNamed(
                        context, '/details',
                        arguments: AppState.I.byId(
                            r.key.substring('anime:'.length)));
                  }
                },
                child: SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: r.poster.startsWith('http')
                                  ? Image.network(r.poster,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          ColoredBox(
                                              color: AppColors.surfaceHi))
                                  : ColoredBox(
                                      color: AppColors.surfaceHi),
                            ),
                            const Center(
                              child: Icon(Icons.play_arrow_rounded,
                                  color: Colors.white70, size: 40),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: ClipRRect(
                                borderRadius:
                                    const BorderRadius.vertical(
                                        bottom: Radius.circular(14)),
                                child: LinearProgressIndicator(
                                  value: frac > 0 ? frac : null,
                                  minHeight: 3,
                                  color: AppColors.accent,
                                  backgroundColor:
                                      Colors.white24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyBold.copyWith(
                              fontSize: 12, color: AppColors.text)),
                      Text(r.label,
                          style: AppText.label.copyWith(fontSize: 10.5)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }

  // ------------------------------------------------------- My List quick row

  Widget _buildMyList() {
    final List<LibEntry> entries = LibraryStore.I.allEntries
        .where((LibEntry e) => e.inList)
        .take(12)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: <Widget>[
              Text('قائمتي', style: AppText.h2),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/library'),
                child: Text('عرض الكل',
                    style: AppText.bodyBold.copyWith(
                        color: AppColors.accent, fontSize: 12.5)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 205,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (BuildContext c, int i) {
              final LibEntry e = entries[i];
              return SizedBox(
                width: 122,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: e.poster.startsWith('http')
                                ? Image.network(e.poster,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        ColoredBox(
                                            color: AppColors.surfaceHi))
                                : ColoredBox(
                                    color: AppColors.surfaceHi),
                          ),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(e.status?.label ?? '',
                                  style: TextStyle(
                                      fontFamily: 'Plex',
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.accent)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyBold.copyWith(
                            fontSize: 11.5, color: AppColors.text)),
                    Text(e.kind,
                        style: AppText.label.copyWith(fontSize: 9.5)),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

/// Auto-rotating hero banner — the top 5 catalog titles with backdrop art.
class _HeroCarousel extends StatelessWidget {
  const _HeroCarousel({required this.state, required this.controller});

  final AppState state;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    final List<Anime> picks = state.catalog.take(5).toList();
    if (picks.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 220,
      child: PageView.builder(
        controller: controller,
        itemCount: picks.length,
        onPageChanged: (_) {},
        itemBuilder: (BuildContext c, int i) {
          final Anime a = picks[i];
          return GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/details',
                arguments: a),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        a.isNetworkPoster
                            ? Image.network(a.poster,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => ColoredBox(
                                    color: AppColors.surfaceHi))
                            : ColoredBox(
                                color: AppColors.surfaceHi),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const <double>[0.35, 1.0],
                              colors: <Color>[
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  if (a.score > 0) ...<Widget>[
                                    const Icon(Icons.star_rounded,
                                        size: 14, color: Color(0xFFFFC94D)),
                                    const SizedBox(width: 3),
                                    Text(a.score.toStringAsFixed(1),
                                        style: const TextStyle(
                                            fontFamily: 'Plex',
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(a.year,
                                      style: const TextStyle(
                                          fontFamily: 'Plex',
                                          fontSize: 11,
                                          color: Colors.white70)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(a.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'Plex',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              const SizedBox(height: 2),
                              Text(
                                a.genres.take(3).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: 'Plex',
                                    fontSize: 11,
                                    color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
            color: offline ? Colors.redAccent : AppColors.accent,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            offline ? 'المحتوى غير متاح' : 'جارٍ التحديث…',
            style: AppText.bodyBold.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            offline
                ? 'تعذّر الوصول إلى مكتبة المحتوى. تحقّق من اتصالك وأعد المحاولة.'
                : state.backendMessage,
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(fontSize: 11),
          ),
          if (offline) ...<Widget>[
            const SizedBox(height: 14),
            GhostChip(
              label: 'إعادة المزامنة',
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

/// Small status chip next to the logo (LIVE / SYNC… / OFFLINE).
class _BackendChip extends StatelessWidget {
  const _BackendChip({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context) {
    final bool live = mode == 'مباشر';
    final bool syncing = mode == 'مزامنة…';
    final bool bad = mode == 'غير متصل';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: live
            ? AppColors.accent.withValues(alpha: 0.15)
            : bad
                ? Colors.red.withValues(alpha: 0.14)
                : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: live
                ? AppColors.accent.withValues(alpha: 0.5)
                : bad
                    ? Colors.red.withValues(alpha: 0.4)
                    : AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (syncing)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: AppColors.accent),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: live
                    ? AppColors.accent
                    : bad
                        ? Colors.redAccent
                        : AppColors.muted,
              ),
            ),
          const SizedBox(width: 5),
          Text(mode,
              style: TextStyle(
                  fontFamily: 'Plex',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: bad ? Colors.redAccent : AppColors.sub)),
        ],
      ),
    );
  }
}
