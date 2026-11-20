import 'package:flutter/material.dart';

import '../core/akwam_api.dart';
import '../core/app_theme.dart';
import '../core/library_store.dart';
import '../widgets/mb_ui.dart';

/// Akwam section accent (site brand teal).
class AkwamColors {
  AkwamColors._();
  static const Color teal = Color(0xFF1FC8EE);
  static const Color tealSoft = Color(0x251FC8EE);
}

/// Which Akwam feed the grid shows.
enum AkwamFeed { recent, movies, series, shows }

extension AkwamFeedX on AkwamFeed {
  String get label {
    switch (this) {
      case AkwamFeed.recent:
        return 'أُضيف حديثًا';
      case AkwamFeed.movies:
        return 'أفلام';
      case AkwamFeed.series:
        return 'مسلسلات';
      case AkwamFeed.shows:
        return 'برامج';
    }
  }
}

/// Akwam home feed: continue watching + one poster row per catalog.
class AkwamTab extends StatefulWidget {
  const AkwamTab({super.key});

  @override
  State<AkwamTab> createState() => _AkwamTabState();
}

class _AkwamTabState extends State<AkwamTab>
    with AutomaticKeepAliveClientMixin {
  final Map<AkwamFeed, List<AkwamItem>> _rows = <AkwamFeed, List<AkwamItem>>{};
  final Set<AkwamFeed> _loading = <AkwamFeed>{};
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  static Future<List<AkwamItem>> fetch(AkwamFeed f, int page) {
    switch (f) {
      case AkwamFeed.recent:
        return AkwamApi.I.recent(page: page);
      case AkwamFeed.movies:
        return AkwamApi.I.movies(page: page);
      case AkwamFeed.series:
        return AkwamApi.I.series(page: page);
      case AkwamFeed.shows:
        return AkwamApi.I.shows(page: page);
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _error = null;
      _loading.addAll(AkwamFeed.values);
    });
    await Future.wait(AkwamFeed.values.map((AkwamFeed f) async {
      try {
        final List<AkwamItem> items = await fetch(f, 1);
        if (!mounted) return;
        setState(() => _rows[f] = items);
      } on AkwamApiException catch (e) {
        if (mounted) setState(() => _error ??= e.message);
      } catch (_) {
        if (mounted) {
          setState(() => _error ??= 'تعذّر الوصول إلى أكوام — حاول لاحقًا.');
        }
      } finally {
        if (mounted) setState(() => _loading.remove(f));
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bool allEmpty = _rows.values.every((List<AkwamItem> l) => l.isEmpty);
    return RefreshIndicator(
      color: AppColors.brandGreen,
      backgroundColor: AppColors.surface,
      onRefresh: _loadAll,
      child: ListenableBuilder(
        listenable: LibraryStore.I,
        builder: (BuildContext context, _) {
          final List<HistoryRow> recent = LibraryStore.I.history
              .where((HistoryRow r) => r.kind == 'akwam')
              .take(10)
              .toList();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              if (recent.isNotEmpty) _ContinueStrip(rows: recent),
              if (_error != null && allEmpty && _loading.isEmpty)
                _ErrorBox(message: _error!, onRetry: _loadAll),
              for (final AkwamFeed f in AkwamFeed.values)
                if (_loading.contains(f) || (_rows[f]?.isNotEmpty ?? false))
                  PosterRow<AkwamItem>(
                    title: f.label,
                    items: _rows[f] ?? const <AkwamItem>[],
                    loading: _loading.contains(f),
                    onAll: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => AkwamGrid(feed: f, standalone: true))),
                    itemBuilder: (BuildContext c, AkwamItem it, double w) =>
                        AkwamCard(item: it, width: w),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Paginated 3-column catalog grid (category tab or "الكل" page).
class AkwamGrid extends StatefulWidget {
  const AkwamGrid({super.key, required this.feed, this.standalone = false});
  final AkwamFeed feed;
  final bool standalone;

  @override
  State<AkwamGrid> createState() => _AkwamGridState();
}

class _AkwamGridState extends State<AkwamGrid>
    with AutomaticKeepAliveClientMixin {
  final List<AkwamItem> _items = <AkwamItem>[];
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 1;
      _done = false;
      _error = null;
    });
    await _load();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final List<AkwamItem> fresh = await _AkwamTabState.fetch(widget.feed, _page);
      if (!mounted) return;
      setState(() {
        for (final AkwamItem it in fresh) {
          if (!_items.any((AkwamItem x) => x.id == it.id)) _items.add(it);
        }
        _page++;
        _loading = false;
        if (fresh.isEmpty) _done = true;
      });
    } on AkwamApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _error = 'تعذّر الوصول إلى أكوام — حاول لاحقًا.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Widget grid = RefreshIndicator(
      color: AppColors.brandGreen,
      backgroundColor: AppColors.surface,
      onRefresh: _reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _load();
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: <Widget>[
            if (_error != null)
              SliverToBoxAdapter(
                  child: _ErrorBox(message: _error!, onRetry: _reload)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.56,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    if (i >= _items.length) {
                      return const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: AppColors.brandGreen, strokeWidth: 2.4),
                        ),
                      );
                    }
                    return AkwamCard(item: _items[i]);
                  },
                  childCount: _items.length +
                      (_done || _error != null ? 0 : 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.standalone) return grid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(widget.feed.label),
      ),
      body: grid,
    );
  }
}

/// Akwam poster (opens the details page).
class AkwamCard extends StatelessWidget {
  const AkwamCard({super.key, required this.item, this.width});

  final AkwamItem item;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return PosterTile(
      title: item.title,
      image: item.poster,
      width: width,
      badge: item.qualityLabel,
      rating: item.rating,
      onTap: () =>
          Navigator.pushNamed(context, '/akwam-details', arguments: item),
    );
  }
}

/// "Continue watching" strip — wide cards with a gradient play button.
class _ContinueStrip extends StatelessWidget {
  const _ContinueStrip({required this.rows});
  final List<HistoryRow> rows;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (BuildContext c, int i) {
          final HistoryRow r = rows[i];
          final String path = r.key.startsWith('akwam:') ? r.key.substring(6) : '';
          return GestureDetector(
            onTap: () {
              final AkwamItem? it = AkwamApi.itemFromPath(path,
                  title: r.title, poster: r.poster);
              if (it != null) {
                Navigator.pushNamed(context, '/akwam-details', arguments: it);
              }
            },
            child: Container(
              width: 250,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: <Widget>[
                  SizedBox(width: 44, height: 64, child: NetImage(r.poster)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(r.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: kFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        Text(r.label,
                            maxLines: 1,
                            style: const TextStyle(
                                fontFamily: kFont,
                                fontSize: 12,
                                color: AppColors.sub)),
                      ],
                    ),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsetsDirectional.only(end: 10),
                    decoration: const BoxDecoration(
                        gradient: AppColors.brandGrad, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Color(0xFF07130D), size: 20),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            const Icon(Icons.wifi_off_rounded, color: AppColors.sub, size: 30),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: kFont, fontSize: 13.5, color: AppColors.sub)),
            const SizedBox(height: 12),
            GradientButton(label: 'إعادة المحاولة', height: 40, onTap: onRetry),
          ],
        ),
      ),
    );
  }
}
