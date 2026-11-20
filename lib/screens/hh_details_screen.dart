import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../core/hh_api.dart';
import '../widgets/common.dart' show IconBubble;
import '../widgets/download_button.dart';
import 'hentai_tab.dart';

/// Hentai series details: hero poster, rating / views / genres, synopsis and
/// the episode list parsed from the series page. Metadata is enriched from
/// the REST API when the card came from a page scrape.
class HhDetailsScreen extends StatefulWidget {
  const HhDetailsScreen({super.key});

  @override
  State<HhDetailsScreen> createState() => _HhDetailsScreenState();
}

class _HhDetailsScreenState extends State<HhDetailsScreen> {
  late HhSeries _series;
  List<HhEpisode>? _episodes;
  String? _episodesError;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _series = const HhSeries(id: 0, slug: '', title: '', thumb: '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Object? args = ModalRoute.of(context)!.settings.arguments;
    if (args is HhSeries && args.slug != _series.slug) {
      _series = args;
      _episodes = null;
      _episodesError = null;
      _expanded = false;
      _load();
    }
  }

  Future<void> _load() async {
    // Enrich metadata (synopsis / genres) when the card lacks it.
    if (_series.synopsis.isEmpty || _series.thumb.isEmpty) {
      HentaiApi.I.seriesBySlug(_series.slug).then((HhSeries rich) {
        if (!mounted || _series.slug != rich.slug) return;
        setState(() => _series = HhSeries(
              id: rich.id,
              slug: rich.slug,
              title: rich.title,
              thumb: rich.thumb.isNotEmpty ? rich.thumb : _series.thumb,
              synopsis: rich.synopsis,
              genres: rich.genres,
              rating: _series.rating > 0 ? _series.rating : rich.rating,
              views: _series.views > 0 ? _series.views : rich.views,
              date: rich.date,
            ));
      }).catchError((_) {});
    }
    try {
      final List<HhEpisode> eps = await HentaiApi.I.episodes(_series.slug);
      if (!mounted) return;
      setState(() => _episodes = eps);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _episodesError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _episodesError = 'تعذّر تحميل الحلقات.');
    }
  }

  String _dlKey(int ep) => 'hh:${_series.slug}|$ep';

  Future<void> _download(int ep) => DownloadManager.I.addResolvable(
        source: 'hh',
        ref: <String, String>{'slug': _series.slug, 'ep': '$ep'},
        title: _series.title,
        subtitle: 'الحلقة $ep',
        poster: _series.thumb,
      );

  void _play(int episodeNumber) {
    Navigator.pushNamed(
      context,
      '/hh-player',
      arguments: (
        series: _series,
        episode: episodeNumber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> genres = _series.genres;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: <Widget>[
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 48),
            children: <Widget>[
              // ---------- Hero ----------
              SizedBox(
                height: 400,
                width: double.infinity,
                child: Hero(
                  tag: 'hh-${_series.slug}',
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (_series.thumb.isNotEmpty)
                        Image.network(_series.thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: AppColors.surfaceHi))
                      else
                        ColoredBox(color: AppColors.surfaceHi),
                      const DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: AppColors.heroFade)),
                      SafeArea(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: <Widget>[
                              IconBubble(Icons.arrow_back_rounded,
                                  onTap: () => Navigator.pop(context)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ---------- Header ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: HhColors.redSoft,
                            border: Border.all(color: HhColors.red,
                                width: 1.2),
                          ),
                          child: Text('هنتاي +18',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: HhColors.red)),
                        ),
                        const SizedBox(width: 8),
                        if (_series.year.isNotEmpty)
                          Text(_series.year,
                              style: AppText.label.copyWith(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(_series.title,
                        style: AppText.h1.copyWith(fontSize: 23)),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        if (_series.rating > 0) ...<Widget>[
                          Icon(Icons.star_rounded,
                              color: AppColors.amber, size: 16),
                          const SizedBox(width: 3),
                          Text(_series.rating.toStringAsFixed(1),
                              style: AppText.bodyBold.copyWith(fontSize: 12.5)),
                          const SizedBox(width: 14),
                        ],
                        if (_series.viewsLabel.isNotEmpty) ...<Widget>[
                          Icon(Icons.visibility_rounded,
                              color: AppColors.muted, size: 15),
                          const SizedBox(width: 4),
                          Text('${_series.viewsLabel} مشاهدة',
                              style: AppText.label.copyWith(fontSize: 11.5)),
                          const SizedBox(width: 14),
                        ],
                        Icon(Icons.videocam_rounded,
                            color: AppColors.muted, size: 15),
                        const SizedBox(width: 4),
                        Builder(builder: (BuildContext context) {
                          final int n = _episodes?.length ?? 0;
                          return Text(
                              n > 0
                                  ? '$n episode${n == 1 ? '' : 's'}'
                                  : 'Hentai Haven',
                              style: AppText.label.copyWith(fontSize: 11.5));
                        }),
                      ],
                    ),
                    if (genres.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        genres.take(5).join('  ·  '),
                        style: AppText.label.copyWith(
                            fontSize: 11.5, color: AppColors.sub),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _PlayButton(onTap: () {
                      final List<HhEpisode> eps = _episodes ?? const <HhEpisode>[];
                      _play(eps.isNotEmpty ? eps.first.number : 1);
                    }),
                    if (_series.synopsis.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 22),
                      Text(_expanded
                              ? _series.synopsis
                              : (_series.synopsis.length > 180
                                  ? '${_series.synopsis.substring(0, 178)}…'
                                  : _series.synopsis),
                          style: AppText.body.copyWith(fontSize: 13)),
                      if (_series.synopsis.length > 180)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _expanded = !_expanded),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                                _expanded ? 'عرض أقل' : 'اقرأ المزيد',
                                style: AppText.bodyBold.copyWith(
                                    color: HhColors.red, fontSize: 12)),
                          ),
                        ),
                    ],
                  ],
                ),
              ),

              // ---------- Episodes ----------
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('الحلقات',
                      style: AppText.h2, textAlign: TextAlign.start),
                ),
              ),
              _EpisodeList(
                state: this,
                episodes: _episodes,
                error: _episodesError,
                currentSlug: _series.slug,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Play button (section accent)
// =============================================================================

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HhColors.red,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 6),
              Text('تشغيل',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Episode list
// =============================================================================

class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.state,
    required this.episodes,
    required this.error,
    required this.currentSlug,
  });

  final _HhDetailsScreenState state;
  final List<HhEpisode>? episodes;
  final String? error;
  final String currentSlug;

  @override
  Widget build(BuildContext context) {
    if (episodes == null && error == null) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
            child: CircularProgressIndicator(
                color: HhColors.red, strokeWidth: 2.4)),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.surface,
            border: Border.all(color: AppColors.stroke),
          ),
          child: Text(error!, style: AppText.body),
        ),
      );
    }
    final List<HhEpisode> eps = episodes!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: <Widget>[
          for (final HhEpisode ep in eps)
            _EpisodeTile(
              episode: ep,
              onTap: () => state._play(ep.number),
              trailing: DownloadIconButton(
                downloadKey: state._dlKey(ep.number),
                color: AppColors.sub,
                onStart: () => state._download(ep.number),
              ),
            ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile(
      {required this.episode, required this.onTap, this.trailing});

  final HhEpisode episode;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 122,
                    height: 70,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ColoredBox(color: AppColors.surfaceHi),
                        if (episode.thumb.isNotEmpty)
                          Image.network(episode.thumb,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        Center(
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.45),
                              border: Border.all(
                                  color: Colors.white, width: 1.6),
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 18),
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
                      Text('الحلقة ${episode.number}',
                          style: AppText.bodyBold.copyWith(fontSize: 13.5)),
                      const SizedBox(height: 3),
                      Text('بث HLS · +18',
                          style: AppText.label.copyWith(fontSize: 10.5)),
                    ],
                  ),
                ),
                ?trailing,
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
