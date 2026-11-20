import 'dart:async';

import 'package:flutter/material.dart';

import '../core/akwam_api.dart';
import '../core/api_service.dart';
import '../core/app_data.dart';
import '../core/app_theme.dart';
import '../core/manga_api.dart';
import '../widgets/mb_ui.dart';
import 'akwam_tab.dart';

/// One search across every source: Akwam first, then anime and manga —
/// each as a poster row.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _ctl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int _gen = 0;

  List<AkwamItem>? _akwam;
  List<Anime>? _anime;
  List<MangaItem>? _manga;

  static const List<String> _hints = <String>[
    'الهيبة', 'ولاد رزق', 'باب الحارة', 'One Piece', 'Breaking Bad',
    'الكبير أوي', 'Attack on Titan', 'Game of Thrones',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _run(v));
  }

  Future<void> _run(String raw) async {
    final String q = raw.trim();
    if (q == _query) return;
    final int gen = ++_gen;
    setState(() {
      _query = q;
      _akwam = null;
      _anime = null;
      _manga = null;
    });
    if (q.length < 2) return;
    Future<void> run<T>(Future<List<T>> f, void Function(List<T>) set) async {
      List<T> r;
      try {
        r = await f.timeout(const Duration(seconds: 20));
      } catch (_) {
        r = <T>[];
      }
      if (mounted && gen == _gen) setState(() => set(r));
    }

    await Future.wait(<Future<void>>[
      run<AkwamItem>(AkwamApi.I.search(q), (List<AkwamItem> r) => _akwam = r),
      run<Anime>(ApiService.I.search(q), (List<Anime> r) => _anime = r),
      run<MangaItem>(MangaApi.I.search(q, limit: 18),
          (List<MangaItem> r) => _manga = r),
    ]);
  }

  bool get _searching => _query.length >= 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 6),
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHi,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.search_rounded,
                              color: AppColors.sub, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _ctl,
                              autofocus: true,
                              onChanged: _onChanged,
                              onSubmitted: _run,
                              textInputAction: TextInputAction.search,
                              cursorColor: AppColors.brandGreen,
                              style: const TextStyle(
                                  fontFamily: kFont,
                                  fontSize: 15,
                                  color: Colors.white),
                              decoration: const InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: 'ابحث عن فيلم، مسلسل، أنمي…',
                                hintStyle: TextStyle(
                                    fontFamily: kFont,
                                    fontSize: 15,
                                    color: AppColors.muted),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _run(_ctl.text),
                            child: const Text('بحث',
                                style: TextStyle(
                                    fontFamily: kFont,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.brandGreen)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _searching ? _results() : _suggestions()),
          ],
        ),
      ),
    );
  }

  Widget _suggestions() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      children: <Widget>[
        const Text('عمليات بحث شائعة',
            style: TextStyle(
                fontFamily: kFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String h in _hints)
              ActionChip(
                backgroundColor: AppColors.surfaceHi,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                label: Text(h,
                    style: const TextStyle(
                        fontFamily: kFont, fontSize: 13.5, color: Colors.white)),
                onPressed: () {
                  _ctl.text = h;
                  _run(h);
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _results() {
    final bool allDone =
        _akwam != null && _anime != null && _manga != null;
    final bool none = allDone &&
        _akwam!.isEmpty &&
        _anime!.isEmpty &&
        _manga!.isEmpty;
    if (none) {
      return Center(
        child: Text('لا توجد نتائج لـ «$_query»',
            style: const TextStyle(
                fontFamily: kFont, fontSize: 15, color: AppColors.sub)),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: <Widget>[
        if (_akwam == null || _akwam!.isNotEmpty)
          PosterRow<AkwamItem>(
            title: 'أكوام — أفلام ومسلسلات',
            items: _akwam ?? const <AkwamItem>[],
            loading: _akwam == null,
            itemBuilder: (BuildContext c, AkwamItem it, double w) =>
                AkwamCard(item: it, width: w),
          ),
        if (_anime == null || _anime!.isNotEmpty)
          PosterRow<Anime>(
            title: 'أنمي',
            items: _anime ?? const <Anime>[],
            loading: _anime == null,
            itemBuilder: (BuildContext c, Anime a, double w) => PosterTile(
              title: a.title,
              image: a.poster,
              width: w,
              rating: a.score,
              onTap: () => Navigator.pushNamed(c, '/details', arguments: a),
            ),
          ),
        if (_manga == null || _manga!.isNotEmpty)
          PosterRow<MangaItem>(
            title: 'مانغا',
            items: _manga ?? const <MangaItem>[],
            loading: _manga == null,
            itemBuilder: (BuildContext c, MangaItem m, double w) => PosterTile(
              title: m.title,
              image: m.cover,
              width: w,
              onTap: () =>
                  Navigator.pushNamed(c, '/comic-details', arguments: m),
            ),
          ),
      ],
    );
  }
}
