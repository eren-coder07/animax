import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/mb_ui.dart';
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
            if (!EmbeddedSection.of(context))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
              child: Row(
                children: <Widget>[
                  const Text('كرتون', style: AppText.h1),
                  const Spacer(),
                  Icon(Icons.animation_rounded,
                      color: AppColors.accent, size: 24),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                  'أفلام ومسلسلات كرتون — مفضّلات العائلة والكلاسيكيات '
                  'الحديثة، تُعرض بنفس مشغّل السيرفرات المتعددة مثل '
                  'السينما.',
                  style: AppText.label),
            ),
            // Inline search
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: TextField(
                controller: _searchCtl,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 13.5,
                    color: AppColors.text),
                decoration: InputDecoration(
                  hintText: 'ابحث عن كرتون…',
                  hintStyle: const TextStyle(
                      fontFamily: 'Plex',
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
              _CinemaRow(title: 'كرتون رائج', future: _trending!, onOpen: _openItem),
              _CinemaRow(title: 'مسلسلات كرتون شائعة', future: _popularSeries!, onOpen: _openItem),
              _CinemaRow(title: 'أفضل أفلام الكرتون', future: _topMovies!, onOpen: _openItem),
              _CinemaRow(title: 'الأعلى تقييمًا', future: _bestRated!, onOpen: _openItem),
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
          Text(_searching ? 'جارٍ البحث…' : 'النتائج',
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
            Text('لا توجد نتائج كرتون لـ «${_searchCtl.text}».',
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
                            fontFamily: 'Plex',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text)),
                    const SizedBox(height: 3),
                    Text(
                      '${item.isSeries ? 'مسلسل' : 'فيلم'}'
                      '${item.releaseInfo.isEmpty ? '' : ' · ${item.releaseInfo}'}'
                      '${item.imdbRating > 0 ? ' · ★ ${item.imdbRating.toStringAsFixed(1)}' : ''}',
                      style: const TextStyle(
                          fontFamily: 'Plex',
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
    return FutureBuilder<List<CinemaItem>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<CinemaItem>> snap) {
        final bool loading = snap.connectionState != ConnectionState.done;
        final List<CinemaItem> list = snap.data ?? const <CinemaItem>[];
        if (!loading && list.isEmpty) return const SizedBox.shrink();
        return PosterRow<CinemaItem>(
          title: title,
          items: list,
          loading: loading,
          itemBuilder: (BuildContext c, CinemaItem it, double w) => PosterTile(
            title: it.name,
            image: it.poster,
            width: w,
            rating: it.imdbRating,
            onTap: () => onOpen(it),
          ),
        );
      },
    );
  }
}
