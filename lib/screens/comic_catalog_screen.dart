import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/manga_api.dart';
import '../widgets/manga_card.dart';
import '../widgets/shimmer.dart';
import 'comic_details_screen.dart';

/// Paginated genre / see-all catalog for comics.
class ComicCatalogScreen extends StatefulWidget {
  const ComicCatalogScreen({super.key, required this.tag, required this.title});

  final MangaTag? tag;
  final String title;

  @override
  State<ComicCatalogScreen> createState() => _ComicCatalogScreenState();
}

class _ComicCatalogScreenState extends State<ComicCatalogScreen> {
  final List<MangaItem> _items = <MangaItem>[];
  bool _loading = true;
  bool _error = false;
  bool _busyMore = false;
  int _offset = 0;
  static const int _page = 24;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_busyMore) return;
    _busyMore = true;
    try {
      final List<MangaItem> res = widget.tag == null
          ? await MangaApi.I.popular(limit: _page, offset: _offset)
          : await MangaApi.I.browseByTag(widget.tag!.id,
              limit: _page, offset: _offset);
      if (!mounted) return;
      setState(() {
        _items.addAll(res);
        _offset += res.length;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _items.isEmpty;
      });
    } finally {
      _busyMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.bg,
      ),
      body: _loading && _items.isEmpty
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.58,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 14),
              itemCount: 12,
              itemBuilder: (_, _) => const ShimmerBox(),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification n) {
                if (n.metrics.pixels >
                    n.metrics.maxScrollExtent - 600) {
                  _loadMore();
                }
                return false;
              },
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.58,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 14),
                itemCount: _items.length + (_error ? 0 : 3),
                itemBuilder: (BuildContext c, int i) {
                  if (i >= _items.length) return const ShimmerBox();
                  final MangaItem m = _items[i];
                  return MangaCard(
                    manga: m,
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(
                      builder: (BuildContext _) =>
                          ComicDetailsScreen(manga: m),
                    )),
                  );
                },
              ),
            ),
    );
  }
}
