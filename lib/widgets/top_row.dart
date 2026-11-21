import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/social.dart';
import '../screens/item_nav.dart';
import 'mb_ui.dart';

/// «الأكثر مشاهدة على أنيماكس»: the community's most-viewed titles with
/// big rank numbers. Hidden when there is nothing to rank yet.
class TopOnAnimaxRow extends StatefulWidget {
  const TopOnAnimaxRow({super.key});

  /// Tests / screenshots: preset the ranking.
  @visibleForTesting
  static void debugSeed(List<TopItem> items) {
    _TopOnAnimaxRowState._cache = items;
    _TopOnAnimaxRowState._at = DateTime.now();
  }

  @override
  State<TopOnAnimaxRow> createState() => _TopOnAnimaxRowState();
}

class _TopOnAnimaxRowState extends State<TopOnAnimaxRow> {
  static List<TopItem>? _cache;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  List<TopItem>? _items = _cache;

  @override
  void initState() {
    super.initState();
    if (_cache == null || DateTime.now().difference(_at).inMinutes >= 5)
      _load();
  }

  Future<void> _load() async {
    try {
      final List<TopItem> l = await Social.topItems();
      _cache = l;
      _at = DateTime.now();
      if (mounted) setState(() => _items = l);
    } catch (_) {}
  }

  static String _kindLabel(String k) => switch (k) {
    'anime' => 'أنمي',
    'manga' => 'مانغا',
    _ => 'أكوام',
  };

  @override
  Widget build(BuildContext context) {
    final List<TopItem>? items = _items;
    if (items == null || items.length < 3) return const SizedBox.shrink();
    final double w = (MediaQuery.sizeOf(context).width - 24) / 2.7;
    return Column(
      key: const Key('topOnAnimax'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const RowHeader('الأكثر مشاهدة على أنيماكس'),
        SizedBox(
          height: w * 1.15 + 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (BuildContext c, int i) {
              final TopItem it = items[i];
              return GestureDetector(
                onTap: () => openItem(
                  c,
                  kind: it.kind,
                  ref: it.ref,
                  title: it.title,
                  poster: it.poster,
                ),
                child: SizedBox(
                  width: w,
                  child: Stack(
                    children: <Widget>[
                      // Big outlined rank number behind the poster.
                      PositionedDirectional(
                        start: 0,
                        bottom: 30,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontFamily: kFont,
                            fontSize: w * 0.62,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 2.5
                              ..color = Colors.white70,
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        end: 0,
                        top: 0,
                        width: w * 0.66,
                        height: w * 0.99,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: NetImage(it.poster),
                        ),
                      ),
                      PositionedDirectional(
                        end: 0,
                        bottom: 0,
                        width: w * 0.66,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              it.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: kFont,
                                fontSize: 12.5,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${compactCount(it.views)} مشاهدة · ${_kindLabel(it.kind)}',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                fontFamily: kFont,
                                fontSize: 11,
                                color: AppColors.sub,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
