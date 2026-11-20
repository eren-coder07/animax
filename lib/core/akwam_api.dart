import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' show Element;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'app_http.dart';

/// Akwam — the "Akwam" section backend (https://akwam.ss), the Arabic
/// movies / series / shows streaming platform.
///
/// Live-verified page structure (2026-11-17, all requests plain GETs):
///
///  * Catalogs   → `GET /recent?page=N`, `/movies?page=N`, `/series?page=N`,
///                 `/shows?page=N` — poster cards (`div.entry-box`).
///  * Search     → `GET /search?q={query}&page=N` — same card markup.
///  * Item page  → `/movie/{id}/{slug}` or `/series/{id}/{slug}`:
///                 og:title / og:image / og:description, story block, and
///                 for series the `#series-episodes` episode grid
///                 (`/episode/{id}/{slug}/…` links with `p.entry-date`).
///  * Movie /    → quality tabs (`ul.header-tabs li a` → `#tab-N`) mapped
///    episode page onto `div.tab-content.quality#tab-N` panels holding
///                 `/watch/{fileId}/{itemId}/{slug}` links (+ sizes).
///  * Watch page → `GET /watch/{fileId}/…` HTML carries the direct
///                 `https://…/*.mp4` stream URL. Range requests are
///                 supported (HTTP 206), so it plays natively through
///                 `video_player` — no WebView, no embed hosts.
///
/// The site is Cloudflare-fronted; on Android requests go through Cronet
/// (Chromium's TLS stack) via [createHttpClient], same as the other sections.
class AkwamApi {
  AkwamApi._();
  static final AkwamApi I = AkwamApi._();

  static const String base = 'https://akwam.ss';

  final http.Client _client = createHttpClient();

  /// In-memory caches (per session).
  final Map<String, String> _watchCache = <String, String>{};
  final Map<String, List<AkwamEpisode>> _episodeCache =
      <String, List<AkwamEpisode>>{};

  static const String ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  Map<String, String> get _headers => <String, String>{
        'User-Agent': ua,
        'Referer': base,
        'Accept-Language': 'en;q=0.9,ar;q=0.8',
        'Accept':
            'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
      };

  /// GET one Akwam page as a decoded string.
  Future<String> _get(String path,
      {Duration timeout = const Duration(seconds: 18)}) async {
    final Uri uri = Uri.parse('$base$path');
    final http.Response res;
    try {
      res = await _client.get(uri, headers: _headers).timeout(timeout);
    } on TimeoutException {
      throw AkwamApiException('انتهت مهلة الطلب.');
    } catch (_) {
      throw AkwamApiException('تعذّر الوصول إلى أكوام.');
    }
    if (res.statusCode == 403 || res.statusCode == 503) {
      throw AkwamApiException('أكوام يحدّ من الطلبات حاليًا — حاول بعد قليل.');
    }
    if (res.statusCode >= 400) {
      throw AkwamApiException('أعاد أكوام الخطأ HTTP ${res.statusCode}.');
    }
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  // -------------------------------------------------------------------------
  // Catalogs + search
  // -------------------------------------------------------------------------

  /// Recently added across all sections.
  Future<List<AkwamItem>> recent({int page = 1}) =>
      _cards('/recent', page: page);

  /// Movie catalog.
  Future<List<AkwamItem>> movies({int page = 1}) =>
      _cards('/movies', page: page);

  /// Series catalog.
  Future<List<AkwamItem>> series({int page = 1}) =>
      _cards('/series', page: page);

  /// TV shows catalog.
  Future<List<AkwamItem>> shows({int page = 1}) =>
      _cards('/shows', page: page);

  /// Keyword search across movies and series.
  Future<List<AkwamItem>> search(String query, {int page = 1}) async {
    final String q = query.trim();
    if (q.isEmpty) return const <AkwamItem>[];
    return _cards(
        '/search?q=${Uri.encodeQueryComponent(q)}'
        '${page > 1 ? '&page=$page' : ''}',
        page: 1);
  }

  Future<List<AkwamItem>> _cards(String path, {required int page}) async {
    final String sep = path.contains('?') ? '&' : '?';
    final String html =
        await _get(page > 1 ? '$path${sep}page=$page' : path);
    return parseAkwamCards(html);
  }

  // -------------------------------------------------------------------------
  // Details
  // -------------------------------------------------------------------------

  /// Loads the item page and enriches [item]: synopsis, backdrop, year,
  /// genres, rating — plus the episode list for series/shows.
  Future<AkwamItem> details(AkwamItem item) async {
    final String html = await _get(item.path);
    return parseAkwamDetails(item, html);
  }

  /// Episode list for a series page (cached per item path).
  Future<List<AkwamEpisode>> episodesOf(AkwamItem item) async {
    final List<AkwamEpisode>? cached = _episodeCache[item.path];
    if (cached != null) return cached;
    final String html = await _get(item.path);
    final AkwamItem rich = parseAkwamDetails(item, html);
    return _episodeCache[item.path] ??=
        rich.episodes.isEmpty ? const <AkwamEpisode>[] : rich.episodes;
  }

  /// Watch sources for a movie (qualities on the movie page itself).
  Future<List<AkwamSource>> sourcesFor(AkwamItem item) async {
    final String html = await _get(item.path);
    return parseAkwamSources(html);
  }

  /// Watch sources for one episode (quality tabs on the episode page).
  Future<List<AkwamSource>> episodeSources(AkwamEpisode episode) async {
    final String html = await _get(episode.path);
    return parseAkwamSources(html);
  }

  /// Resolves a `/watch/{fileId}/…` page into the direct media URL.
  /// Results are cached per watch path.
  Future<String> resolveStream(String watchPath) async {
    final String cached = _watchCache[watchPath] ?? '';
    if (cached.isNotEmpty) return cached;
    final String html = await _get(watchPath);
    final String url = extractAkwamStreamUrl(html);
    if (url.isEmpty) {
      throw AkwamApiException(
          'لا يوجد بث قابل للتشغيل على هذا السيرفر — جرّب جودة أخرى.');
    }
    return _watchCache[watchPath] = url;
  }

  // -------------------------------------------------------------------------
  // Parsing (public so the test suite can run it against fixtures)
  // -------------------------------------------------------------------------

  /// Parses catalog / search result cards (`div.entry-box`).
  static List<AkwamItem> parseAkwamCards(String html) {
    final document = html_parser.parse(html);
    final List<AkwamItem> out = <AkwamItem>[];
    for (final box in document.querySelectorAll('div.entry-box')) {
      // Title + href: the entry-title anchor first, else the poster link.
      String title = '';
      String href = '';
      final anchor = box.querySelector('h3.entry-title a') ??
          box.querySelector('a.box');
      if (anchor != null) {
        title = anchor.text.trim();
        href = anchor.attributes['href'] ?? '';
      }
      if (href.isEmpty) {
        final posterLink = box.querySelector('a.box');
        if (posterLink != null) href = posterLink.attributes['href'] ?? '';
      }
      final AkwamItem? item = _itemFromHref(href, title);
      if (item == null) continue;

      // Poster (lazy-loaded via data-src).
      final img = box.querySelector('img');
      final String raw = img?.attributes['data-src'] ??
          img?.attributes['src'] ??
          '';
      if (raw.isNotEmpty && !raw.contains('placeholder')) {
        item.poster = raw.startsWith('http') ? raw : '$base$raw';
      }

      // Rating / quality labels.
      for (final label in box.querySelectorAll('span.label')) {
        final String text = label.text.trim();
        final Set<String> cls = label.classes;
        if (cls.contains('rating')) {
          item.rating = double.tryParse(text) ?? item.rating;
        } else if (cls.contains('quality') && text.isNotEmpty) {
          item.qualityLabel = text;
        }
      }

      // Badges: year (4-digit) + Arabic genre names.
      for (final badge in box.querySelectorAll('span.badge')) {
        final String text = badge.text.trim();
        if (text.isEmpty) continue;
        if (RegExp(r'^\d{4}$').hasMatch(text)) {
          item.year = text;
        } else if (!item.genres.contains(text)) {
          item.genres.add(text);
        }
      }
      out.add(item);
    }
    return out;
  }

  /// Parses an item page: synopsis / backdrop / meta + episode grid.
  static AkwamItem parseAkwamDetails(AkwamItem item, String html) {
    final document = html_parser.parse(html);
    final AkwamItem rich = AkwamItem(
      id: item.id,
      path: item.path,
      kind: item.kind,
      title: item.title,
    );
    rich.poster = item.poster;
    rich.qualityLabel = item.qualityLabel;
    rich.rating = item.rating;
    rich.year = item.year;
    rich.genres
      ..clear()
      ..addAll(item.genres);

    // og: meta first (always present, well-formed).
    for (final meta in document.querySelectorAll('meta[property]')) {
      final String prop = meta.attributes['property'] ?? '';
      final String content = (meta.attributes['content'] ?? '').trim();
      if (content.isEmpty) continue;
      if (prop == 'og:image' && rich.poster.isEmpty) rich.poster = content;
      if (prop == 'og:description') rich.synopsis = _clean(content);
      if (prop == 'og:title' && rich.title.isEmpty) {
        rich.title = content.replaceAll(RegExp(r'\s*\|\s*اكوام\s*$'), '');
      }
    }

    // Story block — the widget whose header reads "قصة الفيلم/المسلسل"
    // (longer and cleaner than og:description when present).
    for (final widget in document.querySelectorAll('div.widget')) {
      final header = widget.querySelector('.header-title');
      if (header == null || !header.text.contains('قصة')) continue;
      final body = widget.querySelector('.widget-body');
      if (body == null) continue;
      final String text = _clean(body.text.trim());
      if (text.length > rich.synopsis.length) rich.synopsis = text;
      break;
    }

    // Year + genres from the breadcrumb / meta row.
    final metaRow = document.querySelector('.widget-header .badges, .meta');
    if (metaRow != null) {
      for (final badge in metaRow.querySelectorAll('span.badge, a.badge')) {
        final String text = badge.text.trim();
        if (RegExp(r'^\d{4}$').hasMatch(text)) {
          rich.year = text;
        } else if (text.isNotEmpty && !rich.genres.contains(text)) {
          rich.genres.add(text);
        }
      }
    }

    // Episodes (series/shows pages): h2 anchors inside #series-episodes.
    final int epNumberBase = _episodeNumbers(rich);
    int index = 0;
    for (final anchor in document.querySelectorAll('a[href]')) {
      final String href = anchor.attributes['href'] ?? '';
      if (!href.contains('/episode/')) continue;
      final RegExpMatch? m =
          RegExp(r'/episode/(\d+)(?:/[^?#"]*)?').firstMatch(href);
      if (m == null) continue;
      final String label = anchor.text.trim();
      int number = int.tryParse(label.split(':').first
              .replaceAll(RegExp(r'[^0-9]'), '')) ??
          0;
      if (number <= 0) {
        // Fall back to the number embedded in the path (الحلقة-6).
        number = _numberFromPath(href);
      }
      if (number <= 0) {
        // Last resort: keep the page order (episodes ship newest-first).
        number = epNumberBase > 0 ? epNumberBase - index : index + 1;
      }
      final Uri? uri = Uri.tryParse(href);
      final String path = uri == null
          ? href
          : '${uri.path}${uri.query.isEmpty ? '' : '?${uri.query}'}';
      rich.episodes.add(AkwamEpisode(
        id: m.group(1)!,
        number: number,
        label: label.isEmpty ? 'الحلقة $number' : label,
        path: path,
        date: _entryDate(anchor),
      ));
      index++;
    }

    // Dedupe by id — prefer the anchor carrying a text label (episode cards
    // also hold text-less quick-link anchors to the same page). Sort
    // ascending, renumber any zero stragglers.
    final Map<String, AkwamEpisode> unique = <String, AkwamEpisode>{};
    for (final AkwamEpisode ep in rich.episodes) {
      final AkwamEpisode? kept = unique[ep.id];
      if (kept == null ||
          (kept.label.isEmpty && ep.label.isNotEmpty)) {
        unique[ep.id] = ep;
      }
    }
    final List<AkwamEpisode> eps = unique.values.toList()
      ..sort((AkwamEpisode a, AkwamEpisode b) => a.number.compareTo(b.number));
    for (int i = 0; i < eps.length; i++) {
      if (eps[i].number <= 0) {
        eps[i] = AkwamEpisode(
            id: eps[i].id,
            number: i + 1,
            label: eps[i].label,
            path: eps[i].path,
            date: eps[i].date);
      }
    }
    rich.episodes
      ..clear()
      ..addAll(eps);
    return rich;
  }

  /// Parses the quality tabs of a movie or episode page into watch sources.
  static List<AkwamSource> parseAkwamSources(String html) {
    final document = html_parser.parse(html);
    // Tab id → quality label (`ul.header-tabs li a[href=#tab-N]`).
    final Map<String, String> tabQuality = <String, String>{};
    for (final a in document.querySelectorAll('ul.header-tabs a')) {
      final String target = a.attributes['href'] ?? '';
      final String label = a.text.trim();
      if (target.startsWith('#') && label.isNotEmpty) {
        tabQuality[target.substring(1)] = label;
      }
    }

    final List<AkwamSource> out = <AkwamSource>[];
    for (final panel in document.querySelectorAll('div.tab-content.quality')) {
      final String panelId = panel.attributes['id'] ?? '';
      String quality = tabQuality[panelId] ?? '';
      if (quality.isEmpty) quality = panelId; // "tab-4" fallback label
      for (final a in panel.querySelectorAll('a.link-show')) {
        final String href = a.attributes['href'] ?? '';
        if (!href.contains('/watch/')) continue;
        // Size rides on the sibling download button.
        String size = '';
        final container = a.parent?.parent;
        if (container != null) {
          for (final dl in container.querySelectorAll('a.link-download')) {
            final RegExpMatch? m = RegExp(r'([\d.]+\s*[MG]B)').firstMatch(dl.text);
            if (m != null) size = m.group(1)!.trim();
          }
        }
        final Uri? uri = Uri.tryParse(href);
        out.add(AkwamSource(
          quality: quality,
          watchPath: uri == null
              ? href
              : '${uri.path}${uri.query.isEmpty ? '' : '?${uri.query}'}',
          size: size,
        ));
      }
    }

    // Dedupe identical watch paths, keep quality order.
    final Map<String, AkwamSource> unique = <String, AkwamSource>{};
    for (final AkwamSource s in out) {
      unique[s.watchPath] = s;
    }
    return unique.values.toList();
  }

  /// Extracts the direct stream URL (`*.mp4` / `*.m3u8`) from a watch page.
  static String extractAkwamStreamUrl(String html) {
    final RegExpMatch? m = RegExp(
      r'''https?://[^"'\s<>\\]+?\.(?:mp4|m3u8)(?:\?[^"'\s<>\\]*)?''',
    ).firstMatch(html);
    return m?.group(0) ?? '';
  }

  // ----- helpers -----

  static AkwamItem? _itemFromHref(String href, String fallbackTitle) {
    if (href.isEmpty) return null;
    final RegExpMatch? m = RegExp(
      r'/(movie|series|show)/(\d+)/([^"/?#]+)',
    ).firstMatch(href);
    if (m == null) return null;
    final Uri? uri = Uri.tryParse(href);
    return AkwamItem(
      id: m.group(2)!,
      path: uri == null
          ? (href.startsWith('/') ? href : '/$href')
          : '${uri.path}${uri.query.isEmpty ? '' : '?${uri.query}'}',
      kind: AkwamKindExt.fromSlug(m.group(1)!),
      title: fallbackTitle.isEmpty
          ? Uri.decodeComponent(m.group(3)!)
          : fallbackTitle,
    );
  }

  /// Highest episode number on the page (episodes ship newest-first).
  static int _episodeNumbers(AkwamItem item) {
    int max = 0;
    for (final AkwamEpisode ep in item.episodes) {
      if (ep.number > max) max = ep.number;
    }
    return max;
  }

  /// `…/الحلقة-6` → 6 (decodes the trailing path segment).
  static int _numberFromPath(String href) {
    try {
      final String path = Uri.tryParse(href)?.path ?? href;
      final List<String> parts = path.split('/')..removeWhere((String p) => p.isEmpty);
      for (final String part in parts.reversed) {
        final RegExpMatch? m =
            RegExp(r'(\d+)\s*$').firstMatch(Uri.decodeComponent(part));
        if (m != null) return int.tryParse(m.group(1)!) ?? 0;
      }
    } catch (_) {
      // Malformed escape sequences — ignore.
    }
    return 0;
  }

  /// `p.entry-date` text of the episode card the anchor belongs to.
  static String _entryDate(Element anchor) {
    Element? node = anchor;
    for (int depth = 0; depth < 4 && node != null; depth++) {
      if (node.localName == 'h2' || node.localName == 'h3') {
        final Element? card = node.parent;
        if (card == null) return '';
        final Element? date =
            card.nextElementSibling?.querySelector('p.entry-date') ??
                card.querySelector('p.entry-date');
        return date?.text.trim() ?? '';
      }
      node = node.parent;
    }
    return '';
  }

  /// Collapses whitespace and drops ad suffixes from scraped descriptions.
  static String _clean(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*على اكوام\.?\s*$'), '')
      .trim();
}

// =============================================================================
// Models
// =============================================================================

/// Content kinds Akwam hosts.
enum AkwamKind { movie, series, show }

extension AkwamKindExt on AkwamKind {
  String get slug {
    switch (this) {
      case AkwamKind.movie:
        return 'movie';
      case AkwamKind.series:
        return 'series';
      case AkwamKind.show:
        return 'show';
    }
  }

  static AkwamKind fromSlug(String s) {
    switch (s) {
      case 'movie':
        return AkwamKind.movie;
      case 'show':
        return AkwamKind.show;
      default:
        return AkwamKind.series;
    }
  }

  /// UI label.
  String get label {
    switch (this) {
      case AkwamKind.movie:
        return 'فيلم';
      case AkwamKind.series:
        return 'مسلسل';
      case AkwamKind.show:
        return 'برنامج';
    }
  }

  bool get isEpisodeBased => this != AkwamKind.movie;
}

/// One poster card / catalog entry.
class AkwamItem {
  AkwamItem({
    required this.id,
    required this.path,
    required this.kind,
    required this.title,
  });

  /// Numeric Akwam id (`11687`).
  final String id;

  /// Item page path (`/movie/11687/insidious-possession`) — used for all
  /// follow-up requests.
  final String path;
  AkwamKind kind;
  String title;

  String poster = '';
  String synopsis = '';
  String year = '';
  String qualityLabel = '';
  double rating = 0;
  List<String> genres = <String>[];
  List<AkwamEpisode> episodes = <AkwamEpisode>[];

  bool get isSeries => kind.isEpisodeBased;
  bool get hasEpisodes => episodes.isNotEmpty;
}

/// One episode of a series (`/episode/{id}/{slug}/الحلقة-N`).
class AkwamEpisode {
  const AkwamEpisode({
    required this.id,
    required this.number,
    required this.label,
    required this.path,
    this.date = '',
  });

  /// Episode-page id (`105419`).
  final String id;
  final int number;

  /// Site label (Arabic), e.g. `حلقة 6 : مسلسل …`.
  final String label;

  /// Episode page path — sources are parsed from it.
  final String path;

  /// Air-date text scraped from the episode card, when present.
  final String date;
}

/// One watchable quality of an episode / movie.
class AkwamSource {
  const AkwamSource({
    required this.quality,
    required this.watchPath,
    this.size = '',
  });

  /// Quality label from the site (`720p`, `1080p`, `BluRay`…).
  final String quality;

  /// `/watch/{fileId}/…` path — resolve via [AkwamApi.resolveStream].
  final String watchPath;

  /// File size text when the site shows it (`519.3 MB`).
  final String size;
}

/// Akwam section error with a user-presentable message.
class AkwamApiException implements Exception {
  const AkwamApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
