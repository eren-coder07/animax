import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/hh_api.dart';
import 'hentai_tab.dart';

/// What a catalog grid should list.
enum HhCatalogMode { trending, updated, newest, genre }

class HhCatalogQuery {
  const HhCatalogQuery({
    required this.mode,
    required this.title,
    this.genreId,
  });

  final HhCatalogMode mode;
  final String title;
  final int? genreId;
}

/// Paginated 3-column grid behind every "See all" (trending / recently
/// updated / new releases) and genre chip.
class HhCatalogScreen extends StatefulWidget {
  const HhCatalogScreen({super.key});

  @override
  State<HhCatalogScreen> createState() => _HhCatalogScreenState();
}

class _HhCatalogScreenState extends State<HhCatalogScreen> {
  HhCatalogQuery _query =
      const HhCatalogQuery(mode: HhCatalogMode.updated, title: '');

  final List<HhSeries> _items = <HhSeries>[];
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Object? args = ModalRoute.of(context)!.settings.arguments;
    final HhCatalogQuery q =
        args is HhCatalogQuery ? args : _query;
    if (q.mode != _query.mode ||
        q.genreId != _query.genreId ||
        q.title != _query.title) {
      _query = q;
      _items.clear();
      _page = 1;
      _done = false;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<HhSeries> fresh = const <HhSeries>[];
      switch (_query.mode) {
        case HhCatalogMode.trending:
          final List<HhSeries> all = await HentaiApi.I.trending();
          fresh = all.skip((_page - 1) * 24).take(24).toList();
          _done = true; // the trending page ships one ranked list
        case HhCatalogMode.updated:
          fresh = await HentaiApi.I.fetchList(
              orderby: 'modified', page: _page);
        case HhCatalogMode.newest:
          fresh = await HentaiApi.I.fetchList(orderby: 'date', page: _page);
        case HhCatalogMode.genre:
          fresh = await HentaiApi.I.byGenre(_query.genreId!, page: _page);
      }
      if (!mounted) return;
      setState(() {
        _items.addAll(fresh);
        _page++;
        _loading = false;
        if (fresh.isEmpty) _done = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // "rest_post_invalid_page_number" past the end — treat as done.
        if (e.statusCode == 400 || e.statusCode == 404) {
          _done = true;
        } else if (_items.isEmpty) {
          _error = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _error = 'تعذّر الوصول إلى المصدر — تحقّق من اتصالك.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.text,
        title: Text(_query.title,
            style: AppText.h3.copyWith(fontSize: 17)),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: HhColors.redSoft,
                  border: Border.all(color: HhColors.red, width: 1.2),
                ),
                child: Text('+18',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: HhColors.red)),
              ),
            ),
          ),
        ],
      ),
      body: _error != null && _items.isEmpty
          ? _ErrorCard(message: _error!, onRetry: () {
              setState(() {
                _error = null;
                _page = 1;
                _done = false;
              });
              _load();
            })
          : NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification n) {
                if (n.metrics.pixels >
                    n.metrics.maxScrollExtent - 600) {
                  _load();
                }
                return false;
              },
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.52,
                ),
                itemCount: _items.length + (_done ? 0 : 1),
                itemBuilder: (BuildContext context, int i) {
                  if (i >= _items.length) {
                    return const Center(
                        child: Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                          color: HhColors.red, strokeWidth: 2.4),
                    ));
                  }
                  return HhSeriesCard(series: _items[i], width: double.infinity);
                },
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: AppColors.muted, size: 40),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(fontSize: 13)),
            const SizedBox(height: 16),
            HhChip(label: 'إعادة المحاولة', onTap: onRetry),
          ],
        ),
      ),
    );
  }
}
