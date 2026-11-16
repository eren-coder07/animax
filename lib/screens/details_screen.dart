import 'package:flutter/material.dart';

import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  bool _expanded = false;
  String _season = 'Episodes';

  late Anime _anime;
  Future<List<Episode>>? _episodesFuture;
  Future<List<Anime>>? _recsFuture;
  Future<Anime>? _detailsFuture;
  List<Anime> _recs = const <Anime>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Anime args = ModalRoute.of(context)!.settings.arguments as Anime;
    if (args.id != _anime.id) {
      _anime = args;
      _episodesFuture = AppState.I.episodesFor(_anime);
      _recsFuture = AppState.I.moreLikeAsync(_anime).then((List<Anime> list) {
        if (mounted) setState(() => _recs = list);
        return list;
      });
      _detailsFuture = AppState.I.loadDetails(_anime);
    }
  }

  @override
  void initState() {
    super.initState();
    _anime = const Anime(
        id: '',
        title: '',
        poster: '',
        score: 0,
        year: '',
        genres: <String>[],
        synopsis: '');
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              // ---------- Hero ----------
              SizedBox(
                height: 400,
                width: double.infinity,
                child: Hero(
                  tag: 'poster-${_anime.id}',
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(anime: _anime, radius: 0),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.heroFade,
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
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

              // ---------- Content ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<Anime>(
                      future: _detailsFuture,
                      builder: (BuildContext context, AsyncSnapshot<Anime> snap) {
                        final Anime a = snap.data ?? _anime;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.title, style: AppText.h2.copyWith(height: 1.25)),
                            const SizedBox(height: 6),
                            if (a.genres.isNotEmpty)
                              Text('${a.genreLine}.',
                                  style: AppText.label.copyWith(fontSize: 12)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    PrimaryButton(
                      label: 'Play',
                      playIcon: true,
                      height: 50,
                      expanded: true,
                      onTap: () async {
                        final List<Episode> eps =
                            await _episodesFuture ?? const <Episode>[];
                        if (!context.mounted) return;
                        Navigator.pushNamed(
                          context,
                          '/player',
                          arguments: eps.isNotEmpty
                              ? (_anime, eps.first)
                              : (_anime, null),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    FutureBuilder<Anime>(
                      future: _detailsFuture,
                      builder: (BuildContext context, AsyncSnapshot<Anime> snap) {
                        final Anime a = snap.data ?? _anime;
                        return Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: AppColors.green, size: 20),
                            const SizedBox(width: 4),
                            Text(a.score.toStringAsFixed(1),
                                style: AppText.bodyBold.copyWith(fontSize: 15)),
                            const SizedBox(width: 16),
                            if (a.year.isNotEmpty)
                              Text(a.year, style: AppText.bodyBold),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: AppColors.stroke),
                              ),
                              child: Text(a.ageRating,
                                  style: AppText.label.copyWith(fontSize: 10)),
                            ),
                            const SizedBox(width: 12),
                            Text(
                                a.isMovie ? a.duration : '${a.episodeCount} eps',
                                style: AppText.label.copyWith(fontSize: 11)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<Anime>(
                      future: _detailsFuture,
                      builder: (BuildContext context, AsyncSnapshot<Anime> snap) {
                        final Anime a = snap.data ?? _anime;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.synopsis.isEmpty
                                  ? 'Synopsis will load from the backend…'
                                  : a.synopsis,
                              style: AppText.body,
                              maxLines: _expanded ? 40 : 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            if (a.synopsis.isNotEmpty)
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _expanded = !_expanded),
                                child: Text(_expanded ? 'Show less' : 'Read more',
                                    style: AppText.bodyBold.copyWith(
                                        color: AppColors.green, fontSize: 12)),
                              ),
                            if (a.genres.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 20),
                              Text('Genre: ${a.genreLine}.',
                                  style: AppText.label.copyWith(fontSize: 11.5)),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // ---------- Episodes ----------
                    Row(
                      children: [
                        const Text('Episodes', style: AppText.h3),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _pickSeason(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Text(_season,
                                    style: AppText.bodyBold.copyWith(fontSize: 12)),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_down_rounded,
                                    size: 17, color: AppColors.sub),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FutureBuilder<List<Episode>>(
                      future: _episodesFuture,
                      builder: (BuildContext context,
                          AsyncSnapshot<List<Episode>> snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const SizedBox(
                            height: 98,
                            child: Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                    color: AppColors.green, strokeWidth: 2.5),
                              ),
                            ),
                          );
                        }
                        final List<Episode> episodes =
                            snap.data ?? const <Episode>[];
                        if (episodes.isEmpty) {
                          return Container(
                            height: 84,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text('Episodes unavailable for this title',
                                style: AppText.label.copyWith(fontSize: 12)),
                          );
                        }
                        return SizedBox(
                          height: 148,
                          child: ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            scrollDirection: Axis.horizontal,
                            itemCount: episodes.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 12),
                            itemBuilder: (BuildContext context, int i) {
                              final Episode ep = episodes[i];
                              return GestureDetector(
                                onTap: () => Navigator.pushNamed(
                                    context, '/player',
                                    arguments: (_anime, ep)),
                                child: SizedBox(
                                  width: 172,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        height: 98,
                                        child: PosterImage(
                                          anime: _anime,
                                          radius: 12,
                                          child: Center(
                                            child: Container(
                                              width: 34,
                                              height: 34,
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.4),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: Colors.white,
                                                    width: 1.8),
                                              ),
                                              child: const Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: Colors.white,
                                                  size: 21),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text('Episode ${ep.number}',
                                          style: AppText.bodyBold
                                              .copyWith(fontSize: 12)),
                                      Text(
                                          ep.duration.isEmpty
                                              ? (ep.hasDub ? 'SUB • DUB' : 'SUB')
                                              : ep.duration,
                                          style: AppText.label),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 26),
                    // ---------- More Like This ----------
                    SectionHeader(
                      title: 'More Like This',
                      onSeeAll: () => Navigator.pushNamed(context, '/catalog',
                          arguments: (
                            'More Like This',
                            _recs.isNotEmpty ? _recs : state.moreLike(_anime.id),
                          )),
                    ),
                    FutureBuilder<List<Anime>>(
                      future: _recsFuture,
                      builder: (BuildContext context,
                          AsyncSnapshot<List<Anime>> snap) {
                        final List<Anime> recs =
                            snap.data ?? state.moreLike(_anime.id);
                        if (recs.isEmpty) {
                          return Container(
                            height: 64,
                            alignment: Alignment.center,
                            child: Text('Nothing here yet',
                                style: AppText.label.copyWith(fontSize: 12)),
                          );
                        }
                        return SizedBox(
                          height: 226,
                          child: ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            scrollDirection: Axis.horizontal,
                            itemCount: recs.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 14),
                            itemBuilder: (BuildContext context, int i) {
                              final Anime other = recs[i];
                              return PosterCard(
                                anime: other,
                                width: 136,
                                height: 190,
                                subtitle:
                                    '★ ${other.score.toStringAsFixed(1)} • ${other.year}',
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _pickSeason(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: const Text('Episodes', style: AppText.h3),
        children: <String>['Episodes', 'Sub only', 'Dub only']
            .map((String s) => SimpleDialogOption(
                  onPressed: () {
                    setState(() => _season = s);
                    Navigator.pop(ctx);
                  },
                  child: Text(s,
                      style: AppText.bodyBold.copyWith(
                          color: _season == s ? AppColors.green : AppColors.text)),
                ))
            .toList(),
      ),
    );
  }
}

