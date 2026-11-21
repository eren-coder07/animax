import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'panel_crop_screen.dart';

import '../core/social.dart';
import '../core/app_prefs.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../widgets/download_button.dart';
import '../core/library_store.dart';
import '../core/net_quality.dart';
import '../core/manga_api.dart';

/// Manga reader.
///
/// Two modes (Settings → Comics):
///  * vertical — swipe up / down through pages,
///  * paged    — horizontal pages, right-to-left by default (manga style).
///
/// Progress is stored per chapter ([LibraryStore]); a chapter auto-marks as
/// read when its last page is reached, and the next chapter is one tap away
/// via the bottom bar. Page URLs resolve through MangaDex's at-home servers,
/// optionally using the smaller `data-saver` renders.
class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen({
    super.key,
    required this.manga,
    required this.chapters,
    required this.startIndex,
  });

  final MangaItem manga;
  final List<MangaChapter> chapters;
  final int startIndex;

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late PageController _pageCtl;
  late int _chapterIdx;
  List<String> _pages = const <String>[];
  bool _loadingPages = true;
  String? _pageError;
  int _pageIndex = 0;
  bool _chromeVisible = true;
  Map<int, List<String>> _prefetched = <int, List<String>>{};

  String get _key => 'manga:${widget.manga.id}';

  MangaChapter get _chapter => widget.chapters[_chapterIdx];

  @override
  void initState() {
    super.initState();
    _chapterIdx = widget.startIndex.clamp(0, widget.chapters.length - 1);
    _pageCtl = PageController();
    Social.countView('manga:${widget.manga.id}',
        title: widget.manga.title, poster: widget.manga.cover, kind: 'manga');
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    const MethodChannel ch = MethodChannel('animax/app');
    ch.invokeMethod<bool>('setKeepScreenOn', <String, dynamic>{'keep': true})
        .catchError((Object e) => false);
    _openChapter(_chapterIdx, resume: true);
  }

  @override
  void dispose() {
    _pageCtl.dispose();
    const MethodChannel ch = MethodChannel('animax/app');
    ch.invokeMethod<bool>('setKeepScreenOn', <String, dynamic>{'keep': false})
        .catchError((Object e) => false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _openChapter(int idx, {bool resume = false}) async {
    if (idx < 0 || idx >= widget.chapters.length) return;
    setState(() {
      _chapterIdx = idx;
      _loadingPages = true;
      _pageError = null;
      _pageIndex = 0;
    });
    try {
      List<String>? urls = _prefetched[idx];
      if (urls == null) {
        urls = await MangaApi.I.pages(widget.chapters[idx].id,
            dataSaver: AppPrefs.I.readerDataSaver || NetQuality.isSlow);
        _prefetched[idx] = urls;
      }
      if (!mounted) return;
      setState(() {
        _pages = urls ?? const <String>[];
        _loadingPages = false;
      });
      if (resume) {
        final ProgressEntry? p =
            LibraryStore.I.progressOf(_key, widget.chapters[idx].id);
        if (p != null &&
            !p.watched &&
            p.positionSec > 0 &&
            p.positionSec < _pages.length) {
          // Resume on the stored page (1-based positionSec).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _pages.isEmpty) return;
            _pageCtl.jumpToPage(p.positionSec.clamp(0, _pages.length - 1));
            setState(() => _pageIndex = p.positionSec);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPages = false;
        _pageError = e is MangaApiException
            ? e.message
            : 'تعذّر الوصول إلى MangaDex — تحقّق من اتصالك.';
      });
    }
  }

  void _onPage(int i) {
    setState(() => _pageIndex = i);
    LibraryStore.I.saveProgress(
      key: _key,
      sub: _chapter.id,
      positionSec: i,
      durationSec: _pages.length,
    );
    if (i >= _pages.length - 1) {
      // Reached the end → mark read + offer next chapter.
      LibraryStore.I.markWatched(_key, _chapter.id, watched: true);
      LibraryStore.I.pushHistory(
        key: _key,
        title: widget.manga.title,
        poster: widget.manga.cover,
        kind: 'manga',
        sub: _chapter.id,
        label: _chapter.chipLabel,
      );
    }
    _prefetchNext();
  }

  void _prefetchNext() {
    final int next = _chapterIdx + 1;
    if (next >= widget.chapters.length || _prefetched.containsKey(next)) return;
    MangaApi.I
        .pages(widget.chapters[next].id, dataSaver: AppPrefs.I.readerDataSaver || NetQuality.isSlow)
        .then((List<String> urls) => _prefetched[next] = urls)
        .catchError((Object e) => const <String>[]);
  }

  void _nextChapter() {
    if (_chapterIdx + 1 < widget.chapters.length) {
      _openChapter(_chapterIdx + 1);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('هذا أحدث فصل — أنت متابع لكل شيء!')));
    }
  }

  void _prevChapter() {
    if (_chapterIdx - 1 >= 0) _openChapter(_chapterIdx - 1);
  }

  void toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  void _openSettings() {
    final AppPrefs prefs = AppPrefs.I;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (BuildContext ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (BuildContext bctx, void Function(void Function()) setM) =>
              ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            children: <Widget>[
              const Text('إعدادات القارئ',
                  style: TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.readerMode == 'paged',
                onChanged: (bool v) {
                  prefs.set('readerMode', v ? 'paged' : 'vertical');
                  setM(() {});
                  setState(() {}); // rebuild reader with the new mode
                },
                title: const Text('وضع الصفحات (اسحب جانبيًا)',
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 13.5,
                        color: AppColors.text)),
                subtitle: Text(prefs.readerMode == 'paged'
                    ? 'صفحات أفقية'
                    : 'تمرير عمودي',
                    style: const TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 11,
                        color: AppColors.muted)),
              ),
              if (prefs.readerMode == 'paged')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: prefs.readerRtl,
                  onChanged: (bool v) {
                    prefs.set('readerRtl', v);
                    setM(() {});
                    setState(() {});
                  },
                  title: const Text('من اليمين لليسار (أسلوب المانغا)',
                      style: TextStyle(
                          fontFamily: 'Plex',
                          fontSize: 13.5,
                          color: AppColors.text)),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.readerDataSaver,
                onChanged: (bool v) {
                  prefs.set('readerDataSaver', v);
                  setM(() {});
                  _prefetched.clear();
                  _openChapter(_chapterIdx, resume: true);
                },
                title: const Text('صور موفّرة للبيانات',
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 13.5,
                        color: AppColors.text)),
                subtitle: const Text('صفحات مضغوطة أصغر',
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 11,
                        color: AppColors.muted)),
              ),
              const SizedBox(height: 6),
              const Text('الخلفية',
                  style: TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 12,
                      color: AppColors.muted)),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  for (final (String, Color) bg in <(String, Color)>[
                    ('black', Colors.black),
                    ('gray', const Color(0xFF2A2A2A)),
                    ('white', Colors.white),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          prefs.set('readerBg', bg.$1);
                          setM(() {});
                          setState(() {});
                        },
                        child: Container(
                          width: 44,
                          height: 32,
                          decoration: BoxDecoration(
                            color: bg.$2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: prefs.readerBg == bg.$1
                                    ? AppColors.accent
                                    : AppColors.stroke,
                                width: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _bg => switch (AppPrefs.I.readerBg) {
        'white' => Colors.white,
        'gray' => const Color(0xFF2A2A2A),
        _ => Colors.black,
      };

  @override
  Widget build(BuildContext context) {
    final bool paged = AppPrefs.I.readerMode == 'paged';
    final bool rtl = AppPrefs.I.readerRtl;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _loadingPages
                ? Center(
                    child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.accent)))
                : _pageError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text('تعذّر تحميل الصفحات — $_pageError',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontFamily: 'Plex',
                                    fontSize: 12,
                                    color: AppColors.sub)),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => _openChapter(_chapterIdx,
                                  resume: true),
                              child: const Text('إعادة المحاولة',
                                  style: TextStyle(
                                      fontFamily: 'Plex',
                                      color: AppColors.text)),
                            ),
                          ],
                        ),
                      )
                    : _pages.isEmpty
                        ? const Center(
                            child: Text('هذا الفصل لا يحتوي على صفحات.',
                                style: TextStyle(
                                    fontFamily: 'Plex',
                                    fontSize: 13,
                                    color: AppColors.sub)))
                        : PageView.builder(
                            controller: _pageCtl,
                            scrollDirection: paged
                                ? Axis.horizontal
                                : Axis.vertical,
                            reverse: paged && rtl,
                            itemCount: _pages.length,
                            onPageChanged: _onPage,
                            itemBuilder: (BuildContext c, int i) =>
                                _PageImage(
                              url: _pages[i],
                              label: '${i + 1}/${_pages.length}',
                            ),
                          ),
          ),
          if (_chromeVisible) ...<Widget>[
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black.withValues(alpha: 0.72),
                padding: EdgeInsets.fromLTRB(
                    8, MediaQuery.of(context).padding.top + 4, 8, 8),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(widget.manga.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'Plex',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          Text(_chapter.chipLabel,
                              style: const TextStyle(
                                  fontFamily: 'Plex',
                                  fontSize: 10.5,
                                  color: Colors.white60)),
                        ],
                      ),
                    ),
                    DownloadIconButton(
                      chapterId: _chapter.id,
                      size: 21,
                      onStart: () => DownloadManager.I.addComicChapter(
                        title: widget.manga.title,
                        chapterLabel:
                            '${_chapter.chipLabel} · ${_chapter.displayTitle}',
                        chapterId: _chapter.id,
                        poster: widget.manga.cover,
                      ),
                    ),
                    IconButton(
                      key: const Key('cutPanel'),
                      tooltip: 'قص لوحة',
                      icon: const Icon(Icons.content_cut_rounded,
                          color: Colors.white, size: 21),
                      onPressed: _pages.isEmpty
                          ? null
                          : () => showPanelCropper(
                                context,
                                imageUrl: _pages[_pageIndex.clamp(0, _pages.length - 1)],
                                mangaId: widget.manga.id,
                                mangaTitle: widget.manga.title,
                                cover: widget.manga.cover,
                                chapterId: _chapter.id,
                                chapterLabel: _chapter.chipLabel,
                                page: _pageIndex.clamp(0, _pages.length - 1),
                              ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded,
                          color: Colors.white, size: 21),
                      onPressed: _openSettings,
                    ),
                  ],
                ),
              ),
            ),
            // Bottom bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black.withValues(alpha: 0.72),
                padding: EdgeInsets.fromLTRB(
                    10, 8, 10, MediaQuery.of(context).padding.bottom + 8),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: 'الفصل السابق',
                      onPressed: _prevChapter,
                      icon: const Icon(Icons.skip_previous_rounded,
                          color: Colors.white, size: 24),
                    ),
                    Expanded(
                      child: _pages.isEmpty
                          ? const SizedBox(height: 24)
                          : SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7),
                                activeTrackColor: AppColors.accent,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: AppColors.accent,
                              ),
                              child: Slider(
                                value: _pageIndex
                                    .toDouble()
                                    .clamp(0, _pages.length - 1),
                                max: (_pages.length - 1).toDouble(),
                                onChanged: (double v) {
                                  _pageCtl.jumpToPage(v.round());
                                },
                              ),
                            ),
                    ),
                    Text(
                      _pages.isEmpty ? '' : '${_pageIndex + 1}/${_pages.length}',
                      style: const TextStyle(
                          fontFamily: 'Plex',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'الفصل التالي',
                      onPressed: _nextChapter,
                      icon: const Icon(Icons.skip_next_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PageImage extends StatelessWidget {
  const _PageImage({required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context
          .findAncestorStateOfType<_ComicReaderScreenState>()
          ?.toggleChrome(),
      child: InteractiveViewer(
        maxScale: 3.5,
        child: Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (BuildContext context, Widget child,
                    ImageChunkEvent? progress) =>
                progress == null
                    ? child
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent)),
                            const SizedBox(height: 10),
                            Text(label,
                                style: const TextStyle(
                                    fontFamily: 'Plex',
                                    fontSize: 11,
                                    color: Colors.white54)),
                          ],
                        ),
                      ),
            errorBuilder: (_, _, _) => const Center(
              child: Icon(Icons.broken_image_rounded,
                  size: 42, color: Colors.white24),
            ),
          ),
        ),
      ),
    );
  }
}
