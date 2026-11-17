import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:html/parser.dart' show parseFragment;
import 'package:http/http.dart' as http;

import 'app_http.dart';

/// Models + HTTP client for HentaiHaven (hentaihaven.xxx) — the "+18" section
/// backend, reverse-engineered from the user's HAR capture ("henapi") and
/// live-verified.
///
/// Contract (all endpoints confirmed answering 200):
///  * Catalog / search / genres  → WordPress REST at cms.hentaihaven.xxx
///    `/wp-json/wp/v2/wp-manga?search=|orderby=|wp-manga-genre=` with
///    X-WP-Total / X-WP-TotalPages pagination headers.
///  * Trending                   → /browse/trending/ page whose RSC payload
///    embeds the same post objects plus an engagement map (rating + views).
///  * Episode list               → /watch/{slug}/ HTML episode cards.
///  * Stream                     → /watch/{slug}/episode-{n}/ embeds the
///    direct HLS playlist in `<source data-hhaven-indexable-source … src>` —
///    plays with ExoPlayer, no Referer required (verified).
///  * Images                     → https://img.hentaihaven.xxx/ + relative
///    `meta.vraven_remote_thumbnail` path (absolute URLs pass through).
class HentaiApi {
  HentaiApi._();
  static final HentaiApi I = HentaiApi._();

  static const String frontBase = 'https://hentaihaven.xxx';
  static const String cmsBase = 'https://cms.hentaihaven.xxx';
  static const String imgBase = 'https://img.hentaihaven.xxx/';
  static const String _wp = '$cmsBase/wp-json/wp/v2';

  final http.Client _client = createHttpClient();

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  Map<String, String> _headers({bool json = true, bool document = false}) =>
      <String, String>{
        'User-Agent': _ua,
        'Accept-Language': 'en-US,en;q=0.9',
        // Chrome-on-Android client hints — completes the browser disguise.
        'sec-ch-ua':
            '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
        'sec-ch-ua-mobile': '?1',
        'sec-ch-ua-platform': '"Android"',
        if (document) ...<String, String>{
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/'
              'avif,image/webp,image/apng,*/*;q=0.8',
          'Sec-Fetch-Dest': 'document',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'none',
          'Sec-Fetch-User': '?1',
          'Upgrade-Insecure-Requests': '1',
        } else ...<String, String>{
          if (json)
            'Accept': 'application/json, text/javascript, */*; q=0.01'
          else
            'Accept': '*/*',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'same-origin',
        },
        'Referer': '$frontBase/',
      };

  // =========================================================================
  // Models
  // =========================================================================

  /// Resolves a relative CMS thumbnail path to the image CDN, leaving
  /// absolute URLs untouched.
  static String thumbUrl(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return '';
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return imgBase + (t.startsWith('/') ? t.substring(1) : t);
  }

  static String stripTags(String html) =>
      parseFragment(html).text?.trim() ?? html;

  static String decodeEntities(String s) =>
      parseFragment(s).text?.trim() ?? s;

  /// 2924200 → "2.9M", 423856 → "423.8K".
  static String formatViews(int n) {
    if (n >= 1000000) {
      final double v = n / 1000000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}M';
    }
    if (n >= 1000) {
      final double v = n / 1000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}K';
    }
    return '$n';
  }

  static int? _intOf(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? _doubleOf(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // =========================================================================
  // Core HTTP
  // =========================================================================

  Future<http.Response> _get(Uri uri,
      {bool json = true,
      bool document = false,
      Duration timeout = const Duration(seconds: 14)}) {
    return _client
        .get(uri, headers: _headers(json: json, document: document))
        .timeout(timeout);
  }

  ApiException _fail(Object e, [Uri? uri]) {
    if (e is ApiException) {
      // Cloudflare bot challenge — explain instead of a bare status code.
      if (e.statusCode == 403) {
        return ApiException(
            'The source is protected right now (bot check). '
            'Try again in a minute.');
      }
      return e;
    }
    if (e is http.ClientException || e is TimeoutException || e is SocketException) {
      return ApiException('Cannot reach the source — check your connection.');
    }
    return ApiException('The source is unavailable right now.');
  }

  // =========================================================================
  // WordPress REST catalog
  // =========================================================================

  /// One page of series from the WP REST API.
  /// [orderby]: `modified` (recently updated), `date` (newest), `title`.
  Future<List<HhSeries>> fetchList({
    String orderby = 'modified',
    int page = 1,
    int perPage = 24,
    int? genreId,
    String? search,
  }) async {
    final Map<String, String> q = <String, String>{
      'per_page': '$perPage',
      'page': '$page',
      'orderby': orderby,
    };
    if (genreId != null) q['wp-manga-genre'] = '$genreId';
    if (search != null && search.trim().isNotEmpty) {
      q['search'] = search.trim();
    }
    final Uri uri = Uri.parse('$_wp/wp-manga').replace(queryParameters: q);
    try {
      final http.Response res = await _get(uri);
      if (res.statusCode == 400 && (genreId != null || (page > 1))) {
        // WP returns 400 "rest_post_invalid_page_number" past the last page.
        if (res.body.contains('rest_post_invalid_page_number')) {
          return const <HhSeries>[];
        }
      }
      if (res.statusCode != 200) {
        throw ApiException('The source returned HTTP ${res.statusCode}.',
            statusCode: res.statusCode);
      }
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List) return const <HhSeries>[];
      final Map<int, String> genreNames = await _genreMap();
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> j) =>
              HhSeries.fromRestJson(j, genreNames))
          .toList();
    } catch (e) {
      throw _fail(e, uri);
    }
  }

  /// Keyword search with totals. Returns a [HhSearchResult] so the search
  /// screen can paginate ("Load more").
  Future<HhSearchResult> search(String query, {int page = 1}) async {
    final Uri uri = Uri.parse('$_wp/wp-manga').replace(queryParameters: <String, String>{
      'search': query.trim(),
      'per_page': '24',
      'page': '$page',
    });
    try {
      final http.Response res = await _get(uri);
      if (res.body.contains('rest_post_invalid_page_number')) {
        return const HhSearchResult(<HhSeries>[], 0);
      }
      if (res.statusCode != 200) {
        throw ApiException('Search is unavailable right now.',
            statusCode: res.statusCode);
      }
      final Map<int, String> genreNames = await _genreMap();
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final List<HhSeries> items = decoded is List
          ? decoded
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> j) =>
                  HhSeries.fromRestJson(j, genreNames))
              .toList()
          : const <HhSeries>[];
      final int total =
          _intOf(res.headers['x-wp-total']) ?? items.length;
      return HhSearchResult(items, total);
    } catch (e) {
      throw _fail(e, uri);
    }
  }

  Future<List<HhSeries>> byGenre(int genreId, {int page = 1}) =>
      fetchList(genreId: genreId, page: page);

  /// Genre taxonomy (id → name map cache + public list for the chip cloud).
  List<HhGenre> _genreCache = const <HhGenre>[];
  DateTime _genreFetchedAt = DateTime(0);

  Future<List<HhGenre>> genres({bool force = false}) async {
    if (!force && _genreCache.isNotEmpty) return _genreCache;
    final Uri uri = Uri.parse(
        '$_wp/wp-manga-genre?per_page=100&orderby=count&order=desc&hide_empty=true');
    try {
      final http.Response res = await _get(uri);
      if (res.statusCode != 200) return _genreCache;
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is List) {
        _genreCache = decoded
            .whereType<Map<String, dynamic>>()
            .map(HhGenre.fromJson)
            .toList(growable: false);
        _genreFetchedAt = DateTime.now();
      }
    } catch (_) {
      // Cached (possibly empty) list is returned; callers show empty states.
    }
    return _genreCache;
  }

  bool get genresFresh =>
      DateTime.now().difference(_genreFetchedAt).inHours < 24;

  Future<Map<int, String>> _genreMap() async {
    final List<HhGenre> list = await genres();
    return <int, String>{
      for (final HhGenre g in list) g.id: g.name,
    };
  }

  // =========================================================================
  // Trending (frontend page with embedded RSC post array + engagement)
  // =========================================================================

  /// Trending this month. The /browse/trending/ page ships the ranked list
  /// as a JSON post array inside its RSC payload plus an engagement map.
  Future<List<HhSeries>> trending() async {
    final Uri uri = Uri.parse('$frontBase/browse/trending/');
    try {
      final http.Response res = await _get(uri, json: false, document: true);
      if (res.statusCode != 200) {
        throw ApiException('The source returned HTTP ${res.statusCode}.',
            statusCode: res.statusCode);
      }
      final String body = utf8.decode(res.bodyBytes);
      // The RSC payload stores its JSON as an escaped JS string.
      final String flat = body.replaceAll(r'\"', '"');
      final List<Map<String, dynamic>> posts = extractPostArray(flat);
      if (posts.isEmpty) {
        throw ApiException('Trending list unavailable right now.');
      }
      final Map<int, ({double rating, int views})> engagement =
          extractEngagement(flat);
      final Map<int, String> genreNames = await _genreMap();
      return posts
          .map((Map<String, dynamic> j) {
            final HhSeries s = HhSeries.fromRestJson(j, genreNames);
            final ({double rating, int views})? eng = engagement[s.id];
            return (eng == null)
                ? s
                : HhSeries(
                    id: s.id,
                    slug: s.slug,
                    title: s.title,
                    thumb: s.thumb,
                    synopsis: s.synopsis,
                    genres: s.genres,
                    rating: eng.rating,
                    views: eng.views,
                    date: s.date,
                  );
          })
          .toList(growable: false);
    } catch (e) {
      throw _fail(e, uri);
    }
  }

  /// Finds the first `[{"id":…,"date":…,"slug":…}]` array in the (already
  /// un-escaped) RSC payload and JSON-decodes it with a bracket walk.
  static List<Map<String, dynamic>> extractPostArray(String flat) {
    int from = 0;
    while (true) {
      final int start = flat.indexOf('[{"id":', from);
      if (start < 0) return const <Map<String, dynamic>>[];
      // Posts carry "date" + "slug"; genre taxonomy arrays don't.
      final String probe = flat.substring(
          start, (start + 300).clamp(0, flat.length));
      if (probe.contains('"slug":') && probe.contains('"date":')) {
        final int end = _matchingBracket(flat, start);
        if (end > start) {
          try {
            final dynamic decoded = jsonDecode(flat.substring(start, end + 1));
            if (decoded is List) {
              return decoded
                  .whereType<Map<String, dynamic>>()
                  .toList(growable: false);
            }
          } catch (_) {
            // Fall through and try the next candidate.
          }
        }
      }
      from = start + 1;
    }
  }

  /// Engagement map: `{"98923":{"rating":4.6,"views":273815,…}, …}`.
  static Map<int, ({double rating, int views})> extractEngagement(String flat) {
    final RegExp re = RegExp(
        r'"(\d{4,7})":\{"rating":([\d.]+),"views":(\d+),"favorites":\d+');
    final Map<int, ({double rating, int views})> out =
        <int, ({double rating, int views})>{};
    for (final RegExpMatch m in re.allMatches(flat)) {
      final int? id = _intOf(m.group(1));
      final double? rating = _doubleOf(m.group(2));
      final int? views = _intOf(m.group(3));
      if (id != null && rating != null && views != null) {
        out[id] = (rating: rating, views: views);
      }
    }
    return out;
  }

  /// Index of the bracket/parenthesis matching the one at [start].
  static int _matchingBracket(String s, int start) {
    int depth = 0;
    bool inStr = false;
    for (int i = start; i < s.length; i++) {
      final String ch = s[i];
      if (inStr) {
        if (ch == r'\') {
          i++;
        } else if (ch == '"') {
          inStr = false;
        }
      } else if (ch == '"') {
        inStr = true;
      } else if (ch == '[' || ch == '{') {
        depth++;
      } else if (ch == ']' || ch == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  // =========================================================================
  // Series details + episodes (frontend pages)
  // =========================================================================

  /// Full metadata for one series via the REST API (`?slug=`).
  Future<HhSeries> seriesBySlug(String slug) async {
    final Uri uri =
        Uri.parse('$_wp/wp-manga?slug=$slug');
    try {
      final http.Response res = await _get(uri);
      if (res.statusCode != 200) {
        throw ApiException('The source returned HTTP ${res.statusCode}.',
            statusCode: res.statusCode);
      }
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List || decoded.isEmpty) {
        throw ApiException('Series not found.');
      }
      final Map<int, String> genreNames = await _genreMap();
      return HhSeries.fromRestJson(
          decoded.first as Map<String, dynamic>, genreNames);
    } catch (e) {
      throw _fail(e, uri);
    }
  }

  /// Episode list parsed from the series page's episode cards
  /// (`/watch/{slug}/episode-N/` + coverlanyvd thumbnails).
  /// Newest-first on the site — returned oldest-first for the player.
  Future<List<HhEpisode>> episodes(String slug) async {
    final Uri uri = Uri.parse('$frontBase/watch/$slug/');
    try {
      final http.Response res = await _get(uri, json: false, document: true);
      if (res.statusCode != 200) {
        throw ApiException('The source returned HTTP ${res.statusCode}.',
            statusCode: res.statusCode);
      }
      final List<HhEpisode> eps = parseEpisodeCards(utf8.decode(res.bodyBytes), slug);
      if (eps.isEmpty) throw ApiException('No episodes found.');
      // Site lists newest first; the app plays oldest first.
      return eps.reversed.toList(growable: false);
    } catch (e) {
      throw _fail(e, uri);
    }
  }

  /// Splits the page on the episode-card marker and pulls out
  /// (episode number, thumbnail) pairs.
  static List<HhEpisode> parseEpisodeCards(String html, String slug) {
    final List<HhEpisode> out = <HhEpisode>[];
    final RegExp cardRe = RegExp(
        r'href="/watch/[a-z0-9-]+/(episode-(\d+))/">.*?src="([^"]+)"',
        dotAll: true,
        multiLine: false);
    final Set<int> seen = <int>{};
    for (final RegExpMatch m in cardRe.allMatches(html)) {
      final int? n = _intOf(m.group(2));
      if (n == null || !seen.add(n)) continue;
      out.add(HhEpisode(
        number: n,
        thumb: thumbUrl(m.group(3) ?? ''),
      ));
    }
    // Fallback when cards ship without thumbnails.
    if (out.isEmpty) {
      final RegExp hrefRe = RegExp('/watch/$slug/(episode-(\\d+))/');
      for (final RegExpMatch m in hrefRe.allMatches(html)) {
        final int? n = _intOf(m.group(2));
        if (n == null || !seen.add(n)) continue;
        out.add(HhEpisode(number: n, thumb: ''));
      }
    }
    return out;
  }

  // =========================================================================
  // Stream resolution
  // =========================================================================

  /// Resolves the direct HLS playlist for one episode from the episode
  /// page's own `<source data-hhaven-indexable-source>` tag.
  Future<HhStream> resolveStream(String slug, int episode) async {
    final Uri uri = Uri.parse('$frontBase/watch/$slug/episode-$episode/');
    try {
      final http.Response res = await _get(uri, json: false, document: true);
      if (res.statusCode != 200) {
        throw ApiException('This episode is unavailable right now.',
            statusCode: res.statusCode);
      }
      final HhStream? s =
          parseStream(utf8.decode(res.bodyBytes), slug, episode);
      if (s == null) {
        throw ApiException(
            'Stream unavailable (episode $episode may have been removed).');
      }
      return s;
    } catch (e) {
      throw _fail(e, uri);
    }
  }

  /// Pure extractor — also exercised by unit tests.
  static HhStream? parseStream(String html, String slug, int episode) {
    String? url;
    // 1) The player markup's indexable source (primary path).
    final RegExpMatch? m = RegExp(
            r'data-hhaven-indexable-source="true"[^>]*src="([^"]+)"')
        .firstMatch(html);
    if (m != null) url = decodeEntities(m.group(1)!);
    // 2) JSON-LD contentUrl fallback.
    if (url == null) {
      final RegExpMatch? ld =
          RegExp(r'"contentUrl":"([^"]+)"').firstMatch(html);
      if (ld != null) url = decodeEntities(ld.group(1)!);
    }
    if (url == null || !url.startsWith('http')) return null;
    // Poster + duration + title from the RSC payload / JSON-LD.
    String poster = '';
    final RegExpMatch? pm =
        RegExp(r'\\"poster\\":\\"([^"\\]+)\\"').firstMatch(html);
    if (pm != null) {
      poster = thumbUrl(pm.group(1)!);
    } else {
      final RegExpMatch? pm2 =
          RegExp(r'"contentUrl":"[^"]+".{0,400}?"thumbnailUrl"')
              .firstMatch(html);
      poster = '';
      pm2?.group(0);
    }
    final RegExpMatch? dm = RegExp(r'"duration":"(PT[^"]+)"').firstMatch(html);
    final String title = 'Episode $episode';
    return HhStream(
      url: url,
      poster: poster,
      isHls: url.contains('.m3u8'),
      durationMs: _isoDurationMs(dm?.group(1)),
      title: title,
    );
  }

  /// `PT15M40S` → milliseconds.
  static int _isoDurationMs(String? iso) {
    if (iso == null) return 0;
    final RegExpMatch? m = RegExp(
            r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$')
        .firstMatch(iso);
    if (m == null) return 0;
    final int h = _intOf(m.group(1)) ?? 0;
    final int min = _intOf(m.group(2)) ?? 0;
    final double sec = double.tryParse(m.group(3) ?? '0') ?? 0;
    return ((h * 3600 + min * 60 + sec) * 1000).round();
  }

  void dispose() => _client.close();
}

// =============================================================================
// Models
// =============================================================================

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode = 0});
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

/// A hentai series (WordPress `wp-manga` post).
class HhSeries {
  const HhSeries({
    required this.id,
    required this.slug,
    required this.title,
    required this.thumb,
    this.synopsis = '',
    this.genres = const <String>[],
    this.rating = 0,
    this.views = 0,
    this.date = '',
  });

  final int id;
  final String slug;
  final String title;

  /// Absolute image URL (img CDN or episode cover CDN).
  final String thumb;
  final String synopsis;
  final List<String> genres;
  final double rating;
  final int views;
  final String date;

  String get viewsLabel =>
      views > 0 ? HentaiApi.formatViews(views) : '';

  String get year => date.length >= 4 ? date.substring(0, 4) : '';

  /// WordPress REST post shape (also used for the RSC page payloads).
  factory HhSeries.fromRestJson(
      Map<String, dynamic> j, Map<int, String> genreNames) {
    final String thumbRel = ((j['meta'] as Map<String, dynamic>?) ??
            const <String, dynamic>{})['vraven_remote_thumbnail'] as String? ??
        '';
    final String title = HentaiApi.decodeEntities(
        ((j['title'] as Map<String, dynamic>?) ??
                const <String, dynamic>{})['rendered'] as String? ??
            '');
    final List<String> genres = <String>[];
    final dynamic genreIds = j['wp-manga-genre'];
    if (genreIds is List) {
      for (final dynamic g in genreIds) {
        final int? gid = HentaiApi._intOf(g);
        final String? name = gid != null ? genreNames[gid] : null;
        if (name != null && name.isNotEmpty) genres.add(name);
      }
    }
    if (genres.isEmpty) {
      // Fallback: slugs embedded in class_list (`wp-manga-genre-bbw`).
      final dynamic classes = j['class_list'];
      if (classes is List) {
        for (final dynamic c in classes) {
          final String s = c.toString();
          if (s.startsWith('wp-manga-genre-')) {
            final String slug = s.substring('wp-manga-genre-'.length);
            if (slug.isNotEmpty) genres.add(prettifySlug(slug));
          }
        }
      }
    }
    String synopsis = '';
    final dynamic content = j['content'];
    if (content is Map<String, dynamic>) {
      synopsis = _trimSynopsis(
          HentaiApi.stripTags(content['rendered']?.toString() ?? ''));
    }
    if (synopsis.isEmpty) {
      // Yoast description fallback (escaped RSC payloads carry \u0026 etc).
      final dynamic yoast = j['yoast_head_json'];
      if (yoast is Map<String, dynamic>) {
        synopsis = _trimSynopsis(yoast['description']?.toString() ?? '');
      }
    }
    return HhSeries(
      id: HentaiApi._intOf(j['id']) ?? 0,
      slug: j['slug']?.toString() ?? '',
      title: title,
      thumb: HentaiApi.thumbUrl(thumbRel),
      synopsis: synopsis,
      genres: genres,
      date: j['date']?.toString() ?? '',
    );
  }

  static String _trimSynopsis(String s) {
    final String t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 320) return t;
    return '${t.substring(0, 318)}…';
  }

  /// `mouse-cursor-de-genjitsu…` → prettified display fallback.
  static String prettifySlug(String slug) {
    const Map<String, String> fixes = <String, String>{
      'bbw': 'BBW',
      '3d-hentai': '3D Hentai',
      '3d': '3D',
      'hd': 'HD',
      'vr': 'VR',
      'milf': 'MILF',
      'ntr': 'NTR',
      'cg': 'CG',
    };
    return fixes[slug] ??
        slug
            .split('-')
            .map((String w) => w.isEmpty
                ? w
                : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
  }
}

/// One episode of a series.
class HhEpisode {
  const HhEpisode({required this.number, this.thumb = ''});
  final int number;
  final String thumb;

  String get title => 'Episode $number';
}

/// Resolved direct stream for an episode.
class HhStream {
  const HhStream({
    required this.url,
    required this.poster,
    required this.isHls,
    required this.durationMs,
    required this.title,
  });

  final String url;
  final String poster;
  final bool isHls;
  final int durationMs;
  final String title;
}

/// Search result page with server-side totals.
class HhSearchResult {
  const HhSearchResult(this.items, this.total);
  final List<HhSeries> items;
  final int total;
}

/// Genre taxonomy term.
class HhGenre {
  const HhGenre({required this.id, required this.name, required this.count});
  final int id;
  final String name;
  final int count;

  factory HhGenre.fromJson(Map<String, dynamic> j) => HhGenre(
        id: HentaiApi._intOf(j['id']) ?? 0,
        name: HentaiApi.decodeEntities(j['name']?.toString() ?? ''),
        count: HentaiApi._intOf(j['count']) ?? 0,
      );
}
