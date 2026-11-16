import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_http.dart';

/// EgyDead (egydead.ca) — the "EgyDead" section backend, reverse-engineered
/// from the user's HAR capture (2026-11-15) and the site's own JS bundle.
///
/// Live-verified chain (2026-11-16):
///  * Catalog   → `GET /api/v1/channel/{id}?restriction=&order=channelables.
///                created_at:desc&page={n}&paginate=lengthAware&
///                returnContentOnly=true` → `{pagination:{data:[…],next_page}}`
///  * Details   → `GET /api/v1/titles/{id}` → `{title:{…}}`
///  * Related   → `GET /api/v1/titles/{id}/related`
///  * Search    → `GET /api/v1/search/{query}?loader=searchPage`
///  * Watch     → `GET /api/v1/watch/{videoId}` → `{video:{src:"embed url"}}`
///  * Stream    → egybestvid.com embed page (NOT Cloudflare-protected, plain
///                nginx) carries `sources: [{file:"…master.m3u8?t=…"}]`.
///                HLS segments require `Referer: https://egybestvid.com/`.
///
/// Cloudflare: egydead.ca sits behind a managed challenge. Requests from
/// non-browser clients get 403 "Just a moment…". The app stores
/// `cf_clearance` cookies captured by the in-app WebView gate
/// ([EgyGateScreen]) and attaches them to every API call — see
/// [saveCookies]/[loadCookies]. When the challenge trips again the API
/// throws [EgyChallengeException] and the UI offers the gate again.
class EgyApi {
  EgyApi._();
  static final EgyApi I = EgyApi._();

  static const String base = 'https://egydead.ca';
  static const String apiBase = '$base/api/v1';

  /// Video host of the resolved streams (embed pages + HLS CDN).
  static const String vidBase = 'https://egybestvid.com';

  final http.Client _client = createHttpClient();

  /// Browser-mirrored UA — Cloudflare grades requests by UA + TLS.
  static const String ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  // -------------------------------------------------------------------------
  // Channel registry (ids mined from the homepage Inertia props, 2026-11-15)
  // -------------------------------------------------------------------------

  /// Rows shown on the EgyDead tab, in site order.
  static const List<({int id, String label})> channels = <({int id, String label})>[
    (id: 5381, label: 'Trending'),
    (id: 20721, label: 'Movies'),
    (id: 26365, label: 'Series'),
    (id: 17527, label: 'Action'),
    (id: 25845, label: 'Drama'),
    (id: 25737, label: 'Romance'),
    (id: 19191, label: 'Horror'),
    (id: 25651, label: 'War'),
    (id: 24538, label: 'Netflix'),
    (id: 25931, label: 'Sci-Fi'),
    (id: 23841, label: 'Fantasy'),
    (id: 2644, label: 'Adventure'),
    (id: 5382, label: 'Anime'),
    (id: 23472, label: 'Family'),
    (id: 1305, label: 'Asian'),
    (id: 901, label: 'Indian'),
    (id: 1274, label: 'Turkish Movies'),
    (id: 5375, label: 'Turkish Series'),
  ];

  // -------------------------------------------------------------------------
  // Cloudflare cookies
  // -------------------------------------------------------------------------

  static const String _cookieKey = 'egy_cf_cookies';

  /// `cf_clearance=…; PHPSESSID=…` captured by the WebView gate.
  String _cookies = '';
  DateTime _cookieAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// When the cookies were captured (for UI hints / refresh logic).
  DateTime get cookieCapturedAt => _cookieAt;

  bool get hasCookies => _cookies.trim().isNotEmpty;

  Future<void> loadCookies() async {
    if (_cookies.isNotEmpty) return; // already loaded in this session
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _cookies = prefs.getString(_cookieKey) ?? '';
      final int ms = prefs.getInt(_cookieKey + '_at') ?? 0;
      _cookieAt = DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      _cookies = '';
    }
  }

  /// Persists the cookie header captured by the WebView gate.
  Future<void> saveCookies(String cookieHeader) async {
    _cookies = cookieHeader.trim();
    _cookieAt = DateTime.now();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cookieKey, _cookies);
      await prefs.setInt(_cookieKey + '_at', _cookieAt.millisecondsSinceEpoch);
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // HTTP core
  // -------------------------------------------------------------------------

  Map<String, String> _headers({bool json = true}) => <String, String>{
        'User-Agent': ua,
        'Accept-Language': 'en-US,en;q=0.9,ar;q=0.8',
        if (json)
          'Accept': 'application/json, text/javascript, */*; q=0.01'
        else
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Referer': '$base/',
        'X-Requested-With': 'XMLHttpRequest',
        if (_cookies.isNotEmpty) 'Cookie': _cookies,
      };

  Future<http.Response> _get(Uri uri,
      {bool json = true,
      Duration timeout = const Duration(seconds: 15)}) async {
    final http.Response res = await _client
        .get(uri, headers: _headers(json: json))
        .timeout(timeout);
    if (res.statusCode == 403 ||
        res.statusCode == 503 ||
        res.body.startsWith('<!DOCTYPE html>')) {
      throw const EgyChallengeException();
    }
    return res;
  }

  /// Channel listing page. [EgyChallengeException] propagates so the tab can
  /// offer the WebView gate.
  Future<EgyPage> fetchChannel(int channelId, {int page = 1}) async {
    final Uri uri = Uri.parse('$apiBase/channel/$channelId').replace(
      queryParameters: <String, String>{
        'restriction': '',
        'order': 'channelables.created_at:desc',
        'page': '$page',
        'paginate': 'lengthAware',
        'returnContentOnly': 'true',
      },
    );
    final http.Response res = await _get(uri);
    final dynamic body = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    final List<EgyTitle> items = _parseTitleList(body);
    final int? nextPage = _readNextPage(body);
    return EgyPage(items: items, nextPage: nextPage);
  }

  /// Keyword search. Response shape not HAR-verified (endpoint confirmed from
  /// the site JS: `search/{query}?loader=searchPage`) — parsed defensively.
  Future<List<EgyTitle>> search(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return const <EgyTitle>[];
    final Uri uri = Uri.parse(
        '$apiBase/search/${Uri.encodeComponent(q)}')
        .replace(queryParameters: <String, String>{'loader': 'searchPage'});
    final http.Response res = await _get(uri);
    final dynamic body = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    return _parseTitleList(body);
  }

  /// Full title details (genres, images, primary video, seasons for series).
  Future<EgyTitle> fetchTitle(int id) async {
    final Uri uri = Uri.parse('$apiBase/titles/$id');
    final http.Response res = await _get(uri);
    final dynamic body = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    final dynamic t = body is Map
        ? (body['title'] ?? body['data']?['title'] ?? body['data'])
        : null;
    if (t is! Map) throw const EgyApiException('Unexpected title payload.');
    final EgyTitle title = EgyTitle.fromJson(Map<String, dynamic>.from(t));
    // Harvest extra fields the list payload lacks.
    if (body is Map && body['title'] is Map) {
      final Map<String, dynamic> tm = Map<String, dynamic>.from(body['title']);
      title.genres.addAll(_genreNames(tm));
      title.images
          .addAll(_imageUrls(tm));
    }
    return title;
  }

  /// Related titles row.
  Future<List<EgyTitle>> fetchRelated(int id) async {
    final Uri uri = Uri.parse('$apiBase/titles/$id/related');
    final http.Response res = await _get(uri);
    final dynamic body = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    return _parseTitleList(body);
  }

  /// Episodes of one season of a series. Shape parsed defensively (endpoint
  /// confirmed from the site JS: `titles/{id}/seasons/{n}`).
  Future<List<EgyEpisode>> fetchSeason(int titleId, int season) async {
    final Uri uri = Uri.parse('$apiBase/titles/$titleId/seasons/$season');
    final http.Response res = await _get(uri);
    final dynamic body = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    return _parseEpisodes(body);
  }

  /// Videos of one episode (site JS: `titles/{id}/seasons/{s}/episodes/{e}`).
  /// Used when the season listing does not embed the videos.
  Future<List<EgyVideo>> fetchEpisodeVideos(
      int titleId, int season, int episode) async {
    final Uri uri = Uri.parse(
        '$apiBase/titles/$titleId/seasons/$season/episodes/$episode');
    final http.Response res = await _get(uri);
    final dynamic body =
        jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (body is! Map) return const <EgyVideo>[];
    final Map<String, dynamic> m = Map<String, dynamic>.from(body);
    final List<EgyVideo> out = <EgyVideo>[];
    final List<dynamic> sources = <dynamic>[
      if (m['videos'] is List) ...(m['videos'] as List<dynamic>),
      if (m['episode'] is Map && m['episode']['videos'] is List)
        ...(m['episode']['videos'] as List<dynamic>),
      if (m['primary_video'] is Map) m['primary_video'],
    ];
    for (final dynamic v in sources) {
      if (v is Map) {
        out.add(EgyVideo.fromJson(Map<String, dynamic>.from(v)));
      }
    }
    return out;
  }

  /// Watch payload for one video: server list (`alternative_videos`) plus the
  /// selected video itself.
  Future<EgyWatch> fetchWatch(int videoId) async {
    final Uri uri = Uri.parse('$apiBase/watch/$videoId');
    final http.Response res = await _get(uri);
    final dynamic body = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (body is! Map) throw const EgyApiException('Unexpected watch payload.');
    final Map<String, dynamic> m = Map<String, dynamic>.from(body);
    final List<EgyVideo> alt = <EgyVideo>[];
    for (final dynamic v in (m['alternative_videos'] ?? const <dynamic>[])) {
      if (v is Map) alt.add(EgyVideo.fromJson(Map<String, dynamic>.from(v)));
    }
    EgyVideo? video;
    if (m['video'] is Map) {
      video = EgyVideo.fromJson(Map<String, dynamic>.from(m['video']));
    }
    return EgyWatch(video: video, alternatives: alt);
  }

  // -------------------------------------------------------------------------
  // Stream resolution (embed page → direct HLS)
  // -------------------------------------------------------------------------

  /// Resolves an [EgyVideo] into a direct playable stream.
  ///
  ///  * `src` already a media URL (`.mp4` / `.m3u8`) → used as-is.
  ///  * `src` an embed page → fetched (no Cloudflare on egybestvid.com) and
  ///    the jwplayer `sources: [{file:"…"}]` entry is extracted.
  Future<ResolvedStream?> resolveVideo(EgyVideo video) async {
    final String src = video.src.trim();
    if (src.isEmpty) return null;
    final Uri? parsed = Uri.tryParse(src);
    if (parsed == null || !parsed.hasScheme) return null;

    final String lower = parsed.path.toLowerCase();
    final bool direct =
        lower.endsWith('.m3u8') || lower.endsWith('.mp4') || video.type == 'direct';

    if (direct) {
      return ResolvedStream(
        url: src,
        qualities: <String, String>{'Auto': src},
        referer: parsed.host.contains('egybestvid') ? vidBase + '/' : '',
      );
    }

    // Embed page — plain nginx, but keep a Referer like the site's iframe.
    final http.Response res = await _client.get(parsed, headers: <String, String>{
      'User-Agent': ua,
      'Accept': 'text/html,*/*',
      'Referer': '$base/',
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) return null;
    final String html = utf8.decode(res.bodyBytes, allowMalformed: true);
    final String? file = extractEmbedFile(html);
    if (file == null) return null;
    // Some embeds emit relative paths (`file:"/hls/.../index.m3u8"`) —
    // resolve against the embed page or the player gets a broken URL.
    final Uri fileUri = parsed.resolve(file);
    return ResolvedStream(
      url: fileUri.toString(),
      qualities: <String, String>{'Auto': fileUri.toString()},
      referer: '$vidBase/',
    );
  }

  /// Pulls the first playable `file` URL out of a jwplayer embed page.
  ///
  /// Matches the live layout `sources: [{file:"…m3u8?t=…"}]` and common
  /// variants (single quotes, `sources:[…]`, standalone `file:"…"`,
  /// `<source src="…">`).
  static String? extractEmbedFile(String html) {
    final RegExp anyFile = RegExp(
      r'''file\s*:\s*["']([^"']+?\.(?:m3u8|mp4)[^"']*)["']''',
      caseSensitive: false,
    );
    final RegExpMatch? m = anyFile.firstMatch(html);
    if (m != null) return m.group(1)!.trim();

    final RegExp sourceTag = RegExp(
      r'''<source[^>]+src=["']([^"']+?\.(?:m3u8|mp4)[^"']*)["']''',
      caseSensitive: false,
    );
    final RegExpMatch? s = sourceTag.firstMatch(html);
    if (s != null) return s.group(1)!.trim();

    final RegExp plainUrl = RegExp(
      r'''https?://[^\s"'<>]+?\.m3u8\?[^\s"'<>]+''',
      caseSensitive: false,
    );
    final RegExpMatch? p = plainUrl.firstMatch(html);
    return p?.group(0);
  }

  // -------------------------------------------------------------------------
  // Payload parsing helpers
  // -------------------------------------------------------------------------

  /// Understands `pagination.data`, `data`, `results`, bare lists and
  /// `titles` — whichever the endpoint returned.
  List<EgyTitle> _parseTitleList(dynamic body) {
    List<dynamic> raw = const <dynamic>[];
    if (body is List) {
      raw = body;
    } else if (body is Map) {
      final dynamic pag = body['pagination'];
      if (pag is Map && pag['data'] is List) {
        raw = pag['data'] as List<dynamic>;
      } else if (body['data'] is List) {
        raw = body['data'] as List<dynamic>;
      } else if (body['results'] is List) {
        raw = body['results'] as List<dynamic>;
      } else if (body['titles'] is List) {
        raw = body['titles'] as List<dynamic>;
      } else if (body['data'] is Map && body['data']['data'] is List) {
        raw = body['data']['data'] as List<dynamic>;
      }
    }
    final List<EgyTitle> out = <EgyTitle>[];
    for (final dynamic item in raw) {
      if (item is Map) {
        out.add(EgyTitle.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return out;
  }

  int? _readNextPage(dynamic body) {
    if (body is Map) {
      final dynamic pag = body['pagination'] ?? body['data'];
      if (pag is Map) {
        final dynamic n = pag['next_page'];
        if (n is int) return n;
        if (n is String) return int.tryParse(n);
      }
    }
    return null;
  }

  /// Season payload → episodes. Handles `{episodes:[…]}`, `{data:[…]}`,
  /// `{season:{episodes:[…]}}` and bare lists.
  List<EgyEpisode> _parseEpisodes(dynamic body) {
    List<dynamic> raw = const <dynamic>[];
    if (body is List) {
      raw = body;
    } else if (body is Map) {
      if (body['episodes'] is List) {
        raw = body['episodes'] as List<dynamic>;
      } else if (body['season'] is Map &&
          body['season']['episodes'] is List) {
        raw = body['season']['episodes'] as List<dynamic>;
      } else if (body['data'] is List) {
        raw = body['data'] as List<dynamic>;
      } else if (body['data'] is Map && body['data']['episodes'] is List) {
        raw = body['data']['episodes'] as List<dynamic>;
      }
    }
    final List<EgyEpisode> out = <EgyEpisode>[];
    int fallbackNum = 1;
    for (final dynamic e in raw) {
      if (e is! Map) continue;
      final Map<String, dynamic> m = Map<String, dynamic>.from(e);
      final List<EgyVideo> vids = <EgyVideo>[];
      for (final dynamic v in (m['videos'] ?? const <dynamic>[])) {
        if (v is Map) vids.add(EgyVideo.fromJson(Map<String, dynamic>.from(v)));
      }
      final dynamic pv = m['primary_video'];
      if (pv is Map && vids.isEmpty) {
        vids.add(EgyVideo.fromJson(Map<String, dynamic>.from(pv)));
      }
      final int? num = _intOf(m['episode_num'] ?? m['number'] ?? m['episode']);
      out.add(EgyEpisode(
        number: num ?? fallbackNum++,
        name: (m['name'] ?? m['title'] ?? 'Episode $fallbackNum').toString(),
        videos: vids,
        thumbnail: (m['thumbnail'] ?? m['still'] ?? '').toString(),
      ));
    }
    return out;
  }

  static List<String> _genreNames(Map<String, dynamic> t) => <String>[
        for (final dynamic g in (t['genres'] ?? const <dynamic>[]))
          if (g is Map)
            (g['display_name'] ?? g['name'] ?? '').toString(),
      ];

  static List<String> _imageUrls(Map<String, dynamic> t) => <String>[
        for (final dynamic im in (t['images'] ?? const <dynamic>[]))
          if (im is Map && (im['url'] ?? '').toString().isNotEmpty)
            im['url'].toString(),
      ];

  static int? _intOf(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  // ---------------------------------------------------------------------------
  // Test bridges (expose the private parsers to the widget/unit tests)
  // ---------------------------------------------------------------------------

  /// @visibleForTesting
  List<EgyTitle> channelItemsForTest(dynamic body) => _parseTitleList(body);

  /// @visibleForTesting
  int? nextPageForTest(dynamic body) => _readNextPage(body);

  /// @visibleForTesting
  List<EgyEpisode> seasonForTest(dynamic body) => _parseEpisodes(body);
}


int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

// =============================================================================
// Models
// =============================================================================

/// One page of a channel listing.
class EgyPage {
  const EgyPage({required this.items, this.nextPage});
  final List<EgyTitle> items;
  final int? nextPage;
}

/// A movie or a series, in list or detail form.
class EgyTitle {
  EgyTitle({required this.id, required this.name});

  final int id;
  String name;

  String originalTitle = '';
  String description = '';
  String poster = '';
  String backdrop = '';
  String releaseDate = '';
  bool isSeries = false;
  double rating = 0;
  int runtime = 0;
  int year = 0;
  int views = 0;
  String certification = '';
  int seasonsCount = 0;
  List<String> genres = <String>[];
  List<String> images = <String>[];

  /// Video id for the default server (movies) — `primary_video.id`.
  int? primaryVideoId;

  bool get hasBackdrop => backdrop.isNotEmpty;
  String get yearLabel => year > 0 ? '$year' : '';

  static EgyTitle fromJson(Map<String, dynamic> j) {
    final EgyTitle t = EgyTitle(
      id: _asInt(j['id']) ?? 0,
      name: (j['name'] ?? '').toString(),
    );
    t.originalTitle = (j['original_title'] ?? '').toString();
    t.description = (j['description'] ?? '').toString();
    t.poster = (j['poster'] ?? '').toString();
    t.backdrop = (j['backdrop'] ?? '').toString();
    t.releaseDate = (j['release_date'] ?? '').toString();
    t.isSeries = j['is_series'] == true || j['is_series'] == 1;
    t.rating = _asDouble(j['rating']) ?? 0;
    t.runtime = _asInt(j['runtime']) ?? 0;
    t.views = _asInt(j['views']) ?? 0;
    t.certification = (j['certification'] ?? '').toString();
    t.seasonsCount = _asInt(j['seasons_count']) ?? 0;
    t.year = _asInt(j['year']) ?? _yearOf(t.releaseDate);
    if (t.year == 0) t.year = _yearOf(t.releaseDate);
    t.primaryVideoId = _asInt(
        (j['primary_video'] is Map ? j['primary_video']['id'] : null) ??
            j['primary_video_id']);
    final List<String> g = <String>[];
    for (final dynamic x in (j['genres'] ?? const <dynamic>[])) {
      if (x is Map) g.add((x['display_name'] ?? x['name'] ?? '').toString());
    }
    t.genres
      ..clear()
      ..addAll(g);
    final List<String> ims = <String>[];
    for (final dynamic im in (j['images'] ?? const <dynamic>[])) {
      if (im is Map) {
        final String u = (im['url'] ?? '').toString();
        if (u.isNotEmpty) ims.add(u);
      }
    }
    t.images
      ..clear()
      ..addAll(ims);
    return t;
  }

  static int _yearOf(String iso) {
    if (iso.length >= 4) return int.tryParse(iso.substring(0, 4)) ?? 0;
    return 0;
  }
}

/// One playable source (server) of a title/episode.
class EgyVideo {
  const EgyVideo({
    required this.id,
    required this.name,
    required this.src,
    required this.type,
    this.quality = '',
  });

  final int id;
  final String name;
  final String src;

  /// `embed` (egybestvid iframe) or `direct`.
  final String type;
  final String quality;

  static EgyVideo fromJson(Map<String, dynamic> j) => EgyVideo(
        id: _asInt(j['id']) ?? 0,
        name: (j['name'] ?? 'Server').toString(),
        src: (j['src'] ?? '').toString(),
        type: (j['type'] ?? 'embed').toString(),
        quality: (j['quality'] ?? '').toString(),
      );
}

/// One episode of a season.
class EgyEpisode {
  const EgyEpisode({
    required this.number,
    required this.name,
    this.videos = const <EgyVideo>[],
    this.thumbnail = '',
  });
  final int number;
  final String name;
  final List<EgyVideo> videos;
  final String thumbnail;
}

/// Watch endpoint payload.
class EgyWatch {
  const EgyWatch({this.video, this.alternatives = const <EgyVideo>[]});
  final EgyVideo? video;
  final List<EgyVideo> alternatives;

  /// All usable servers: selected one first, then the alternatives.
  List<EgyVideo> get servers => <EgyVideo>[
        if (video != null) video!,
        ...alternatives.where((EgyVideo v) => v.id != video?.id),
      ];
}

/// Direct stream handed to the player (mirrors core/stream_resolver.dart).
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    this.qualities = const <String, String>{},
    this.referer = '',
  });
  final String url;
  final Map<String, String> qualities;

  /// Referer the CDN expects — the player must send it on every request
  /// (manifest + segments): `403 Forbidden` without it (verified live).
  final String referer;

  bool get isHls => url.toLowerCase().contains('.m3u8');
}

// =============================================================================
// Exceptions
// =============================================================================

class EgyApiException implements Exception {
  const EgyApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cloudflare managed challenge hit — the WebView gate must be (re)solved.
class EgyChallengeException implements Exception {
  const EgyChallengeException();
  @override
  String toString() =>
      'egydead.ca requires verification (Cloudflare challenge).';
}
