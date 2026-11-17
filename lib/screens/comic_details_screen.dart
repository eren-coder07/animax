import 'package:flutter/material.dart';

import '../core/app_prefs.dart';
import '../core/app_theme.dart';
import '../core/library_store.dart';
import '../core/manga_api.dart';
import '../widgets/shimmer.dart';
import '../widgets/transitions.dart';
import 'comic_reader_screen.dart';

/// Comic details — cover, metadata, description, chapter list with read
/// markers, bookmarking and "continue reading".
class ComicDetailsScreen extends StatefulWidget {
  const ComicDetailsScreen({super.key, required this.manga});

  final MangaItem manga;

  @override
  State<ComicDetailsScreen> createState() => _ComicDetailsScreenState();
}

class _ComicDetailsScreenState extends State<ComicDetailsScreen> {
  MangaItem? _full;
  List<MangaChapter> _chapters = <MangaChapter>[];
  bool _loadingChapters = true;
  String? _chapterError;
  bool _descExpanded = false;

  String get _key => 'manga:${widget.manga.id}';

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    // Full details + chapter list in one go.
    try {
      final MangaItem full = await MangaApi.I.details(widget.manga.id);
      if (!mounted) return;
      setState(() => _full = full);
    } catch (_) {
      // Keep the catalog payload as fallback.
    }
    await _loadChapters();
  }

  Future<void> _loadChapters() async {
    setState(() => _loadingChapters = true);
    try {
      final List<MangaChapter> ch = await MangaApi.I.chapters(
          widget.manga.id, language: AppPrefs.I.mangaLanguage);
      if (!mounted) return;
      setState(() {
        _chapters = ch;
        _loadingChapters = false;
        _chapterError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingChapters = false;
        _chapterError = e is MangaApiException
            ? e.message
            : 'Cannot reach MangaDex — check your connection.';
      });
    }
  }

  MangaItem get item => _full ?? widget.manga;

  /// Oldest chapter with no saved progress — the "continue" target.
  MangaChapter? get _continueTarget {
    final List<MangaChapter> oldest = _chapters.reversed
        .where((MangaChapter c) => !c.isUnavailable)
        .toList();
    for (final MangaChapter c in oldest) {
      final ProgressEntry? p = LibraryStore.I.progressOf(_key, c.id);
      if (p == null || (!p.watched && p.fraction < 0.98)) return c;
    }
    return oldest.isNotEmpty ? oldest.last : null;
  }

  void _openReader(MangaChapter chapter) {
    final int index = _chapters.indexOf(chapter);
    Navigator.of(context).push(SlideFadeRoute<void>(
      page: ComicReaderScreen(
        manga: item,
        chapters: _chapters,
        startIndex: index < 0 ? 0 : index,
      ),
    ));
  }

  void _toggleBookmark() {
    final LibraryStore lib = LibraryStore.I;
    final LibEntry? existing = lib.entryOf(_key);
    if (existing?.inList ?? false) {
      lib.removeListEntry(_key);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${item.title} removed from My List')));
      }
    } else {
      lib.setListStatus(
        key: _key,
        title: item.title,
        poster: item.cover,
        kind: 'manga',
        status: LibStatus.watching,
        meta: '${item.year.isEmpty ? 'Manga' : item.year}'
            '${item.status.isEmpty ? '' : ' · ${item.status}'}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${item.title} saved to My List')));
      }
    }
  }

  Future<void> _pickStatus() async {
    final LibStatus? current = LibraryStore.I.entryOf(_key)?.status;
    final LibStatus? picked = await showModalBottomSheet<LibStatus>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Save to…',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text)))),
            for (final LibStatus s in LibStatus.values)
              ListTile(
                leading: Icon(
                    s == LibStatus.watching
                        ? Icons.visibility_rounded
                        : s == LibStatus.plan
                            ? Icons.bookmark_rounded
                            : s == LibStatus.done
                                ? Icons.check_circle_rounded
                                : s == LibStatus.hold
                                    ? Icons.pause_circle_rounded
                                    : Icons.remove_circle_outline_rounded,
                    color: s == current ? AppColors.accent : AppColors.muted),
                title: Text(s.label,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.5,
                        color:
                            s == current ? AppColors.accent : AppColors.text)),
                onTap: () => Navigator.of(ctx).pop(s),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (picked == null) return;
    LibraryStore.I.setListStatus(
      key: _key,
      title: item.title,
      poster: item.cover,
      kind: 'manga',
      status: picked,
      meta: '${item.year.isEmpty ? 'Manga' : item.year}'
          '${item.status.isEmpty ? '' : ' · ${item.status}'}',
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final MangaItem m = item;
    final LibEntry? entry = LibraryStore.I.entryOf(_key);
    final bool listed = entry?.inList ?? false;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: AppColors.bg,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: <Widget>[
              IconButton(
                icon: Icon(
                    listed
                        ? Icons.bookmark_added_rounded
                        : Icons.bookmark_add_outlined,
                    color: listed ? AppColors.accent : AppColors.text),
                onPressed: _toggleBookmark,
              ),
              if (listed)
                IconButton(
                  icon: const Icon(Icons.playlist_add_check_rounded,
                      color: AppColors.text),
                  onPressed: _pickStatus,
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.network(
                    m.cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        ColoredBox(color: AppColors.surface),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const <double>[0.0, 0.55, 1.0],
                        colors: <Color>[
                          Colors.transparent,
                          AppColors.bg.withValues(alpha: 0.55),
                          AppColors.bg,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(m.title,
                      style: AppText.h1.copyWith(fontSize: 23)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _metaChip(m.status.isEmpty
                          ? 'Manga'
                          : m.status[0].toUpperCase() + m.status.substring(1)),
                      if (m.year.isNotEmpty) _metaChip(m.year),
                      if (m.chapterCount > 0)
                        _metaChip('${m.chapterCount} chapters'),
                      if (m.authors.isNotEmpty) _metaChip(m.authors.first),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (m.followedCount > 0)
                    Row(
                      children: <Widget>[
                        Icon(Icons.favorite_rounded,
                            size: 14, color: AppColors.accent),
                        const SizedBox(width: 5),
                        Text('${m.followedLabel} followers',
                            style: AppText.label),
                      ],
                    ),
                  const SizedBox(height: 14),
                  // Continue-reading CTA
                  if (!_loadingChapters && _continueTarget != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.ink,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () => _openReader(_continueTarget!),
                        icon: const Icon(Icons.menu_book_rounded, size: 19),
                        label: Text(
                          LibraryStore.I.progressOf(_key,
                                      _continueTarget!.id) !=
                                  null
                              ? 'Continue ${_continueTarget!.chipLabel}'
                              : 'Start reading ${_continueTarget!.chipLabel}',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  // Description
                  if (m.description.isNotEmpty)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _descExpanded = !_descExpanded),
                      child: Text(
                        m.description,
                        maxLines: _descExpanded ? 40 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(height: 1.55),
                      ),
                    ),
                  if (m.tags.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: m.tags
                          .take(8)
                          .map((MangaTag t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.stroke),
                                ),
                                child: Text(t.name,
                                    style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 10.5,
                                        color: AppColors.sub)),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildChapterHeader(),
                ],
              ),
            ),
          ),
          _buildChapterList(),
        ],
      ),
    );
  }

  Widget _metaChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.sub)),
      );

  Widget _buildChapterHeader() {
    return Row(
      children: <Widget>[
        Text('Chapters',
            style: AppText.h3.copyWith(fontSize: 17)),
        const Spacer(),
        if (_chapters.isNotEmpty)
          Text('${_chapters.length} available',
              style: AppText.label),
      ],
    );
  }

  Widget _buildChapterList() {
    if (_loadingChapters) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < 6; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ShimmerBox(height: 56, radius: 12),
                ),
            ],
          ),
        ),
      );
    }
    if (_chapterError != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              Text('Chapters failed to load — $_chapterError',
                  style: AppText.label),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _loadChapters,
                child: const Text('Retry',
                    style: TextStyle(
                        fontFamily: 'Poppins', color: AppColors.text)),
              ),
            ],
          ),
        ),
      );
    }
    if (_chapters.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
              'No chapters available in your reader language yet — '
              'change it in Settings → Comics.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.muted)),
        ),
      );
    }
    return SliverList.separated(
      itemCount: _chapters.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext c, int i) {
        final MangaChapter ch = _chapters[i];
        final ProgressEntry? p = LibraryStore.I.progressOf(_key, ch.id);
        final bool read = p?.watched ?? false;
        final bool started = p != null && p.fraction > 0.01;
        return Opacity(
          opacity: ch.isUnavailable ? 0.45 : 1,
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: ch.isUnavailable ? null : () => _openReader(ch),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 64,
                      child: Text(ch.chipLabel,
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color:
                                  read ? AppColors.muted : AppColors.accent)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(ch.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: read
                                      ? AppColors.muted
                                      : AppColors.text)),
                          const SizedBox(height: 3),
                          Text(
                            '${ch.pages} pages'
                            '${ch.publishedAt.length >= 10 ? ' · ${ch.publishedAt.substring(0, 10)}' : ''}'
                            '${started && !read ? ' · ${p.fraction.toStringAsFixed(0)}%' : ''}',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10.5,
                                color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    if (read)
                      Icon(Icons.check_circle_rounded,
                          size: 18, color: AppColors.accent)
                    else
                      const Icon(Icons.chevron_right_rounded,
                          size: 20, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
