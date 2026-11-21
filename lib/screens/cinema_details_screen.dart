import 'package:flutter/material.dart';

import '../widgets/social_bar.dart';
import '../core/app_theme.dart';
import '../core/cinema_api.dart';
import '../core/library_store.dart';
import 'cinema_player_screen.dart';
import 'cinema_tab.dart' show CinemaColors;

/// Details for a Cinema title (Cinemeta meta): poster, backdrop, description,
/// cast, and for series a season switcher with the episode list. Movies play
/// immediately; episodes open the multi-server embed player (subtitles +
/// adaptive quality handled by the embed player itself).
class CinemaDetailsScreen extends StatefulWidget {
  const CinemaDetailsScreen({super.key, required this.item});

  final CinemaItem item;

  @override
  State<CinemaDetailsScreen> createState() => _CinemaDetailsScreenState();
}

class _CinemaDetailsScreenState extends State<CinemaDetailsScreen> {
  CinemaMeta? _meta;
  String? _error;
  int _season = 0;

  bool get _isSeries => widget.item.isSeries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final CinemaMeta meta = await CinemaApi.I
          .fetchMeta(widget.item.type, widget.item.id)
          .timeout(const Duration(seconds: 18));
      if (!mounted) return;
      setState(() {
        _meta = meta;
        if (meta.seasonNumbers.isNotEmpty) _season = meta.seasonNumbers.first;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذّر تحميل التفاصيل. تحقّق من اتصالك.');
    }
  }

  Future<void> _playMovie() async {
    final CinemaMeta? meta = _meta;
    if (meta == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Directionality(
          textDirection: TextDirection.ltr,
          child: CinemaPlayerScreen(meta: meta)),
    ));
  }

  Future<void> _playEpisode(CinemaEpisode ep) async {
    final CinemaMeta? meta = _meta;
    if (meta == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Directionality(
        textDirection: TextDirection.ltr,
        child: CinemaPlayerScreen(
          meta: meta,
          season: ep.season,
          episode: ep.number,
          episodeName: ep.name,
        ),
      ),
    ));
  }

  void _playTrailer(CinemaTrailer t) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CinemaPlayerScreen.direct(
        url: 'https://www.youtube.com/embed/${t.source}?autoplay=1&rel=0',
        title: '${_meta?.name ?? widget.item.name} — الإعلان',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final CinemaMeta? meta = _meta;
    final String name = meta?.name.isNotEmpty == true
        ? meta!.name
        : widget.item.name;
    final String poster = meta?.poster.isNotEmpty == true
        ? meta!.poster
        : widget.item.poster;
    final String background = meta?.background.isNotEmpty == true
        ? meta!.background
        : widget.item.background;
    final double rating = meta?.imdbRating != 0
        ? (meta?.imdbRating ?? widget.item.imdbRating)
        : widget.item.imdbRating;
    final List<String> genres =
        meta != null && meta.genres.isNotEmpty ? meta.genres : widget.item.genres;
    final String release = meta?.releaseInfo.isNotEmpty == true
        ? meta!.releaseInfo
        : widget.item.releaseInfo;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: CinemaColors.gold,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverAppBar(
              expandedHeight: 235,
              pinned: true,
              backgroundColor: AppColors.bg,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: <Widget>[
                _BookmarkButton(item: widget.item),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (background.isNotEmpty)
                      Image.network(background,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: AppColors.surfaceHi))
                    else if (poster.isNotEmpty)
                      Image.network(poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: AppColors.surfaceHi))
                    else
                      ColoredBox(color: AppColors.surfaceHi),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.transparent,
                            AppColors.bg,
                          ],
                          stops: <double>[0.45, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
              sliver: SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  Text(name,
                      style: AppText.h1.copyWith(height: 1.15)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _Chip(label: _isSeries ? 'مسلسل' : 'فيلم',
                          gold: !_isSeries),
                      if (rating > 0)
                        _Chip(label: 'IMDb ${rating.toStringAsFixed(1)}',
                            gold: true),
                      if (release.isNotEmpty) _Chip(label: release),
                      if (meta?.runtime.isNotEmpty == true)
                        _Chip(label: meta!.runtime),
                      if (meta?.status.isNotEmpty == true && _isSeries)
                        _Chip(label: meta!.status),
                    ],
                  ),
                  if (genres.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(genres.join(' · '),
                        style: AppText.label
                            .copyWith(fontSize: 12, color: AppColors.sub)),
                  ],
                  const SizedBox(height: 16),
                  // ----- Primary action -----
                  if (!_isSeries)
                    _PrimaryButton(
                      icon: Icons.play_arrow_rounded,
                      label: _meta == null ? 'جارٍ التحميل…' : 'تشغيل الفيلم',
                      onTap: _meta == null ? null : _playMovie,
                    )
                  else
                    _PrimaryButton(
                      icon: Icons.play_arrow_rounded,
                      label: _meta == null
                          ? 'جارٍ التحميل…'
                          : (_meta!.episodes.isEmpty
                              ? 'لا توجد حلقات'
                              : 'تشغيل الموسم $_season'),
                      onTap: _meta == null ||
                              _meta!.episodes.isEmpty
                          ? null
                          : () {
                              final List<CinemaEpisode> eps =
                                  _episodesFor(_season);
                              if (eps.isNotEmpty) _playEpisode(eps.first);
                            },
                    ),
                  // ----- Trailer row -----
                  if (meta != null && meta.trailers.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    for (final CinemaTrailer t in meta.trailers.take(2))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _playTrailer(t),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.text,
                              side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.22)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.movie_creation_outlined,
                                size: 18, color: AppColors.sub),
                            label: Text('شاهد الإعلان (يوتيوب)',
                                style: AppText.bodyBold.copyWith(fontSize: 13)),
                          ),
                        ),
                      ),
                  ],
                  SocialBar(
                      itemKey: 'cinema:${widget.item.id}',
                      title: meta?.name ?? widget.item.name),
                  const SizedBox(height: 18),
                  // ----- Description -----
                  if ((meta?.description ?? widget.item.description)
                      .isNotEmpty) ...<Widget>[
                    Text('القصة', style: AppText.h3),
                    const SizedBox(height: 8),
                    Text(meta?.description ?? widget.item.description,
                        style: AppText.body.copyWith(
                            fontSize: 13.5, height: 1.7, color: AppColors.sub)),
                    const SizedBox(height: 18),
                  ],
                  // ----- Cast -----
                  if (meta != null && meta.cast.isNotEmpty) ...<Widget>[
                    Text('طاقم التمثيل', style: AppText.h3),
                    const SizedBox(height: 8),
                    Text(meta.cast.take(6).join(', '),
                        style: AppText.label.copyWith(color: AppColors.sub)),
                    const SizedBox(height: 18),
                  ],
                  // ----- Seasons / episodes -----
                  if (_isSeries && meta != null && meta.episodes.isNotEmpty)
                    _EpisodeList(
                      meta: meta,
                      currentSeason: _season,
                      onSeason: (int s) => setState(() => _season = s),
                      onPlay: _playEpisode,
                    ),
                  // ----- Error -----
                  if (_error != null) ...<Widget>[
                    Text(_error!,
                        style: AppText.body
                            .copyWith(fontSize: 13, color: AppColors.danger)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded,
                          size: 18, color: AppColors.text),
                      label: const Text('إعادة المحاولة',
                          style: TextStyle(
                              fontFamily: 'Plex',
                              fontSize: 12.5,
                              color: AppColors.text)),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<CinemaEpisode> _episodesFor(int season) =>
      _meta?.episodes.where((CinemaEpisode e) => e.season == season).toList() ??
      const <CinemaEpisode>[];
}

// =============================================================================
// Season switcher + episode list
// =============================================================================

class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.meta,
    required this.currentSeason,
    required this.onSeason,
    required this.onPlay,
  });

  final CinemaMeta meta;
  final int currentSeason;
  final void Function(int) onSeason;
  final void Function(CinemaEpisode) onPlay;

  @override
  Widget build(BuildContext context) {
    final List<int> seasons = meta.seasonNumbers;
    final List<CinemaEpisode> eps = meta.episodes
        .where((CinemaEpisode e) => e.season == currentSeason)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('الحلقات', style: AppText.h3),
        const SizedBox(height: 10),
        if (seasons.length > 1)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (BuildContext _, int i) {
                final int s = seasons[i];
                final bool active = s == currentSeason;
                return ChoiceChip(
                  label: Text('الموسم $s'),
                  selected: active,
                  onSelected: (_) => onSeason(s),
                  labelStyle: TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.ink : AppColors.text),
                  selectedColor: AppColors.accent,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                      color:
                          active ? AppColors.accent : AppColors.stroke, width: 1),
                  showCheckmark: false,
                );
              },
            ),
          ),
        if (seasons.length > 1) const SizedBox(height: 8),
        for (final CinemaEpisode ep in eps)
          _EpisodeTile(
            ep: ep,
            onTap: () => onPlay(ep),
          ),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.ep, required this.onTap});

  final CinemaEpisode ep;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 118,
                height: 66,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (ep.thumbnail.isNotEmpty)
                      Image.network(ep.thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: AppColors.surfaceHi))
                    else
                      ColoredBox(color: AppColors.surfaceHi),
                    Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${ep.label} · ${ep.name.isEmpty ? 'حلقة' : ep.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyBold.copyWith(fontSize: 13)),
                  if (ep.overview.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(ep.overview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label
                            .copyWith(fontSize: 11, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Small building blocks
// =============================================================================

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.gold = false});

  final String label;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: gold ? CinemaColors.goldSoft : AppColors.surface,
        border: Border.all(
            color: gold ? CinemaColors.gold : AppColors.stroke, width: 1),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Plex',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: gold ? CinemaColors.gold : AppColors.sub)),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: AppColors.surfaceHi,
          disabledForegroundColor: AppColors.muted,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(icon, size: 22),
        label: Text(label, style: AppText.button.copyWith(fontSize: 14)),
      ),
    );
  }
}

/// Bookmark toggle in the cinema details app bar — saves the title to My
/// List (kind: cinema / cartoon) with the poster and year as meta.
class _BookmarkButton extends StatelessWidget {
  const _BookmarkButton({required this.item});

  final CinemaItem item;

  String get _key => 'cinema:${item.id}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LibraryStore.I,
      builder: (BuildContext context, _) {
        final bool listed = LibraryStore.I.isListed(_key);
        return IconButton(
          icon: Icon(
            listed ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
            color: listed ? AppColors.accent : Colors.white,
          ),
          tooltip: listed ? 'إزالة من قائمتي' : 'حفظ في قائمتي',
          onPressed: () {
            final LibraryStore lib = LibraryStore.I;
            if (listed) {
              lib.removeListEntry(_key);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('أُزيل ${item.name} من قائمتي')));
            } else {
              lib.setListStatus(
                key: _key,
                title: item.name,
                poster: item.poster,
                kind: 'cinema',
                status: LibStatus.watching,
                meta: '${item.releaseInfo.isEmpty ? 'Cinema' : item.releaseInfo}'
                    '${item.imdbRating > 0 ? ' · ★ ${item.imdbRating.toStringAsFixed(1)}' : ''}',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('حُفظ ${item.name} في قائمتي')));
            }
          },
        );
      },
    );
  }
}
