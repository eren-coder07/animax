import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_http.dart';
import 'app_prefs.dart';

/// MangaDex client for the Comics section.
///
/// MangaDex (https://api.mangadex.org) is a free, open manga library — no
/// auth, no Cloudflare challenge for read-only endpoints, JSON over HTTPS.
/// Verified live (2026-11-17):
///  * Search/trending → `GET /manga?limit=…&includes[]=cover_art&order[followedCount]=desc`
///  * Tags            → `GET /manga/tag`
///  * Chapters        → `GET /manga/{id}/feed?translatedLanguage[]=en&order[chapter]=desc`
///  * Pages           → `GET /at-home/server/{chapterId}`
///                     → `{baseUrl}/data/{hash}/{file}` (or `/data-saver/`)
///
/// The API applies aggressive rate limiting, so every request goes through a
/// serial queue with inter-request spacing and a 429-aware retry.
class MangaApi {
  MangaApi._();
  static final MangaApi I = MangaApi._();

  static const String base = 'https://api.mangadex.org';
  static const String uploadsBase = 'https://uploads.mangadex.org';
  static const String ua = 'Animax/2.2.0 (Android; Flutter)';

  final http.Client _client = createHttpClient();

  // Serial request queue — keeps us far below the API's burst limits.
  final Future<void> _queueTail = Future<void>.value();
  Future<void> get _gate => _queueTail;

  static const Duration _spacing = Duration(milliseconds: 220);
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<dynamic> _getJson(String path, {int retries = 2}) async {
    await _gate;
    final DateTime now = DateTime.now();
    final Duration since = now.difference(_lastAt);
    if (since < _spacing) {
      await Future<void>.delayed(_spacing - since);
    }
    _lastAt = DateTime.now();

    final Uri uri = Uri.parse('$base$path');
    late http.Response res;
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        res = await _client
            .get(uri, headers: <String, String>{
              'User-Agent': ua,
              'Accept': 'application/json',
            })
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        if (attempt > retries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        continue;
      }
      if (res.statusCode == 429) {
        final int after =
            int.tryParse(res.headers['retry-after'] ?? '') ?? 2;
        if (attempt > retries + 1) {
          throw MangaApiException('MangaDex يحدّ من الطلبات حاليًا');
        }
        await Future<void>.delayed(Duration(seconds: after + 1));
        continue;
      }
      if (res.statusCode >= 500 && attempt <= retries) {
        await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
        continue;
      }
      if (res.statusCode != 200) {
        throw MangaApiException('أعاد المصدر الخطأ HTTP ${res.statusCode}.');
      }
      break;
    }
    return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  // ----------------------------------------------------------------- lists

  /// Popular titles (by followed count).
  Future<List<MangaItem>> popular({int limit = 24, int offset = 0}) =>
      _list(
        'order[followedCount]=desc',
        limit: limit,
        offset: offset,
      );

  /// Recently updated titles.
  Future<List<MangaItem>> latest({int limit = 24, int offset = 0}) => _list(
        'order[latestUploadedChapter]=desc',
        limit: limit,
        offset: offset,
      );

  /// Newest titles on the platform.
  Future<List<MangaItem>> newest({int limit = 24, int offset = 0}) => _list(
        'order[createdAt]=desc',
        limit: limit,
        offset: offset,
      );

  /// Highest rated titles.
  Future<List<MangaItem>> topRated({int limit = 24, int offset = 0}) =>
      _list('order[rating]=desc', limit: limit, offset: offset);

  /// Keyword search.
  Future<List<MangaItem>> search(String query, {int limit = 24}) async {
    final String q = query.trim();
    if (q.isEmpty) return const <MangaItem>[];
    return _list('title=${Uri.encodeComponent(q)}', limit: limit);
  }

  /// Browse with an included genre tag + sort order.
  Future<List<MangaItem>> browseByTag(String tagUuid,
      {int limit = 24, int offset = 0, String order = 'order[followedCount]=desc'}) {
    return _list('includedTags%5B%5D=$tagUuid', limit: limit, offset: offset);
  }

  Future<List<MangaItem>> _list(String query,
      {int limit = 24, int offset = 0}) async {
    final StringBuffer p = StringBuffer('/manga?limit=$limit&offset=$offset');
    p.write('&includes%5B%5D=cover_art');
    p.write('&contentRating%5B%5D=safe&contentRating%5B%5D=suggestive');
    p.write('&hasAvailableChapters=true');
    p.write('&availableTranslatedLanguage%5B%5D=${AppPrefs.I.mangaLanguage}');
    p.write('&$query');
    final dynamic body = await _getJson(p.toString());
    return parseItems(body);
  }

  /// Parses a /manga list/search payload (public for tests).
  List<MangaItem> parseItems(dynamic body) {
    final List<MangaItem> out = <MangaItem>[];
    if (body is! Map) return out;
    final dynamic data = body['data'];
    if (data is! List) return out;
    for (final dynamic d in data) {
      if (d is! Map) continue;
      try {
        out.add(MangaItem.fromJson(
            Map<String, dynamic>.from(d)));
      } catch (_) {
        // Skip malformed entries.
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ tags

  List<MangaTag>? _tagsCache;

  /// The full genre/tag list (cached after the first call).
  Future<List<MangaTag>> tags() async {
    final List<MangaTag>? cached = _tagsCache;
    if (cached != null) return cached;
    final dynamic body = await _getJson('/manga/tag?limit=100');
    final List<MangaTag> out = <MangaTag>[];
    if (body is Map && body['data'] is List) {
      for (final dynamic d in body['data'] as List<dynamic>) {
        if (d is! Map) continue;
        final String id = (d['id'] ?? '').toString();
        final dynamic attrs = d['attributes'];
        if (attrs is! Map || id.isEmpty) continue;
        final dynamic names = attrs['name'];
        String name = '';
        if (names is Map) {
          name = (names['en'] ??
                  (names.values.isEmpty ? '' : names.values.first))
              .toString();
        }
        if (name.isNotEmpty) out.add(MangaTag(id: id, name: name));
      }
    }
    _tagsCache = out;
    return out;
  }

  // --------------------------------------------------------------- details

  /// Full details for one title.
  Future<MangaItem> details(String id) async {
    final dynamic body = await _getJson(
        '/manga/${Uri.encodeComponent(id)}?includes%5B%5D=cover_art&includes%5B%5D=author&includes%5B%5D=artist');
    if (body is Map && body['data'] is Map) {
      return MangaItem.fromJson(
          Map<String, dynamic>.from(body['data'] as Map<dynamic, dynamic>),
          full: true);
    }
    throw const MangaApiException('استجابة غير متوقعة من MangaDex.');
  }

  // -------------------------------------------------------------- chapters

  /// Chapter list for a title (newest first), skipping external-only
  /// chapters (MangaPlus embeds that cannot be read in-app).
  /// Chapters in [language]; when that language has none, falls back to
  /// English (Arabic coverage on MangaDex is thin).
  Future<List<MangaChapter>> chapters(String id,
      {String language = 'ar', int limit = 200}) async {
    final List<MangaChapter> first =
        await _chaptersIn(id, language.isEmpty ? 'ar' : language, limit);
    if (first.isNotEmpty || language == 'en') return first;
    return _chaptersIn(id, 'en', limit);
  }

  Future<List<MangaChapter>> _chaptersIn(
      String id, String lang, int limit) async {
    final String p = '/manga/${Uri.encodeComponent(id)}/feed'
        '?translatedLanguage%5B%5D=${Uri.encodeComponent(lang)}'
        '&order%5Bchapter%5D=desc&order%5Bvolume%5D=desc'
        '&limit=$limit&includeEmptyPages=0&includeExternalUrl=0'
        '&contentRating%5B%5D=safe&contentRating%5B%5D=suggestive';
    final dynamic body = await _getJson(p);
    final List<MangaChapter> out = <MangaChapter>[];
    if (body is Map && body['data'] is List) {
      for (final dynamic d in body['data'] as List<dynamic>) {
        if (d is! Map) continue;
        try {
          out.add(MangaChapter.fromJson(
              Map<String, dynamic>.from(d)));
        } catch (_) {
          // Skip malformed chapters.
        }
      }
    }
    return out;
  }

  // ----------------------------------------------------------------- pages

  /// Resolves the page image URLs for a chapter.
  ///
  /// [dataSaver] picks the smaller compressed renders (reader setting).
  Future<List<String>> pages(String chapterId, {bool dataSaver = false}) async {
    final dynamic body = await _getJson(
        '/at-home/server/${Uri.encodeComponent(chapterId)}'
        '${dataSaver ? '?qualityMode=data-saver' : ''}');
    if (body is! Map) return const <String>[];
    final String host = (body['baseUrl'] ?? '').toString();
    final dynamic ch = body['chapter'];
    if (host.isEmpty || ch is! Map) return const <String>[];
    final String hash = (ch['hash'] ?? '').toString();
    final List<dynamic> files = (dataSaver
            ? ch['dataSaver'] ?? ch['data']
            : ch['data'] ?? ch['dataSaver']) as List<dynamic>? ??
        const <dynamic>[];
    final String dir = dataSaver ? 'data-saver' : 'data';
    return files
        .map((dynamic f) => '$host/$dir/$hash/${(f ?? '').toString()}')
        .toList(growable: false);
  }
}

class MangaApiException implements Exception {
  const MangaApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

// =============================================================================
// Models
// =============================================================================

/// A genre tag (uuid + display name).
class MangaTag {
  const MangaTag({required this.id, required this.name});
  final String id;
  final String name;
}

/// One manga title.
class MangaItem {
  MangaItem({required this.id, this.title = ''});

  final String id;
  String title = '';
  String cover = '';
  String description = '';
  String status = ''; // ongoing / completed / hiatus…
  String year = '';
  String contentRating = 'safe';
  int followedCount = 0;
  int rating = 0;
  int chapterCount = 0;
  String latestChapterAt = '';
  List<String> altTitles = <String>[];
  List<String> authors = <String>[];
  List<MangaTag> tags = <MangaTag>[];

  String get followedLabel {
    final int n = followedCount;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  static MangaItem fromJson(Map<String, dynamic> j, {bool full = false}) {
    final MangaItem m = MangaItem(id: (j['id'] ?? '').toString(), title: '');
    final dynamic attrs = j['attributes'];
    if (attrs is! Map) return m;
    final Map<String, dynamic> a = Map<String, dynamic>.from(attrs);

    // Titles: prefer the `en` main title, then an `en` alt title, then the
    // first main title, then the first alt title.
    final dynamic titles = a['title'];
    final dynamic alts = a['altTitles'];
    String? enAlt;
    if (alts is List) {
      for (final dynamic t in alts) {
        if (t is Map && t.isNotEmpty) {
          final String altEn = (t['en'] ?? '').toString();
          enAlt ??= altEn.isNotEmpty ? altEn : null;
          m.altTitles.add((t.values.first ?? '').toString());
        }
      }
    }
    if (titles is Map) {
      final String en = (titles['en'] ?? '').toString();
      m.title = en.isNotEmpty
          ? en
          : (enAlt ??
              (titles.values.isEmpty ? '' : titles.values.first) ??
              (m.altTitles.isNotEmpty ? m.altTitles.first : ''))
          .toString();
    } else {
      m.title = enAlt ?? (m.altTitles.isNotEmpty ? m.altTitles.first : '');
    }

    // Description: prefer en.
    final dynamic desc = a['description'];
    if (desc is Map) {
      m.description = (desc['en'] ??
              (desc.values.isEmpty ? '' : desc.values.first))
          .toString();
    }

    m.status = (a['status'] ?? '').toString();
    m.year = (a['year'] ?? '').toString();
    m.contentRating = (a['contentRating'] ?? 'safe').toString();
    m.followedCount = (a['followedCount'] as num?)?.toInt() ?? 0;
    m.chapterCount = (a['lastChapter'] as num?)?.toInt() ?? 0;
    final dynamic rating = a['rating'];
    if (rating is Map) {
      m.rating = ((rating['bayesian'] ?? rating['average'] ?? 0) as num)
              .toDouble()
              .round();
    }
    m.latestChapterAt = (a['latestUploadedChapter'] ?? a['updatedAt'] ?? '')
        .toString();

    // Tags.
    final dynamic t = a['tags'];
    if (t is List) {
      for (final dynamic x in t) {
        if (x is! Map) continue;
        final dynamic ta = x['attributes'];
        if (ta is! Map) continue;
        final dynamic names = ta['name'];
        String name = '';
        if (names is Map) {
          name = (names['en'] ?? (names.values.isEmpty ? '' : names.values.first))
              .toString();
        }
        if (name.isNotEmpty) {
          m.tags.add(MangaTag(id: (x['id'] ?? '').toString(), name: name));
        }
      }
    }

    // Relationships: cover art, author, artist.
    final dynamic rel = j['relationships'];
    if (rel is List) {
      for (final dynamic r in rel) {
        if (r is! Map) continue;
        final String rtype = (r['type'] ?? '').toString();
        final dynamic rattrs = r['attributes'];
        if (rtype == 'cover_art' && rattrs is Map) {
          final String file = (rattrs['fileName'] ?? '').toString();
          if (file.isNotEmpty) {
            m.cover =
                '${MangaApi.uploadsBase}/covers/${m.id}/$file.512.jpg';
          }
        }
        if ((rtype == 'author' || rtype == 'artist') && rattrs is Map) {
          final String name = (rattrs['name'] ?? '').toString();
          if (name.isNotEmpty && !m.authors.contains(name)) {
            m.authors.add(name);
          }
        }
      }
    }
    return m;
  }
}

/// One chapter of a manga.
class MangaChapter {
  MangaChapter({required this.id, this.title = ''});

  final String id;
  String title = '';
  String number = '';
  String volume = '';
  int pages = 0;
  String publishedAt = '';
  bool isUnavailable = false;

  String get displayTitle {
    final String t = title.trim();
    if (t.isNotEmpty) return t;
    return 'الفصل ${number.isEmpty ? '?' : number}';
  }

  String get chipLabel =>
      number.isEmpty ? 'فصل واحد' : 'فصل ${_trimNum(number)}';

  static String _trimNum(String n) {
    final double? d = double.tryParse(n);
    if (d == null) return n;
    return d == d.roundToDouble()
        ? d.toInt().toString()
        : d.toString();
  }

  static MangaChapter fromJson(Map<String, dynamic> j) {
    final dynamic attrs = j['attributes'];
    final MangaChapter c =
        MangaChapter(id: (j['id'] ?? '').toString());
    if (attrs is! Map) return c;
    final Map<String, dynamic> a = Map<String, dynamic>.from(attrs);
    c.title = (a['title'] ?? '').toString();
    c.number = (a['chapter'] ?? '').toString();
    c.volume = (a['volume'] ?? '').toString();
    c.pages = (a['pages'] as num?)?.toInt() ?? 0;
    c.publishedAt = (a['publishAt'] ?? a['readableAt'] ?? '').toString();
    c.isUnavailable = a['isUnavailable'] == true;
    return c;
  }
}
