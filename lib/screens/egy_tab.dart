import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/egy_api.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import 'egy_details_screen.dart';
import 'egy_gate_screen.dart';
import 'egy_search_screen.dart';

/// Accent used by the EgyDead section (Netflix red on the black UI).
class EgyColors {
  EgyColors._();
  static const Color red = Color(0xFFE50914);
  static const Color redSoft = Color(0x29E50914);
}

/// The "EgyDead" tab — movies & series from egydead.ca.
///
/// Rows are the site's own channels (Trending / Movies / Series / Action /
/// Horror / …), each paginated with infinite scroll. When Cloudflare blocks
/// the API a gate card offers an in-app WebView check.
class EgyTab extends StatefulWidget {
  const EgyTab({super.key});

  @override
  State<EgyTab> createState() => _EgyTabState();
}

class _EgyTabState extends State<EgyTab> with AutomaticKeepAliveClientMixin {
  /// First channel drives the hero + "Trending" row.
  static const int _trendingId = 5381;

  List<EgyTitle>? _trending;
  final Map<int, List<EgyTitle>> _rows = <int, List<EgyTitle>>{};
  final Map<int, int> _nextPage = <int, int>{};
  final Set<int> _loadingRows = <int>{};

  String? _error;
  bool _challenge = false;
  bool _cookiesLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _error = null;
      _challenge = false;
    });
    await EgyApi.I.loadCookies();
    _cookiesLoaded = true;
    // Hero + trending row first — the other rows stream in parallel.
    await _loadRow(_trendingId, refresh: true);
    if (mounted && _trending != null) {
      for (final ({int id, String label}) ch in EgyApi.channels.skip(1)) {
        unawaited(_loadRow(ch.id, refresh: true));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadRow(int channelId, {bool refresh = false}) async {
    if (_loadingRows.contains(channelId)) return;
    _loadingRows.add(channelId);
    try {
      final EgyPage page = await EgyApi.I.fetchChannel(
          channelId,
          page: refresh ? 1 : (_nextPage[channelId] ?? 1));
      if (!mounted) return;
      setState(() {
        _challenge = false;
        _error = null;
        if (refresh) {
          _rows[channelId] = page.items;
        } else {
          _rows[channelId] = <EgyTitle>[
            ...(_rows[channelId] ?? const <EgyTitle>[]),
            ...page.items,
          ];
        }
        _nextPage[channelId] = page.nextPage ?? 0;
        if (channelId == _trendingId) _trending = page.items;
      });
    } on EgyChallengeException {
      if (mounted) setState(() => _challenge = true);
    } on EgyApiException catch (e) {
      if (mounted && channelId == _trendingId) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted && channelId == _trendingId) {
        setState(() => _error = 'Cannot reach egydead.ca right now.');
      }
    } finally {
      _loadingRows.remove(channelId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openGate() async {
    final bool ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const EgyGateScreen()),
        ) ??
        false;
    if (ok) _loadAll();
  }

  void _openDetails(EgyTitle t) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EgyDetailsScreen(title: t),
    ));
  }

  void _openSearch() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const EgySearchScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_cookiesLoaded) {
      return const Center(
          child: CircularProgressIndicator(color: EgyColors.red));
    }

    // --- Cloudflare gate ---
    if (_challenge) {
      return _GateCard(
        onVerify: _openGate,
        onRetry: _loadAll,
        hasCookies: EgyApi.I.hasCookies,
      );
    }

    final List<EgyTitle>? trending = _trending;
    if (trending == null) {
      // First load failed / still running.
      if (_error != null) {
        return _ErrorCard(message: _error!, onRetry: _loadAll);
      }
      return const Center(child: CircularProgressIndicator(color: EgyColors.red));
    }

    return RefreshIndicator(
      color: EgyColors.red,
      backgroundColor: AppColors.surface,
      onRefresh: _loadAll,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          // ---------- Header ----------
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: <Widget>[
                  Text('EgyDead',
                      style: AppText.h2.copyWith(
                          color: EgyColors.red, fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Movies & series — egydead.ca',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(fontSize: 10.5)),
                  ),
                  IconBubble(Icons.search_rounded, onTap: _openSearch),
                ],
              ),
            ),
          ),

          // ---------- Hero ----------
          if (trending.isNotEmpty)
            SliverToBoxAdapter(child: _Hero(title: trending.first, onTap: () => _openDetails(trending.first))),

          // ---------- Trending row ----------
          _SliverRow(
            label: 'Trending',
            items: trending,
            onTap: _openDetails,
          ),

          // ---------- Remaining channels ----------
          for (final ({int id, String label}) ch in EgyApi.channels.skip(1))
            _SliverRow(
              key: ValueKey<int>(ch.id),
              label: ch.label,
              items: _rows[ch.id],
              onTap: _openDetails,
              loading: _loadingRows.contains(ch.id),
              failed: _rows[ch.id] == null &&
                  !_loadingRows.contains(ch.id) &&
                  _challenge == false &&
                  _error == null,
              onRetry: () => _loadRow(ch.id, refresh: true),
              onLoadMore: _nextPage[ch.id] != null && _nextPage[ch.id]! > 0
                  ? () => _loadRow(ch.id)
                  : null,
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// =============================================================================
// Hero banner
// =============================================================================

class _Hero extends StatelessWidget {
  const _Hero({required this.title, required this.onTap});
  final EgyTitle title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (title.hasBackdrop)
                  Image.network(title.backdrop,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, _, _) =>
                          Container(color: AppColors.surfaceHi))
                else
                  Container(color: AppColors.surfaceHi),
                // Bottom fade + label
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const <double>[0.35, 1.0],
                      colors: <Color>[
                        Colors.transparent,
                        AppColors.bg.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
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
                      const SizedBox(height: 6),
                      Text(title.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.h3.copyWith(fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        <String>[
                          if (title.yearLabel.isNotEmpty) title.yearLabel,
                          if (title.runtime > 0) '${title.runtime} min',
                          if (title.rating > 0)
                            '★ ${title.rating.toStringAsFixed(1)}',
                        ].join('  •  '),
                        style: AppText.label.copyWith(
                            fontSize: 10.5, color: AppColors.sub),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Horizontal content row
// =============================================================================

class _SliverRow extends StatelessWidget {
  const _SliverRow({
    super.key,
    required this.label,
    required this.items,
    required this.onTap,
    this.loading = false,
    this.failed = false,
    this.onRetry,
    this.onLoadMore,
  });

  final String label;
  final List<EgyTitle>? items;
  final ValueChanged<EgyTitle> onTap;
  final bool loading;
  final bool failed;
  final VoidCallback? onRetry;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final List<EgyTitle>? list = items;
    if (list == null) {
      if (failed) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                    child: Text('$label — unavailable',
                        style: AppText.label.copyWith(fontSize: 11))),
                GestureDetector(
                  onTap: onRetry,
                  child: Text('retry',
                      style: AppText.label
                          .copyWith(fontSize: 11, color: EgyColors.red)),
                ),
              ],
            ),
          ),
        );
      }
      if (loading) {
        return const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: SizedBox(
              height: 120,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: EgyColors.red, strokeWidth: 2),
                ),
              ),
            ),
          ),
        );
      }
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    if (list.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Text(label,
                style: AppText.h3.copyWith(fontSize: 14.5)),
          ),
          SizedBox(
            height: 172,
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: list.length + (onLoadMore != null ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 11),
              itemBuilder: (BuildContext context, int i) {
                if (i >= list.length) {
                  return _LoadMoreCard(onTap: onLoadMore!);
                }
                final EgyTitle t = list[i];
                return EgyPosterCard(title: t, onTap: () => onTap(t));
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Poster tile for EgyDead titles (170×~2:3 + score badge).
class EgyPosterCard extends StatelessWidget {
  const EgyPosterCard({super.key, required this.title, this.onTap});

  final EgyTitle title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (title.poster.isNotEmpty)
                      Image.network(title.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                              color: AppColors.surfaceHi,
                              child: const Icon(Icons.movie_creation_outlined,
                                  color: AppColors.muted, size: 26)))
                    else
                      Container(
                        color: AppColors.surfaceHi,
                        child: const Icon(Icons.movie_creation_outlined,
                            color: AppColors.muted, size: 26),
                      ),
                    if (title.rating > 0)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                              '★ ${title.rating.toStringAsFixed(1)}',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: EgyColors.red)),
                        ),
                      ),
                    if (title.isSeries)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: EgyColors.red,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text('TV',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(title.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyBold.copyWith(fontSize: 10.5)),
            Text(
              <String>[
                if (title.yearLabel.isNotEmpty) title.yearLabel,
                if (title.isSeries) 'Series',
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreCard extends StatelessWidget {
  const _LoadMoreCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.stroke),
        ),
        child: const Icon(Icons.add_rounded, color: AppColors.muted, size: 22),
      ),
    );
  }
}

// =============================================================================
// Status cards
// =============================================================================

class _GateCard extends StatelessWidget {
  const _GateCard({
    required this.onVerify,
    required this.onRetry,
    required this.hasCookies,
  });

  final VoidCallback onVerify;
  final VoidCallback onRetry;
  final bool hasCookies;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.shield_outlined,
                color: EgyColors.red, size: 44),
            const SizedBox(height: 14),
            Text('One-time access check',
                style: AppText.h3.copyWith(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              hasCookies
                  ? 'egydead.ca expired this device\'s access token (Cloudflare).\n'
                      'Verify once more — it takes a few seconds.'
                  : 'egydead.ca protects its API with a Cloudflare check.\n'
                      'Verify once in the built-in browser — it takes a few seconds.',
              textAlign: TextAlign.center,
              style: AppText.label.copyWith(fontSize: 11.5, height: 1.5),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                GhostChip(
                  label: 'Verify access',
                  active: true,
                  onTap: onVerify,
                ),
                GhostChip(label: 'Retry', onTap: onRetry),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded,
                color: AppColors.muted, size: 42),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(fontSize: 12)),
            const SizedBox(height: 16),
            GhostChip(label: 'Retry', active: true, onTap: onRetry),
          ],
        ),
      ),
    );
  }
}
