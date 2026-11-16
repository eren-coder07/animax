import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/cartoon_api.dart';
import '../core/cinema_api.dart';
import '../widgets/transitions.dart';
import 'cinema_details_screen.dart';

/// Cartoons tab — Western animation (Cinemeta `genre=Animation`), playing
/// through the same multi-server Cinema player as the Cinema section.
class CartoonTab extends StatefulWidget {
  const CartoonTab({super.key});

  @override
  State<CartoonTab> createState() => _CartoonTabState();
}

class _CartoonTabState extends State<CartoonTab>
    with AutomaticKeepAliveClientMixin {
  Future<List<CinemaItem>>? _trending;
  Future<List<CinemaItem>>? _popularSeries;
  Future<List<CinemaItem>>? _topMovies;
  Future<List<CinemaItem>>? _bestRated;

  final TextEditingController _searchCtl = TextEditingController();
  List<CinemaItem>? _searchResults;
  bool _searching = false;
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final CartoonApi api = CartoonApi.I;
    _trending = api.trending();
    _popularSeries = api.popularSeries();
    _topMovies = api.topMovies();
    _bestRated = api.bestRated();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() => _searchResults = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _searching = true);
      try {
        final List<CinemaItem> res = await CartoonApi.I.search(v.trim());
        if (!mounted) return;
        setState(() {
          _searchResults = res;
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _searchResults = const <CinemaItem>[];
          _searching = false;
        });
      }
    });
  }

  void _openItem(CinemaItem item) {
    Navigator.of(context).push(SlideFadeRoute<void>(
      page: CinemaDetailsScreen(item: item),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
              child: Row(
                children: <Widget>[
                  const Text('Cartoons', style: AppText.h1),
                  const Spacer(),
                  Icon(Icons.animation_rounded,
                      color: AppColors.accent, size: 24),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                  'Animated movies & series — family favorites and modern '
                  'classics, streaming with the same multi-server player as '
                  'Cinema.',
                  style: AppText.label),
            ),
            // Inline search
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: TextField(
                controller: _searchCtl,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.5,
                    color: AppColors.text),
                decoration: InputDecoration(
                  hintText: 'Search cartoons…',
                  hintStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppColors.muted),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 20, color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 13, horizontal: 16),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.stroke)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: AppColors.accent, width: 1.2)),
                ),
              ),
            ),
            if (_searchResults != null || _searching) ...<Widget>[
              _buildSearchResults(),
            ] else ...<Widget>[
              _CinemaRow(title: 'Trending cartoons', future: _trending!, onOpen: _openItem),
              _CinemaRow(title: 'Popular animated series', future: _popularSeries!, onOpen: _openItem),
              _CinemaRow(title: 'Top animated movies', future: _topMovies!, onOpen: _openItem),
              _CinemaRow(title: 'Best rated animation', future: _bestRated!, onOpen: _openItem),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_searching ? 'Searching…' : 'Results',
              style: AppText.h3),
          const SizedBox(height: 12),
          if (_searching)
            Center(
                child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.accent)))
          else if (_searchResults!.isEmpty)
            Text('No animated titles found for "${_searchCtl.text}".',
                style: AppText.label)
          else
            ...List<Widget>.generate(_searchResults!.length, (int i) {
              final CinemaItem it = _searchResults![i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SearchRow(item: it, onTap: () => _openItem(it)),
              );
            }),
        ],
      ),
    );
  }
}

/// One search hit row.
class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.item, required this.onTap});

  final CinemaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 62,
                  child: item.poster.startsWith('http')
                      ? Image.network(item.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: AppColors.surfaceHi))
                      : ColoredBox(color: AppColors.surfaceHi),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text)),
                    const SizedBox(height: 3),
                    Text(
                      '${item.isSeries ? 'Series' : 'Movie'}'
                      '${item.releaseInfo.isEmpty ? '' : ' · ${item.releaseInfo}'}'
                      '${item.imdbRating > 0 ? ' · ★ ${item.imdbRating.toStringAsFixed(1)}' : ''}',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10.5,
                          color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal poster row backed by a Cinemeta catalog future.
class _CinemaRow extends StatelessWidget {
  const _CinemaRow({
    required this.title,
    required this.future,
    required this.onOpen,
  });

  final String title;
  final Future<List<CinemaItem>> future;
  final void Function(CinemaItem) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Text(title, style: AppText.h2),
        ),
        SizedBox(
          height: 220,
          child: FutureBuilder<List<CinemaItem>>(
            future: future,
            builder: (BuildContext context,
                AsyncSnapshot<List<CinemaItem>> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Center(
                    child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: AppColors.accent)));
              }
              if (snap.hasError || (snap.data?.isEmpty ?? true)) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    snap.hasError
                        ? 'Could not load — ${snap.error}'
                        : 'Nothing here right now.',
                    style: AppText.label,
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: snap.data!.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (BuildContext c, int i) {
                  final CinemaItem it = snap.data![i];
                  return _CartoonCard(item: it, onTap: () => onOpen(it));
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Poster card for cinema/cartoon items (reuses the app's NeonButton style
/// palette through [PosterLikeBox]).
class _CartoonCard extends StatelessWidget {
  const _CartoonCard({required this.item, required this.onTap});

  final CinemaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (item.poster.startsWith('http'))
                        Image.network(
                          item.poster,
                          fit: BoxFit.cover,
                          loadingBuilder: (BuildContext context, Widget child,
                                  ImageChunkEvent? progress) =>
                              progress == null
                                  ? child
                                  : ColoredBox(
                                      color: AppColors.surface),
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: AppColors.surfaceHi),
                        )
                      else
                        ColoredBox(color: AppColors.surfaceHi),
                      if (item.imdbRating > 0)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.star_rounded,
                                    size: 11, color: Color(0xFFFFC94D)),
                                const SizedBox(width: 2),
                                Text(
                                  item.imdbRating.toStringAsFixed(1),
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
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
            const SizedBox(height: 7),
            Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyBold.copyWith(
                    fontSize: 12, color: AppColors.text)),
            Text(
              '${item.isSeries ? 'Series' : 'Movie'}'
              '${item.releaseInfo.isEmpty ? '' : ' · ${item.releaseInfo}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
