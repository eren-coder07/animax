import 'dart:async';

import 'package:flutter/material.dart';

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
              : 'Cannot reach MangaDex — check your connection.';
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
                      fontFamily: 'Poppins',
                      fontSize: 13.5,
                      color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: 'Search comics…',
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
                child: Text('Cancel',
                    style: TextStyle(
                        fontFamily: 'Poppins',
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
                      child: Text('Search failed — $_searchError',
                          textAlign: TextAlign.center,
                          style: AppText.label))
                  : (_searchResults?.isEmpty ?? true)
                      ? Center(
                          child: Text('No comics found for "${_searchCtl.text}"',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
            child: Row(
              children: <Widget>[
                Text('Comics', style: AppText.h1),
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
                'Thousands of free manga & comics from MangaDex — no ads, no Cloudflare.',
                style: AppText.label),
          ),
          _buildGenreChips(),
          const SizedBox(height: 10),
          MangaRow(title: 'Popular now', future: _popular!),
          const SizedBox(height: 22),
          MangaRow(title: 'Latest updates', future: _latest!),
          const SizedBox(height: 22),
          MangaRow(title: 'Fresh releases', future: _newest!),
          const SizedBox(height: 22),
          MangaRow(title: 'Top rated', future: _top!),
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
          const List<String> wanted = <String>[
            'Action', 'Adventure', 'Comedy', 'Fantasy', 'Romance',
            'Horror', 'Sci-Fi', 'Mystery', 'Slice of Life', 'Sports',
            'Supernatural', 'Thriller',
          ];
          final List<MangaTag> tags = (snap.data ?? const <MangaTag>[])
              .where((MangaTag t) => wanted.contains(t.name))
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
              label: Text(tags[i].name,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      color: AppColors.text)),
              onPressed: () => Navigator.of(context).push(SlideFadeRoute<void>(
                page: ComicCatalogScreen(tag: tags[i], title: tags[i].name),
              )),
            ),
          );
        },
      ),
    );
  }
}
