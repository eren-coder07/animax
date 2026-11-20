import 'package:flutter/material.dart';

import '../core/akwam_api.dart';
import '../core/app_theme.dart';
import '../widgets/common.dart' show IconBubble;

/// Akwam section accent (site brand teal).
class AkwamColors {
  AkwamColors._();
  static const Color teal = Color(0xFF18A2B8);
  static const Color tealSoft = Color(0x2518A2B8);
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
        return 'مسلسل';
      case AkwamFeed.shows:
        return 'برامج';
    }
  }
}

/// The "Akwam" tab — Arabic movies / series / shows from akwam.ss with
/// native playback (direct MP4 streams, no WebView).
class AkwamTab extends StatefulWidget {
  const AkwamTab({super.key});

  @override
  State<AkwamTab> createState() => _AkwamTabState();
}

class _AkwamTabState extends State<AkwamTab>
    with AutomaticKeepAliveClientMixin {
  AkwamFeed _feed = AkwamFeed.recent;

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

  Future<void> _reload(AkwamFeed feed) async {
    setState(() {
      _feed = feed;
      _items.clear();
      _page = 1;
      _done = false;
      _error = null;
      _loading = true;
    });
    await _load();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      List<AkwamItem> fresh;
      switch (_feed) {
        case AkwamFeed.recent:
          fresh = await AkwamApi.I.recent(page: _page);
        case AkwamFeed.movies:
          fresh = await AkwamApi.I.movies(page: _page);
        case AkwamFeed.series:
          fresh = await AkwamApi.I.series(page: _page);
        case AkwamFeed.shows:
          fresh = await AkwamApi.I.shows(page: _page);
      }
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AkwamColors.teal,
        backgroundColor: AppColors.surface,
        onRefresh: () => _reload(_feed),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            // ---------- Header ----------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: <Widget>[
                    Text('أكوام', style: AppText.h1),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: AkwamColors.tealSoft,
                        border:
                            Border.all(color: AkwamColors.teal, width: 1.2),
                      ),
                      child: Text('أكوام',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: AkwamColors.teal)),
                    ),
                    const Spacer(),
                    IconBubble(Icons.search_rounded,
                        onTap: () => Navigator.pushNamed(context, '/akwam-search')),
                  ],
                ),
              ),
            ),

            // ---------- Feed chips ----------
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: <Widget>[
                    for (final AkwamFeed f in AkwamFeed.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FeedChip(
                          label: f.label,
                          active: f == _feed,
                          onTap: () => _reload(f),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ---------- Error banner ----------
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: GestureDetector(
                    onTap: () => _reload(_feed),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.stroke),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(_error!,
                              style: AppText.body
                                  .copyWith(color: AppColors.danger)),
                          const SizedBox(height: 8),
                          Text('اضغط لإعادة المحاولة',
                              style: AppText.bodyBold.copyWith(
                                  color: AkwamColors.teal, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ---------- Grid ----------
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.52,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    if (i >= _items.length) {
                      if (_done) return const SizedBox.shrink();
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                              color: AkwamColors.teal, strokeWidth: 2.4),
                        ),
                      );
                    }
                    return AkwamCard(item: _items[i]);
                  },
                  childCount:
                      _items.length + (_done || _error != null ? 0 : 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Feed chip
// -----------------------------------------------------------------------------

class _FeedChip extends StatelessWidget {
  const _FeedChip({required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AkwamColors.teal : AppColors.surface,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? Colors.white : AppColors.sub)),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Poster card (grid)
// -----------------------------------------------------------------------------

class AkwamCard extends StatelessWidget {
  const AkwamCard({super.key, required this.item});

  final AkwamItem item;

  void _open(BuildContext context) {
    Navigator.pushNamed(context, '/akwam-details', arguments: item);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Hero(
              tag: 'akwam-${item.id}',
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppColors.surfaceHi,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (item.poster.isNotEmpty)
                      Image.network(item.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: AppColors.surfaceHi))
                    else
                      ColoredBox(color: AppColors.surfaceHi),
                    if (item.qualityLabel.isNotEmpty)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                          child: Text(item.qualityLabel,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: AkwamColors.teal)),
                        ),
                      ),
                    if (item.rating > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.star_rounded,
                                  color: AppColors.amber, size: 12),
                              const SizedBox(width: 3),
                              Text(item.rating.toStringAsFixed(1),
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
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
          const SizedBox(height: 7),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodyBold.copyWith(fontSize: 11.5, height: 1.25),
          ),
          if (item.year.isNotEmpty)
            Text(item.year, style: AppText.label.copyWith(fontSize: 9.5)),
        ],
      ),
    );
  }
}
