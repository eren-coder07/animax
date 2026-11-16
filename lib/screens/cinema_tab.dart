import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/cinema_api.dart';
import '../widgets/common.dart';
import 'cinema_details_screen.dart';

/// Accent used by the Cinema section (vidsrc gold on the app's dark base).
class CinemaColors {
  CinemaColors._();
  static const Color gold = Color(0xFFF5C518); // IMDb gold
  static const Color goldSoft = Color(0x29F5C518);
}

/// The "Cinema" tab — Cinemeta catalogs (Stremio's official public metadata
/// addon): trending movies, popular + top-rated series, new releases and
/// keyword search. Titles open in [CinemaDetailsScreen] and play through the
/// multi-server embed player with built-in subtitles.
class CinemaTab extends StatefulWidget {
  const CinemaTab({super.key});

  @override
  State<CinemaTab> createState() => _CinemaTabState();
}

class _CinemaTabState extends State<CinemaTab>
    with AutomaticKeepAliveClientMixin {
  List<CinemaItem>? _trending;
  List<CinemaItem>? _popularSeries;
  List<CinemaItem>? _topMovies;
  List<CinemaItem>? _topSeries;
  List<CinemaItem>? _newMovies;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _error = null);
    Future<void> row(
        String key, Future<List<CinemaItem>> Function() fetch) async {
      try {
        final List<CinemaItem> items = await fetch();
        if (!mounted) return;
        setState(() {
          if (key == 'trending') _trending = items;
          if (key == 'series') _popularSeries = items;
          if (key == 'movies') _topMovies = items;
          if (key == 'topseries') _topSeries = items;
          if (key == 'new') _newMovies = items;
        });
      } catch (_) {}
    }

    // Primary row first (fallback banner if it fails), rest in parallel.
    await row('trending', () => CinemaApi.I.trendingMovies());
    unawaited(row('series', () => CinemaApi.I.popularSeries()));
    unawaited(row('movies', () => CinemaApi.I.topMovies()));
    unawaited(row('topseries', () => CinemaApi.I.topSeries()));
    unawaited(row('new', () => CinemaApi.I.moviesByYear(2026)));
    if (_trending == null && mounted) {
      setState(() => _error = 'Cannot reach the Cinema catalog right now.');
    }
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const CinemaSearchScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(58),
        child: SafeArea(
          top: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Row(
              children: <Widget>[
                Text('Cinema', style: AppText.h1),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: CinemaColors.goldSoft,
                    border: Border.all(color: CinemaColors.gold, width: 1),
                  ),
                  child: const Text('IMDb',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: CinemaColors.gold)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search_rounded,
                      color: AppColors.text, size: 26),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: CinemaColors.gold,
        backgroundColor: AppColors.surface,
        onRefresh: _loadAll,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 36),
          children: <Widget>[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_error!,
                        style: AppText.body
                            .copyWith(fontSize: 13, color: AppColors.danger)),
                    TextButton.icon(
                      onPressed: _loadAll,
                      icon: const Icon(Icons.refresh_rounded,
                          size: 18, color: AppColors.text),
                      label: const Text('Retry',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.5,
                              color: AppColors.text)),
                    ),
                  ],
                ),
              )
            else ...<Widget>[
              _Row(
                title: 'Trending movies',
                items: _trending,
                onOpen: _openItem,
              ),
              _Row(
                title: 'Popular series',
                items: _popularSeries,
                onOpen: _openItem,
              ),
              _Row(
                title: 'Top rated movies',
                items: _topMovies,
                onOpen: _openItem,
              ),
              _Row(
                title: 'Top rated series',
                items: _topSeries,
                onOpen: _openItem,
              ),
              _Row(
                title: 'New in 2026',
                items: _newMovies,
                onOpen: _openItem,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openItem(CinemaItem item) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CinemaDetailsScreen(item: item),
    ));
  }
}

// =============================================================================
// Horizontal catalog row
// =============================================================================

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.items, required this.onOpen});

  final String title;
  final List<CinemaItem>? items;
  final void Function(CinemaItem) onOpen;

  @override
  Widget build(BuildContext context) {
    final List<CinemaItem>? list = items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Text(title, style: AppText.h2),
        ),
        if (list == null)
          const SizedBox(
            height: 170,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: CinemaColors.gold, strokeWidth: 2),
              ),
            ),
          )
        else if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Text('Nothing here right now.',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.sub)),
          )
        else
          SizedBox(
            height: 232,
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (BuildContext _, int i) =>
                  _Card(item: list[i], onOpen: onOpen),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item, required this.onOpen});

  final CinemaItem item;
  final void Function(CinemaItem) onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onOpen(item),
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (item.poster.isNotEmpty)
                      Image.network(
                        item.poster,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: AppColors.surfaceHi),
                      )
                    else
                      const ColoredBox(color: AppColors.surfaceHi),
                    if (item.imdbRating > 0)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.star_rounded,
                                  color: CinemaColors.gold, size: 11),
                              const SizedBox(width: 2),
                              Text(item.imdbRating.toStringAsFixed(1),
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(item.isSeries ? 'SERIES' : 'MOVIE',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 7.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: item.isSeries
                                    ? AppColors.green
                                    : CinemaColors.gold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(fontSize: 11.5)),
            if (item.releaseInfo.isNotEmpty)
              Text(item.releaseInfo,
                  maxLines: 1,
                  style: AppText.label.copyWith(
                      fontSize: 10, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Search
// =============================================================================

class CinemaSearchScreen extends StatefulWidget {
  const CinemaSearchScreen({super.key});

  @override
  State<CinemaSearchScreen> createState() => _CinemaSearchScreenState();
}

class _CinemaSearchScreenState extends State<CinemaSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<CinemaItem>? _results;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), () => _run(q));
  }

  Future<void> _run(String q) async {
    final String query = q.trim();
    if (query.length < 2) {
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<CinemaItem> items = await CinemaApi.I.search(query);
      if (!mounted) return;
      setState(() {
        _results = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Search failed — check your connection.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<CinemaItem>? list = _results;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: FieldBox(
          controller: _controller,
          hint: 'Movies or series…',
          icon: Icons.search_rounded,
          onChanged: _onChanged,
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: CinemaColors.gold))
          : _error != null
              ? EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Search unavailable',
                  message: _error!,
                )
              : list == null
                  ? const Center(
                      child: Text('Type at least 2 characters to search.',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: AppColors.sub)))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 10,
                              childAspectRatio: 0.52),
                      itemCount: list.length,
                      itemBuilder: (BuildContext _, int i) => _Card(
                          item: list[i],
                          onOpen: (CinemaItem it) {
                            Navigator.of(context)
                                .push(MaterialPageRoute<void>(
                              builder: (_) => CinemaDetailsScreen(item: it),
                            ));
                          }),
                    ),
    );
  }
}
