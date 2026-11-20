import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/mb_ui.dart';
import '../core/app_theme.dart';
import '../core/manga_api.dart';
import '../widgets/manga_card.dart';
import '../widgets/shimmer.dart';
import '../widgets/transitions.dart';
import 'comic_catalog_screen.dart';

/// Comics tab — MangaDex browsing: rows + genre chips + inline search.
class ComicTab extends StatefulWidget {
  const ComicTab({super.key});

  @override
  State<ComicTab> createState() => _ComicTabState();
}

class _ComicTabState extends State<ComicTab>
    with AutomaticKeepAliveClientMixin {
  Future<List<MangaItem>>? _popular;
  Future<List<MangaItem>>? _latest;
  Future<List<MangaItem>>? _newest;
  Future<List<MangaItem>>? _top;
  Future<List<MangaTag>>? _tags;

  final TextEditingController _searchCtl = TextEditingController();
  List<MangaItem>? _searchResults;
  bool _searching = false;
  String _searchError = '';
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final MangaApi api = MangaApi.I;
    _popular = api.popular(limit: 18);
    _latest = api.latest(limit: 18);
    _newest = api.newest(limit: 18);
    _top = api.topRated(limit: 18);
    _tags = api.tags();
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
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() {
        _searching = true;
        _searchError = '';
      });
      try {
        final List<MangaItem> res =
            await MangaApi.I.search(v.trim(), limit: 30);
        if (!mounted) return;
        setState(() {
          _searchResults = res;
          _searching = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _searchError = e is MangaApiException
              ? e.message
              : 'تعذّر الوصول إلى MangaDex — تحقّق من اتصالك.';
          _searching = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _searchResults != null || _searching || _searchError.isNotEmpty
            ? _buildSearchBody()
            : _buildBrowseBody(),
      ),
    );
  }

  // ------------------------------------------------------------------ search

  Widget _buildSearchBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  autofocus: true,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 13.5,
                      color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن مانغا…',
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
                        borderSide:
                            const BorderSide(color: AppColors.stroke)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: AppColors.accent, width: 1.2)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  _searchCtl.clear();
                  setState(() {
                    _searchResults = null;
                    _searchError = '';
                  });
                },
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 12.5,
                        color: AppColors.accent)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _searching
              ? GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.58,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 14),
                  itemCount: 9,
                  itemBuilder: (_, _) => const ShimmerBox(),
                )
              : _searchError.isNotEmpty
                  ? Center(
                      child: Text('فشل البحث — $_searchError',
                          textAlign: TextAlign.center,
                          style: AppText.label))
                  : (_searchResults?.isEmpty ?? true)
                      ? Center(
                          child: Text('لا توجد نتائج لـ «${_searchCtl.text}»',
                              style: AppText.label))
                      : GridView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(20, 4, 20, 20),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  childAspectRatio: 0.58,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 14),
                          itemCount: _searchResults!.length,
                          itemBuilder: (BuildContext c, int i) =>
                              MangaCard(manga: _searchResults![i]),
                        ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ browse

  Widget _buildBrowseBody() {
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        _reload();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          if (!EmbeddedSection.of(context))
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
            child: Row(
              children: <Widget>[
                Text('مانغا', style: AppText.h1),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() => _searchResults = const <MangaItem>[]);
                  },
                  icon: const Icon(Icons.search_rounded,
                      color: AppColors.text, size: 24),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
                'آلاف المانغا والقصص المصوّرة المجانية من MangaDex — بدون إعلانات.',
                style: AppText.label),
          ),
          _buildGenreChips(),
          const SizedBox(height: 10),
          MangaRow(title: 'الأكثر شعبية', future: _popular!),
          const SizedBox(height: 22),
          MangaRow(title: 'آخر التحديثات', future: _latest!),
          const SizedBox(height: 22),
          MangaRow(title: 'إصدارات جديدة', future: _newest!),
          const SizedBox(height: 22),
          MangaRow(title: 'الأعلى تقييمًا', future: _top!),
          const SizedBox(height: 26),
        ],
      ),
    );
  }

  Widget _buildGenreChips() {
    return SizedBox(
      height: 40,
      child: FutureBuilder<List<MangaTag>>(
        future: _tags,
        builder: (BuildContext context, AsyncSnapshot<List<MangaTag>> snap) {
          // MangaDex tag name (filter key) → Arabic chip label.
          const Map<String, String> wanted = <String, String>{
            'Action': 'أكشن', 'Adventure': 'مغامرة', 'Comedy': 'كوميديا',
            'Fantasy': 'فانتازيا', 'Romance': 'رومانسي', 'Horror': 'رعب',
            'Sci-Fi': 'خيال علمي', 'Mystery': 'غموض',
            'Slice of Life': 'شريحة من الحياة', 'Sports': 'رياضة',
            'Supernatural': 'خارق للطبيعة', 'Thriller': 'إثارة',
          };
          final List<MangaTag> tags = (snap.data ?? const <MangaTag>[])
              .where((MangaTag t) => wanted.containsKey(t.name))
              .toList();
          if (tags.isEmpty) return const SizedBox.shrink();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tags.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (BuildContext c, int i) => ActionChip(
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.stroke),
              label: Text(wanted[tags[i].name] ?? tags[i].name,
                  style: const TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 11.5,
                      color: AppColors.text)),
              onPressed: () => Navigator.of(context).push(SlideFadeRoute<void>(
                page: ComicCatalogScreen(
                    tag: tags[i], title: wanted[tags[i].name] ?? tags[i].name),
              )),
            ),
          );
        },
      ),
    );
  }
}
