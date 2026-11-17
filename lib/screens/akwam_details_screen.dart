import 'package:flutter/material.dart';

import '../core/akwam_api.dart';
import '../core/app_theme.dart';
import '../widgets/common.dart' show IconBubble;
import 'akwam_tab.dart';

/// Akwam details: hero backdrop, meta row, synopsis, and either the
/// episode list (series / shows) or the quality list (movies).
class AkwamDetailsScreen extends StatefulWidget {
  const AkwamDetailsScreen({super.key});

  @override
  State<AkwamDetailsScreen> createState() => _AkwamDetailsScreenState();
}

class _AkwamDetailsScreenState extends State<AkwamDetailsScreen> {
  late AkwamItem _item;
  List<AkwamEpisode>? _episodes;
  List<AkwamSource>? _sources;
  String? _error;
  bool _expanded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _item = AkwamItem(id: '', path: '', kind: AkwamKind.movie, title: '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Object? args = ModalRoute.of(context)!.settings.arguments;
    if (args is AkwamItem && args.path != _item.path) {
      _item = args;
      _episodes = null;
      _sources = null;
      _error = null;
      _expanded = false;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final AkwamItem rich = await AkwamApi.I.details(_item);
      if (!mounted) return;
      setState(() {
        _item = rich;
        if (rich.isSeries) {
          _episodes = rich.episodes;
        } else {
          _sources = null;
        }
        _busy = false;
      });
      if (!rich.isSeries) {
        final List<AkwamSource> sources = await AkwamApi.I.sourcesFor(_item);
        if (!mounted) return;
        setState(() => _sources = sources);
      }
    } on AkwamApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this title.';
        _busy = false;
      });
    }
  }

  void _play({AkwamEpisode? episode}) {
    Navigator.pushNamed(
      context,
      '/akwam-player',
      arguments: (item: _item, episode: episode),
    );
  }

  void _playFirst() {
    if (_item.isSeries) {
      final List<AkwamEpisode> eps = _episodes ?? const <AkwamEpisode>[];
      _play(episode: eps.isNotEmpty ? eps.first : null);
    } else {
      _play();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                height: 380,
                width: double.infinity,
                child: Hero(
                  tag: 'akwam-${_item.id}',
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (_item.poster.isNotEmpty)
                        Image.network(_item.poster,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: AppColors.surfaceHi))
                      else
                        ColoredBox(color: AppColors.surfaceHi),
                      const DecoratedBox(
                          decoration:
                              BoxDecoration(gradient: AppColors.heroFade)),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                            color: AkwamColors.tealSoft,
                            border: Border.all(color: AkwamColors.teal,
                                width: 1.2),
                          ),
                          child: Text(
                              'AKWAM · ${_item.kind.label.toUpperCase()}',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: AkwamColors.teal)),
                        ),
                        const SizedBox(width: 8),
                        if (_item.qualityLabel.isNotEmpty)
                          Text(_item.qualityLabel,
                              style: AppText.label.copyWith(fontSize: 11.5)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(_item.title,
                        style: AppText.h1.copyWith(fontSize: 22)),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        if (_item.rating > 0) ...<Widget>[
                          Icon(Icons.star_rounded,
                              color: AppColors.amber, size: 16),
                          const SizedBox(width: 3),
                          Text(_item.rating.toStringAsFixed(1),
                              style:
                                  AppText.bodyBold.copyWith(fontSize: 12.5)),
                          const SizedBox(width: 14),
                        ],
                        if (_item.year.isNotEmpty) ...<Widget>[
                          Text(_item.year,
                              style: AppText.label.copyWith(fontSize: 11.5)),
                          const SizedBox(width: 14),
                        ],
                        if (_item.isSeries) ...<Widget>[
                          Icon(Icons.videocam_rounded,
                              color: AppColors.muted, size: 15),
                          const SizedBox(width: 4),
                          Builder(builder: (BuildContext context) {
                            final int n = _episodes?.length ?? 0;
                            return Text(
                                n > 0
                                    ? '$n episode${n == 1 ? '' : 's'}'
                                    : 'Akwam',
                                style:
                                    AppText.label.copyWith(fontSize: 11.5));
                          }),
                        ],
                      ],
                    ),
                    if (_item.genres.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _item.genres.take(5).join('  ·  '),
                        style: AppText.label
                            .copyWith(fontSize: 11.5, color: AppColors.sub),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _PlayButton(
                        onTap: _busy ? null : _playFirst,
                        label: _item.isSeries ? 'Play E1' : 'Play'),
                    if (_item.synopsis.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 22),
                      Text(_expanded
                              ? _item.synopsis
                              : (_item.synopsis.length > 180
                                  ? '${_item.synopsis.substring(0, 178)}…'
                                  : _item.synopsis),
                          style: AppText.body.copyWith(fontSize: 13)),
                      if (_item.synopsis.length > 180)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _expanded = !_expanded),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                                _expanded ? 'Show less' : 'Read more',
                                style: AppText.bodyBold.copyWith(
                                    color: AkwamColors.teal, fontSize: 12)),
                          ),
                        ),
                    ],
                  ],
                ),
              ),

              // ---------- Episodes (series / shows) ----------
              if (_item.isSeries) ...<Widget>[
                const SizedBox(height: 26),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Episodes',
                        style: AppText.h2, textAlign: TextAlign.left),
                  ),
                ),
                _EpisodeSection(state: this),
              ],

              // ---------- Qualities (movies) ----------
              if (!_item.isSeries) ...<Widget>[
                const SizedBox(height: 26),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Watch — quality',
                        style: AppText.h2, textAlign: TextAlign.left),
                  ),
                ),
                _QualitySection(state: this),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Play button
// -----------------------------------------------------------------------------

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap, required this.label});

  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? AppColors.surfaceHi : AkwamColors.teal,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.play_arrow_rounded,
                  color: onTap == null ? AppColors.muted : Colors.white,
                  size: 22),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: onTap == null ? AppColors.muted : Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Episode section (series / shows)
// -----------------------------------------------------------------------------

class _EpisodeSection extends StatelessWidget {
  const _EpisodeSection({required this.state});

  final _AkwamDetailsScreenState state;

  @override
  Widget build(BuildContext context) {
    final List<AkwamEpisode>? eps = state._episodes;
    if (state._busy && eps == null) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
            child: CircularProgressIndicator(
                color: AkwamColors.teal, strokeWidth: 2.4)),
      );
    }
    if (state._error != null && eps == null) {
      return _NoteCard(message: state._error!);
    }
    if (eps == null) {
      return const _NoteCard(message: 'Loading episodes…');
    }
    if (eps.isEmpty) {
      return const _NoteCard(message: 'No episodes on Akwam yet for this title.');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: <Widget>[
          for (final AkwamEpisode ep in eps)
            _EpisodeTile(
              episode: ep,
              onTap: () => state._play(episode: ep),
            ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.onTap});

  final AkwamEpisode episode;
  final VoidCallback onTap;

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
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AkwamColors.tealSoft,
                  ),
                  child: Text('${episode.number}',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AkwamColors.teal)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Episode ${episode.number}',
                          style:
                              AppText.bodyBold.copyWith(fontSize: 13.5)),
                      if (episode.date.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(episode.date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppText.label.copyWith(fontSize: 10.5)),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_outline_rounded,
                    color: AkwamColors.teal, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Quality section (movies)
// -----------------------------------------------------------------------------

class _QualitySection extends StatelessWidget {
  const _QualitySection({required this.state});

  final _AkwamDetailsScreenState state;

  @override
  Widget build(BuildContext context) {
    final List<AkwamSource>? sources = state._sources;
    if (sources == null && state._error == null) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
            child: CircularProgressIndicator(
                color: AkwamColors.teal, strokeWidth: 2.4)),
      );
    }
    if (state._error != null && (sources == null || sources.isEmpty)) {
      return _NoteCard(message: state._error!);
    }
    if (sources == null || sources.isEmpty) {
      return const _NoteCard(
          message: 'No playable quality found on Akwam right now.');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: <Widget>[
          for (final AkwamSource s in sources)
            _QualityTile(
              source: s,
              onTap: () => state._play(),
            ),
        ],
      ),
    );
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({required this.source, required this.onTap});

  final AkwamSource source;
  final VoidCallback onTap;

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
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AkwamColors.tealSoft,
                  ),
                  child: Text(source.quality,
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AkwamColors.teal)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Direct stream (MP4)',
                          style:
                              AppText.bodyBold.copyWith(fontSize: 13.5)),
                      if (source.size.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(source.size,
                            style:
                                AppText.label.copyWith(fontSize: 10.5)),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_outline_rounded,
                    color: AkwamColors.teal, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Note card
// -----------------------------------------------------------------------------

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColors.surface,
          border: Border.all(color: AppColors.stroke),
        ),
        child: Text(message, style: AppText.body),
      ),
    );
  }
}
