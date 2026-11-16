import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/hh_api.dart';
import '../widgets/common.dart';
import 'hh_catalog_screen.dart';

/// Age-gate persistence key.
const String _kAgeOk = 'hh_age_ok';

/// Accent used by the +18 section (HentaiHaven brand red).
class HhColors {
  HhColors._();
  static const Color red = Color(0xFFFF003C);
  static const Color redSoft = Color(0x29FF003C);
}

/// The "+18" tab — Hentai Haven catalog (trending / recently updated /
/// new releases / genres) behind a persisted 18+ age confirmation.
class HentaiTab extends StatefulWidget {
  const HentaiTab({super.key});

  @override
  State<HentaiTab> createState() => _HentaiTabState();
}

class _HentaiTabState extends State<HentaiTab>
    with AutomaticKeepAliveClientMixin {
  bool _ageChecked = false;
  bool _ageOk = false;

  List<HhSeries>? _trending;
  List<HhSeries>? _updated;
  List<HhSeries>? _newest;
  List<HhGenre>? _genres;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAgeGate();
  }

  Future<void> _loadAgeGate() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ageOk = prefs.getBool(_kAgeOk) ?? false;
      _ageChecked = true;
    });
    if (_ageOk) _loadAll();
  }

  Future<void> _confirmAge() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAgeOk, true);
    if (!mounted) return;
    setState(() => _ageOk = true);
    _loadAll();
  }

  Future<void> _leave() async {
    await SharedPreferences.getInstance()
        .then((SharedPreferences p) => p.setBool(_kAgeOk, false));
    if (!mounted) return;
    AppState.I.setTab(0);
  }

  Future<void> _loadAll() async {
    setState(() => _error = null);
    try {
      final List<HhSeries> trending = await HentaiApi.I.trending();
      if (!mounted) return;
      setState(() => _trending = trending);
    } on ApiException catch (e) {
      // Fallback: the trending page scrape failed — try the REST catalog so
      // the tab still loads (ranked order is lost, but content is live).
      try {
        final List<HhSeries> fallback =
            await HentaiApi.I.fetchList(orderby: 'date');
        if (!mounted) return;
        setState(() {
          _trending = fallback;
          _error = 'Trending list unavailable — showing new releases instead.';
        });
      } catch (_) {
        if (mounted) setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Cannot reach hentaihaven.xxx right now.');
      }
    }
    // Secondary sections — parallel, failures stay silent (rows hidden).
    unawaited(_loadRest());
  }

  Future<void> _loadRest() async {
    try {
      final List<HhSeries> updated =
          await HentaiApi.I.fetchList(orderby: 'modified');
      if (mounted) setState(() => _updated = updated);
    } catch (_) {}
    try {
      final List<HhSeries> newest =
          await HentaiApi.I.fetchList(orderby: 'date');
      if (mounted) setState(() => _newest = newest);
    } catch (_) {}
    try {
      final List<HhGenre> genres = await HentaiApi.I.genres();
      if (mounted) setState(() => _genres = genres);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_ageChecked) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (!_ageOk) return _AgeGate(onEnter: _confirmAge, onLeave: _leave);
    return _Home(
      trending: _trending,
      updated: _updated,
      newest: _newest,
      genres: _genres,
      error: _error,
      onRetry: _loadAll,
    );
  }
}

// =============================================================================
// Age gate
// =============================================================================

class _AgeGate extends StatelessWidget {
  const _AgeGate({required this.onEnter, required this.onLeave});

  final VoidCallback onEnter;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HhColors.redSoft,
                  border: Border.all(color: HhColors.red, width: 2),
                ),
                child: const Icon(Icons.eighteen_up_rating_rounded,
                    color: HhColors.red, size: 52),
              ),
              const SizedBox(height: 26),
              Text('Adult content ahead',
                  textAlign: TextAlign.center, style: AppText.h1),
              const SizedBox(height: 12),
              Text(
                'This section streams explicit hentai (18+) from '
                'hentaihaven.xxx. By entering you confirm that you are of '
                'legal age in your jurisdiction and that you want to view '
                'adult content.',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(fontSize: 13.5, height: 1.7),
              ),
              const SizedBox(height: 34),
              _PrimaryActionButton(label: 'I am 18 or older — Enter', onTap: onEnter),
              const SizedBox(height: 12),
              HhChip(label: 'Leave', onTap: onLeave),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: HhColors.red, width: 1.4),
                    ),
                    child: Text('RTA · 18+ ONLY',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: HhColors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Section home
// =============================================================================

class _Home extends StatelessWidget {
  const _Home({
    required this.trending,
    required this.updated,
    required this.newest,
    required this.genres,
    required this.error,
    required this.onRetry,
  });

  final List<HhSeries>? trending;
  final List<HhSeries>? updated;
  final List<HhSeries>? newest;
  final List<HhGenre>? genres;
  final String? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final List<HhSeries> trend = trending ?? const <HhSeries>[];
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: HhColors.red,
        backgroundColor: AppColors.surface,
        onRefresh: onRetry,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 36),
          children: [
            // ---------- Header ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text('Hentai', style: AppText.h1),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: HhColors.redSoft,
                            border: Border.all(color: HhColors.red, width: 1.2),
                          ),
                          child: Text('18+',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: HhColors.red)),
                        ),
                      ],
                    ),
                  ),
                  IconBubble(Icons.search_rounded,
                      onTap: () => Navigator.pushNamed(context, '/hh-search')),
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.stroke),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(error!,
                          style: AppText.body.copyWith(color: AppColors.danger)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: onRetry,
                        child: Text('Tap to retry',
                            style: AppText.bodyBold
                                .copyWith(color: HhColors.red, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
              ),

            // ---------- Hero (top trending) ----------
            if (trend.isNotEmpty) _Hero(item: trend.first),

            // ---------- Trending ----------
            _Row(
              title: 'Trending Now',
              items: trend.take(12).skip(1).toList(),
              seeAll: () => Navigator.pushNamed(
                  context, '/hh-catalog',
                  arguments: const HhCatalogQuery(
                      mode: HhCatalogMode.trending, title: 'Trending Now')),
            ),

            // ---------- Recently Updated ----------
            _Row(
              title: 'Recently Updated',
              items: updated ?? const <HhSeries>[],
              seeAll: () => Navigator.pushNamed(
                  context, '/hh-catalog',
                  arguments: const HhCatalogQuery(
                      mode: HhCatalogMode.updated,
                      title: 'Recently Updated')),
            ),

            // ---------- New Releases ----------
            _Row(
              title: 'New Releases',
              items: newest ?? const <HhSeries>[],
              seeAll: () => Navigator.pushNamed(
                  context, '/hh-catalog',
                  arguments: const HhCatalogQuery(
                      mode: HhCatalogMode.newest, title: 'New Releases')),
            ),

            // ---------- Genres ----------
            if (genres != null && genres!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 26),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Browse by Genre',
                          style: AppText.h2, textAlign: TextAlign.left),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.start,
                        children: <Widget>[
                          for (final HhGenre g in genres!.take(18))
                            HhChip(
                              label: '${g.name}  ·  ${g.count}',
                              onTap: () => Navigator.pushNamed(
                                  context, '/hh-catalog',
                                  arguments: HhCatalogQuery(
                                      mode: HhCatalogMode.genre,
                                      genreId: g.id,
                                      title: g.name)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// HH-local buttons (section accent color)
// =============================================================================

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.label, required this.onTap});

  final String label;
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
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
      ),
    );
  }
}

class HhChip extends StatelessWidget {
  const HhChip({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(
            color: onTap == null ? AppColors.stroke : HhColors.red,
            width: 1.4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: onTap == null ? AppColors.sub : Colors.white)),
        ),
      ),
    );
  }
}

// =============================================================================
// Hero card
// =============================================================================

class _Hero extends StatelessWidget {
  const _Hero({required this.item});

  final HhSeries item;

  void _open(BuildContext context) {
    Navigator.pushNamed(context, '/hh-details', arguments: item);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: GestureDetector(
        onTap: () => _open(context),
        child: Container(
          height: 210,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppColors.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.thumb.isNotEmpty)
                Image.network(item.thumb,
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
                    colors: [Colors.transparent, Colors.black87, AppColors.bg],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: HhColors.red,
                          ),
                          child: Text('#1 TRENDING',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: Colors.white)),
                        ),
                        const SizedBox(width: 8),
                        if (item.rating > 0)
                          Icon(Icons.star_rounded,
                              color: AppColors.amber, size: 15),
                        if (item.rating > 0)
                          Text(item.rating.toStringAsFixed(1),
                              style: AppText.bodyBold.copyWith(fontSize: 12)),
                        if (item.viewsLabel.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 8),
                          Icon(Icons.visibility_rounded,
                              color: AppColors.muted, size: 14),
                          Text(item.viewsLabel,
                              style: AppText.label.copyWith(fontSize: 11.5)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.h2.copyWith(fontSize: 19)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        InkWell(
                          onTap: () => _open(context),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              color: HhColors.red,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 4),
                                Text('Watch',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Horizontal card row
// =============================================================================

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.items, this.seeAll});

  final String title;
  final List<HhSeries> items;
  final VoidCallback? seeAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(
            children: [
              Expanded(child: Text(title, style: AppText.h2)),
              if (seeAll != null)
                GestureDetector(
                  onTap: seeAll,
                  child: Text('See all',
                      style: AppText.bodyBold
                          .copyWith(color: HhColors.red, fontSize: 12.5)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 236,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int i) =>
                HhSeriesCard(series: items[i]),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Shared card (also used by catalog + search)
// =============================================================================

class HhSeriesCard extends StatelessWidget {
  const HhSeriesCard({super.key, required this.series, this.width = 128});

  final HhSeries series;
  final double width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, '/hh-details', arguments: series),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Hero(
                tag: 'hh-${series.slug}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: AppColors.surfaceHi),
                        if (series.thumb.isNotEmpty)
                          Image.network(series.thumb,
                              fit: BoxFit.cover,
                              loadingBuilder: (BuildContext context,
                                      Widget child,
                                      ImageChunkEvent? progress) =>
                                  progress == null
                                      ? child
                                      : ColoredBox(
                                          color: AppColors.surface,
                                          child: child),
                              errorBuilder: (_, _, _) => _Letter(series)),
                        Positioned(
                          top: 7,
                          right: 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              color: Colors.black.withValues(alpha: 0.72),
                              border:
                                  Border.all(color: HhColors.red, width: 1),
                            ),
                            child: Text('18+',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: HhColors.red)),
                          ),
                        ),
                        if (series.rating > 0)
                          Positioned(
                            top: 7,
                            left: 7,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(5),
                                color: Colors.black.withValues(alpha: 0.72),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.star_rounded,
                                      color: AppColors.amber, size: 11),
                                  const SizedBox(width: 2),
                                  Text(series.rating.toStringAsFixed(1),
                                      style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
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
            ),
            const SizedBox(height: 8),
            Text(series.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyBold.copyWith(fontSize: 12.5)),
            if (series.viewsLabel.isNotEmpty)
              Text('${series.viewsLabel} views',
                  style: AppText.label.copyWith(fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter(this.series);
  final HhSeries series;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceHi, AppColors.accentDeep],
        ),
      ),
      child: Text(
        series.title.isNotEmpty ? series.title[0].toUpperCase() : '?',
        style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: HhColors.red),
      ),
    );
  }
}
