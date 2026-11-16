import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/egy_api.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import 'egy_gate_screen.dart';
import 'egy_player_screen.dart';
import 'egy_tab.dart' show EgyColors, EgyPosterCard;

/// Details page for an EgyDead title (movie or series).
///
/// Movies → server chips (from `watch/{id}`) → EgyPlayerScreen.
/// Series → season selector + episode list (`titles/{id}/seasons/{n}`) →
/// per-episode videos → EgyPlayerScreen.
class EgyDetailsScreen extends StatefulWidget {
  const EgyDetailsScreen({super.key, required this.title});

  final EgyTitle title;

  @override
  State<EgyDetailsScreen> createState() => _EgyDetailsScreenState();
}

class _EgyDetailsScreenState extends State<EgyDetailsScreen> {
  EgyTitle get t => widget.title;

  // Movie servers
  List<EgyVideo>? _servers;
  String? _serversError;
  bool _challenge = false;

  // Series
  int _season = 1;
  List<EgyEpisode>? _episodes;
  String? _episodesError;

  List<EgyTitle>? _related;

  @override
  void initState() {
    super.initState();
    if (t.isSeries) {
      unawaited(_loadSeason(1));
    } else {
      unawaited(_loadServers());
    }
    unawaited(_loadRelated());
  }

  Future<void> _loadServers() async {
    setState(() {
      _serversError = null;
      _challenge = false;
    });
    try {
      await EgyApi.I.loadCookies();
      final int? vid = t.primaryVideoId;
      if (vid == null) {
        if (mounted) {
          setState(() => _serversError = 'No playable source for this movie.');
        }
        return;
      }
      final EgyWatch w = await EgyApi.I.fetchWatch(vid);
      if (!mounted) return;
      setState(() => _servers = w.servers);
    } on EgyChallengeException {
      if (mounted) setState(() => _challenge = true);
    } on EgyApiException catch (e) {
      if (mounted) setState(() => _serversError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _serversError = 'Cannot reach egydead.ca right now.');
      }
    }
  }

  Future<void> _loadSeason(int season) async {
    setState(() {
      _season = season;
      _episodes = null;
      _episodesError = null;
      _challenge = false;
    });
    try {
      await EgyApi.I.loadCookies();
      final List<EgyEpisode> eps =
          await EgyApi.I.fetchSeason(t.id, season);
      if (!mounted) return;
      setState(() => _episodes = eps);
    } on EgyChallengeException {
      if (mounted) setState(() => _challenge = true);
    } on EgyApiException catch (e) {
      if (mounted) setState(() => _episodesError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _episodesError = 'Cannot reach egydead.ca right now.');
      }
    }
  }

  Future<void> _loadRelated() async {
    try {
      final List<EgyTitle> rel = await EgyApi.I.fetchRelated(t.id);
      if (mounted && rel.isNotEmpty) setState(() => _related = rel);
    } catch (_) {
      // Row simply stays hidden.
    }
  }

  Future<void> _openGate() async {
    final bool ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const EgyGateScreen()),
        ) ??
        false;
    if (ok) {
      if (t.isSeries) {
        _loadSeason(_season);
      } else {
        _loadServers();
      }
    }
  }

  /// Resolves + plays a video, walking the fallback servers on failure.
  Future<void> _play({
    required List<EgyVideo> servers,
    int season = 0,
    int episode = 0,
    List<EgyEpisode> episodes = const <EgyEpisode>[],
  }) async {
    if (servers.isEmpty) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EgyPlayerScreen(
        title: t,
        servers: servers,
        season: season,
        episode: episode,
        episodes: episodes,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: <Widget>[
          // ---------- Scroll body ----------
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: _Header(title: t),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // ---------- Meta line ----------
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          if (t.rating > 0)
                            _Pill(
                              icon: Icons.star_rounded,
                              text: t.rating.toStringAsFixed(1),
                              accent: true,
                            ),
                          if (t.yearLabel.isNotEmpty)
                            _Pill(text: t.yearLabel),
                          if (t.runtime > 0)
                            _Pill(text: '${t.runtime} min'),
                          if (t.certification.isNotEmpty &&
                              t.certification != 'nr')
                            _Pill(
                                text: t.certification.toUpperCase()),
                          _Pill(text: t.isSeries ? 'Series' : 'Movie'),
                          if (t.views > 0)
                            _Pill(text: '${_compact(t.views)} views'),
                        ],
                      ),
                      // ---------- Genres ----------
                      if (t.genres.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: <Widget>[
                            for (final String g in t.genres)
                              _GenreChip(label: g),
                          ],
                        ),
                      ],
                      // ---------- Synopsis ----------
                      if (t.description.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        Text(t.description,
                            style: AppText.body.copyWith(
                                fontSize: 12.5, height: 1.65)),
                      ],
                      const SizedBox(height: 20),
                      // ---------- Watch section ----------
                      if (t.isSeries) ..._seriesSection() else ..._movieSection(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              // ---------- Related ----------
              if (_related != null && _related!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('More like this',
                        style: AppText.h3.copyWith(fontSize: 14.5)),
                  ),
                ),
              if (_related != null && _related!.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 172,
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: _related!.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 11),
                      itemBuilder: (BuildContext context, int i) {
                        final EgyTitle r = _related![i];
                        return EgyPosterCard(
                            title: r, onTap: () => _openRelated(r));
                      },
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
          ),

          // ---------- Back button ----------
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 0, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: IconBubble(Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).maybePop()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openRelated(EgyTitle r) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EgyDetailsScreen(title: r),
    ));
  }

  // -------------------------------------------------------------------------
  // Movie section
  // -------------------------------------------------------------------------

  List<Widget> _movieSection() {
    if (_challenge) {
      return <Widget>[_GateInline(onVerify: _openGate)];
    }
    if (_serversError != null) {
      return <Widget>[
        Text('Playback unavailable',
            style: AppText.h3.copyWith(fontSize: 14.5)),
        const SizedBox(height: 6),
        Text(_serversError!,
            style: AppText.label.copyWith(fontSize: 11.5)),
        const SizedBox(height: 10),
        GhostChip(label: 'Retry', active: true, onTap: _loadServers),
      ];
    }
    final List<EgyVideo>? servers = _servers;
    if (servers == null) {
      return const <Widget>[
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              color: EgyColors.red, strokeWidth: 2),
        ),
      ];
    }
    return <Widget>[
      Text('Watch now — servers',
          style: AppText.h3.copyWith(fontSize: 14.5)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (int i = 0; i < servers.length; i++)
            _ServerChip(
              label: servers[i].name.isEmpty
                  ? 'Server ${i + 1}'
                  : servers[i].name,
              onTap: () => _play(servers: servers),
            ),
        ],
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Series section
  // -------------------------------------------------------------------------

  List<Widget> _seriesSection() {
    if (_challenge) {
      return <Widget>[_GateInline(onVerify: _openGate)];
    }
    final int seasons = t.seasonsCount > 0 ? t.seasonsCount : 1;
    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text('Episodes',
                style: AppText.h3.copyWith(fontSize: 14.5)),
          ),
          if (seasons > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.stroke),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _season.clamp(1, seasons),
                  dropdownColor: AppColors.surfaceHi,
                  icon: const Icon(Icons.expand_more_rounded,
                      color: AppColors.sub, size: 18),
                  style: AppText.bodyBold.copyWith(fontSize: 12.5),
                  items: <DropdownMenuItem<int>>[
                    for (int s = 1; s <= seasons; s++)
                      DropdownMenuItem<int>(
                          value: s, child: Text('Season $s')),
                  ],
                  onChanged: (int? s) {
                    if (s != null) _loadSeason(s);
                  },
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (_episodesError != null) ...<Widget>[
        Text(_episodesError!, style: AppText.label.copyWith(fontSize: 11.5)),
        const SizedBox(height: 10),
        GhostChip(
            label: 'Retry', active: true, onTap: () => _loadSeason(_season)),
      ] else if (_episodes == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: EgyColors.red, strokeWidth: 2),
          ),
        )
      else if (_episodes!.isEmpty)
        Text('No episodes found for season $_season.',
            style: AppText.label.copyWith(fontSize: 11.5))
      else
        ...<Widget>[
          for (final EgyEpisode ep in _episodes!)
            _EpisodeTile(
              number: ep.number,
              name: ep.name,
              onTap: () => _playEpisode(ep),
            ),
        ],
    ];
  }

  Future<void> _playEpisode(EgyEpisode ep) async {
    List<EgyVideo> servers = ep.videos;
    if (servers.isEmpty) {
      try {
        servers = await EgyApi.I.fetchEpisodeVideos(t.id, _season, ep.number);
      } on EgyChallengeException {
        if (mounted) setState(() => _challenge = true);
        return;
      } catch (_) {
        servers = const <EgyVideo>[];
      }
    }
    if (servers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No playable source found for this episode.')),
        );
      }
      return;
    }
    await _play(
      servers: servers,
      season: _season,
      episode: ep.number,
      episodes: _episodes ?? const <EgyEpisode>[],
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// =============================================================================
// Header (backdrop + poster + names)
// =============================================================================

class _Header extends StatelessWidget {
  const _Header({required this.title});
  final EgyTitle title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Backdrop
        Stack(
          children: <Widget>[
            SizedBox(
              height: 210,
              width: double.infinity,
              child: title.hasBackdrop
                  ? Image.network(title.backdrop,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Container(color: AppColors.surfaceHi))
                  : Container(color: AppColors.surfaceHi),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const <double>[0.0, 1.0],
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.25),
                      AppColors.bg,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // Poster + titles
        Transform.translate(
          offset: const Offset(20, -66),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 108,
                  height: 158,
                  child: title.poster.isNotEmpty
                      ? Image.network(title.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: AppColors.surfaceHi))
                      : Container(color: AppColors.surfaceHi),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 20, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: EgyColors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                            title.isSeries ? 'SERIES' : 'MOVIE',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                      const SizedBox(height: 7),
                      Text(title.name,
                          style: AppText.h2.copyWith(fontSize: 16.5)),
                      if (title.originalTitle.isNotEmpty &&
                          title.originalTitle != title.name)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(title.originalTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label.copyWith(fontSize: 10.5)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Small pieces
// =============================================================================

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon, this.accent = false});
  final String text;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? EgyColors.redSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: accent ? EgyColors.red : AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon,
                size: 13,
                color: accent ? EgyColors.red : AppColors.sub),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: AppText.bodyBold.copyWith(
                  fontSize: 11,
                  color: accent ? EgyColors.red : AppColors.text)),
        ],
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Text(label,
          style: AppText.label.copyWith(fontSize: 10.5, color: AppColors.sub)),
    );
  }
}

class _ServerChip extends StatelessWidget {
  const _ServerChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EgyColors.red),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.play_arrow_rounded,
                size: 15, color: EgyColors.red),
            const SizedBox(width: 6),
            Text(label,
                style: AppText.bodyBold
                    .copyWith(fontSize: 11.5, color: EgyColors.red)),
          ],
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.number,
    required this.name,
    required this.onTap,
  });

  final int number;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHi,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.stroke),
                  ),
                  child: Text('$number',
                      style: AppText.bodyBold.copyWith(
                          fontSize: 12.5, color: EgyColors.red)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyBold.copyWith(fontSize: 12.5)),
                ),
                const Icon(Icons.play_circle_outline_rounded,
                    size: 20, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GateInline extends StatelessWidget {
  const _GateInline({required this.onVerify});
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EgyColors.red),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.shield_outlined,
                  color: EgyColors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Verification required',
                    style: AppText.bodyBold.copyWith(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'egydead.ca is asking for a Cloudflare check. Verify once in the '
            'built-in browser to continue.',
            style: AppText.label.copyWith(fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 10),
          GhostChip(label: 'Verify access', active: true, onTap: onVerify),
        ],
      ),
    );
  }
}
