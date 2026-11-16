import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_http.dart';

/// Cinemeta — the "Cinema" section backend (Stremio's official public
/// catalog addon, https://github.com/Stremio/stremio-cinemeta).
///
/// Live-verified (2026-11-16):
///  * Catalog  → `GET /catalog/movie/top.json`,
///               `/catalog/series/popular.json`,
///               `/catalog/movie/trending.json`,
///               pagination via `&skip=N`, extras as extra path segment:
///               `/catalog/movie/top/genre=Action.json`,
///               `/catalog/movie/top/search=dune.json`
///  * Meta     → `GET /meta/movie/tt0137523.json`,
///               `/meta/series/tt0903747.json`
///               (series meta carries `videos:[{season,number,name,…}]`)
///
/// No Cloudflare, no auth, plain JSON — all requests are direct GETs.
///
/// Playback: Cinemeta is a metadata source; streams are played through the
/// multi-server embed player (vidsrc.sh family, IMDb id based) inside
/// [CinemaPlayerScreen]'s WebView. That player ships its own subtitle system
/// (OpenSubtitles auto-match) and bandwidth-adaptive quality selection.
class CinemaApi {
  CinemaApi._();
  static final CinemaApi I = CinemaApi._();

  static const String base = 'https://v3-cinemeta.strem.io';

  final http.Client _client = createHttpClient();

  static const String ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  Map<String, String> get _headers => <String, String>{
        'User-Agent': ua,
        'Accept': 'application/json',
      };

  Future<dynamic> _getJson(String path,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final Uri uri = Uri.parse('$base$path');
    final http.Response res = await _client
        .get(uri, headers: _headers)
        .timeout(timeout);
    if (res.statusCode != 200) {
      throw CinemaApiException('HTTP ${res.statusCode} for $path');
    }
    return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  // -------------------------------------------------------------------------
  // Catalogs
  // -------------------------------------------------------------------------

  /// Trending movies (site home row).
  Future<List<CinemaItem>> trendingMovies({int skip = 0}) =>
      _catalog('movie', 'trending', skip: skip);

  /// Popular series.
  Future<List<CinemaItem>> popularSeries({int skip = 0}) =>
      _catalog('series', 'popular', skip: skip);

  /// Top-rated movies.
  Future<List<CinemaItem>> topMovies({int skip = 0}) =>
      _catalog('movie', 'top', skip: skip);

  /// Top-rated series.
  Future<List<CinemaItem>> topSeries({int skip = 0}) =>
      _catalog('series', 'top', skip: skip);

  /// Latest movies for a release year (row "New in {year}").
  Future<List<CinemaItem>> moviesByYear(int year, {int skip = 0}) =>
      _catalog('movie', 'year', extra: 'year=$year', skip: skip);

  /// Catalog filtered by genre.
  Future<List<CinemaItem>> byGenre(String type, String genre, {int skip = 0}) =>
      _catalog(type, 'top', extra: 'genre=$genre', skip: skip);

  /// IMDb-rank catalog filtered by genre (Cartoons section "Best rated").
  Future<List<CinemaItem>> ratingByGenre(String type, String genre,
          {int skip = 0}) =>
      _catalog(type, 'imdbRating', extra: 'genre=$genre', skip: skip);

  /// Keyword search across movies and series (returns merged results).
  Future<List<CinemaItem>> search(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return const <CinemaItem>[];
    final String enc = Uri.encodeComponent(q);
    final List<CinemaItem> out = <CinemaItem>[];
    final List<Future<List<CinemaItem>>> jobs = <Future<List<CinemaItem>>>[
      _catalog('movie', 'top', extra: 'search=$enc'),
      _catalog('series', 'top', extra: 'search=$enc'),
    ];
    final List<List<CinemaItem>> lists = await Future.wait(jobs);
    // Interleave movie/series results so both types show up early.
    final int maxLen = lists
        .map((List<CinemaItem> l) => l.length)
        .fold(0, (int a, int b) => a > b ? a : b);
    for (int i = 0; i < maxLen; i++) {
      for (final List<CinemaItem> l in lists) {
        if (i < l.length) out.add(l[i]);
      }
    }
    return out;
  }

  Future<List<CinemaItem>> _catalog(String type, String catalog,
      {String? extra, int skip = 0}) async {
    // Extras ride in the path (Stremio addon protocol), e.g.
    // `/catalog/movie/top/genre=Action.json`, `/catalog/movie/top/skip=100.json`.
    final List<String> segments = <String>[
      'catalog',
      type,
      catalog,
      if (extra != null && extra.isNotEmpty) extra,
      if (skip > 0) 'skip=$skip',
    ];
    final String path = '/${segments.join('/')}.json';
    final dynamic body = await _getJson(path);
    return _parseList(body);
  }

  List<CinemaItem> _parseList(dynamic body) {
    final List<CinemaItem> out = <CinemaItem>[];
    if (body is! Map) return out;
    final dynamic metas = body['metas'];
    if (metas is! List) return out;
    for (final dynamic m in metas) {
      if (m is Map) out.add(CinemaItem.fromJson(Map<String, dynamic>.from(m)));
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Meta (details)
  // -------------------------------------------------------------------------

  /// Full details for a movie or a series (episodes for series included).
  Future<CinemaMeta> fetchMeta(String type, String imdbId) async {
    final dynamic body =
        await _getJson('/meta/$type/${Uri.encodeComponent(imdbId)}.json');
    final dynamic m = body is Map ? body['meta'] : null;
    if (m is! Map) {
      throw const CinemaApiException('Unexpected meta payload.');
    }
    return CinemaMeta.fromJson(Map<String, dynamic>.from(m));
  }
}

class CinemaApiException implements Exception {
  const CinemaApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

// =============================================================================
// Models
// =============================================================================

/// One poster in a catalog row.
class CinemaItem {
  CinemaItem({
    required this.id,
    required this.name,
    required this.type,
  });

  /// IMDb id (tt…), used for details and playback.
  final String id;
  String name;

  /// `movie` or `series`.
  String type;

  String poster = '';
  String background = '';
  String description = '';
  String releaseInfo = '';
  double imdbRating = 0;
  List<String> genres = <String>[];

  bool get isSeries => type == 'series';

  static CinemaItem fromJson(Map<String, dynamic> j) {
    final CinemaItem it = CinemaItem(
      id: (j['imdb_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      type: (j['type'] ?? 'movie').toString(),
    );
    it.poster = (j['poster'] ?? '').toString();
    it.background = (j['background'] ?? j['backdrop'] ?? '').toString();
    it.description = (j['description'] ?? '').toString();
    it.releaseInfo = (j['releaseInfo'] ?? j['year'] ?? '').toString();
    it.imdbRating = _doubleOf(j['imdbRating']) ?? 0;
    final List<String> g = <String>[];
    final dynamic genres = j['genre'] ?? j['genres'];
    if (genres is List) {
      for (final dynamic x in genres) {
        final String s = x.toString();
        if (s.isNotEmpty) g.add(s);
      }
    }
    it.genres
      ..clear()
      ..addAll(g);
    return it;
  }
}

/// Full details payload (movies: trailers; series: episode list).
class CinemaMeta extends CinemaItem {
  CinemaMeta({required super.id, required super.name, required super.type});

  String runtime = '';
  String status = '';

  /// TMDB id (`moviedb_id` from Cinemeta) — required by some providers for
  /// series playback.
  String tmdbId = '';
  List<String> cast = <String>[];
  List<CinemaTrailer> trailers = <CinemaTrailer>[];
  List<CinemaEpisode> episodes = <CinemaEpisode>[];

  /// Distinct seasons, ascending.
  List<int> get seasonNumbers {
    final Set<int> s = <int>{for (final CinemaEpisode e in episodes) e.season};
    final List<int> out = s.toList()..sort();
    return out;
  }

  static CinemaMeta fromJson(Map<String, dynamic> j) {
    final CinemaMeta m = CinemaMeta(
      id: (j['imdb_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      type: (j['type'] ?? 'movie').toString(),
    );
    m.poster = (j['poster'] ?? '').toString();
    m.background = (j['background'] ?? '').toString();
    m.description = (j['description'] ?? '').toString();
    m.releaseInfo = (j['releaseInfo'] ?? '').toString();
    m.runtime = (j['runtime'] ?? '').toString();
    m.status = (j['status'] ?? '').toString();
    m.imdbRating = _doubleOf(j['imdbRating']) ?? 0;
    m.tmdbId = (j['moviedb_id'] ?? j['tmdb_id'] ?? '').toString();
    final dynamic genres = j['genre'] ?? j['genres'];
    if (genres is List) {
      for (final dynamic x in genres) {
        final String s = x.toString();
        if (s.isNotEmpty) m.genres.add(s);
      }
    }
    final dynamic cast = j['cast'];
    if (cast is List) {
      for (final dynamic x in cast) {
        final String s = x.toString();
        if (s.isNotEmpty) m.cast.add(s);
      }
    }
    final dynamic trailers = j['trailerStreams'] ?? j['trailers'];
    if (trailers is List) {
      for (final dynamic t in trailers) {
        if (t is Map) {
          m.trailers.add(CinemaTrailer(
            source: (t['source'] ?? '').toString(),
            type: (t['type'] ?? 'Trailer').toString(),
          ));
        }
      }
    }
    final dynamic videos = j['videos'];
    if (videos is List) {
      for (final dynamic v in videos) {
        if (v is! Map) continue;
        final Map<String, dynamic> vm = Map<String, dynamic>.from(v);
        final dynamic season = vm['season'];
        if (season == null) continue; // skip specials / extras without season
        m.episodes.add(CinemaEpisode(
          season: _intOf(season) ?? 0,
          number: _intOf(vm['number'] ?? vm['episode']) ?? 0,
          name: (vm['name'] ?? '').toString(),
          overview: (vm['overview'] ?? vm['description'] ?? '').toString(),
          thumbnail: (vm['thumbnail'] ?? '').toString(),
          released: (vm['released'] ?? vm['firstAired'] ?? '').toString(),
        ));
      }
      m.episodes.sort((CinemaEpisode a, CinemaEpisode b) {
        final int s = a.season.compareTo(b.season);
        return s != 0 ? s : a.number.compareTo(b.number);
      });
    }
    return m;
  }
}

/// YouTube trailer reference.
class CinemaTrailer {
  const CinemaTrailer({required this.source, required this.type});
  final String source;
  final String type;

  /// `yt` sources open as a YouTube watch URL.
  bool get isYouTube =>
      type.toLowerCase() == 'trailer' && source.length == 11;
}

/// One series episode.
class CinemaEpisode {
  const CinemaEpisode({
    required this.season,
    required this.number,
    required this.name,
    required this.overview,
    required this.thumbnail,
    required this.released,
  });
  final int season;
  final int number;
  final String name;
  final String overview;
  final String thumbnail;
  final String released;

  String get label => 'S${season.toString().padLeft(2, '0')}'
      ' · E${number.toString().padLeft(2, '0')}';
}

double? _doubleOf(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _intOf(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

// =============================================================================
// Playback embed (vidsrc.sh family — IMDb-id based multi-server player)
// =============================================================================

/// Builds the embed-player URL for a Cinema title / episode.
///
/// The embed player (vidsrc.sh family) resolves 3+ servers per title,
/// renders burned-in subtitles (OpenSubtitles auto-match) and performs
/// bandwidth-adaptive quality selection in its own UI. Verified live:
/// `embed/movie/tt0137523` and `embed/tv/tt0903747/1-1` both answer HTTP 200.
class CinemaPlayback {
  CinemaPlayback._();

  static const String embedBase = 'https://vidsrc.sh';

  /// UA / Referer for the WebView that hosts the embed player.
  static const String ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static String movieUrl(String imdbId) =>
      '$embedBase/embed/movie/${Uri.encodeComponent(imdbId)}';

  static String episodeUrl(String imdbId, int season, int episode) =>
      '$embedBase/embed/tv/${Uri.encodeComponent(imdbId)}'
      '/${season.toString().padLeft(2, '0')}-${episode.toString().padLeft(2, '0')}';

  /// Hosts the embed is allowed to load from (popunder/ads get blocked).
  static const List<String> allowedHosts = <String>[
    'vidsrc.sh',
    'stellarconductornexus.com',
    'vidsrcme.ru',
    'data.vidsrc.sh',
    'data.vidsrcme.ru',
    'nectarandnectary.space',
    'vidapi.cloud',
    'vidsrc.to',
    'vidlink.pro',
    'vidcore.io',
    'vidcore.net',
    '2embed.cc',
    'streamsrcs.2embed.cc',
  ];

  static bool isAllowedHost(String host) {
    for (final String h in allowedHosts) {
      if (host == h || host.endsWith('.$h')) return true;
    }
    return false;
  }
}
