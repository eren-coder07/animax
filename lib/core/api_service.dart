import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_html.dart';
import 'api_mapper.dart'
    show AuthUser, authUserFromJson, tokenFromResponse, userFromResponse;
import 'app_data.dart';

import 'app_http.dart';

export 'api_html.dart'
    show AnimeWatchId, EpisodeServer, EpisodeSource, ScheduleItem, parseSourceResult;
export 'api_mapper.dart' show AuthUser;

/// Exception with a user-presentable message.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode = 0});
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

/// HTTP client for the Aniwaves AJAX backend (contract captured in the
/// user's HAR): JSON envelopes whose payloads are HTML fragments.
///
/// Requests mirror the site's own frontend headers (browser UA,
/// `X-Requested-With: XMLHttpRequest`, same-origin referer) so the AJAX
/// endpoints answer the same way they do in a browser session.
class ApiService {
  ApiService._();
  static final ApiService I = ApiService._();

  ApiConfig _config = ApiConfig();
  ApiConfig get config => _config;

  final http.Client _client = createHttpClient();

  /// Set after a successful catalog load — used by search.
  String? _knownId;

  Future<void> loadConfig() async {
    _config = await ApiConfig.load();
  }

  void updateConfig(ApiConfig c) {
    _config = c;
    _knownId = null;
  }

  void _noteId(String? id) {
    if (id != null && id.isNotEmpty) _knownId = id;
  }

  // ----- Headers (mirrors the captured browser traffic) -----

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  Map<String, String> _headers({bool ajax = false, bool jsonBody = false}) {
    final Map<String, String> h = <String, String>{
      'User-Agent': _ua,
      'Accept-Language': 'en;q=0.8',
      if (_config.cleanBase.isNotEmpty) 'Referer': _config.cleanBase,
    };
    if (ajax) {
      h['Accept'] = 'application/json, text/javascript, */*; q=0.01';
      h['X-Requested-With'] = 'XMLHttpRequest';
    } else {
      h['Accept'] =
          'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8';
    }
    if (jsonBody) h['Content-Type'] = 'application/json; charset=utf-8';
    final String token = _config.authToken.trim();
    if (token.isNotEmpty) h['Authorization'] = 'Bearer $token';
    final String keyName = _config.apiKeyHeader.trim();
    final String keyValue = _config.apiKeyValue.trim();
    if (keyName.isNotEmpty && keyValue.isNotEmpty) h[keyName] = keyValue;
    return h;
  }

  // ----- Core HTTP -----

  /// GET returning the raw body string.
  Future<String> getRaw(Uri uri,
      {bool ajax = false, Duration timeout = const Duration(seconds: 14)}) async {
    try {
      final http.Response res = await _client
          .get(uri, headers: _headers(ajax: ajax))
          .timeout(timeout);
      if (res.statusCode >= 500) {
        throw ApiException('المصدر يواجه مشكلة (HTTP ${res.statusCode}).',
            statusCode: res.statusCode);
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw ApiException('المصدر رفض هذا الطلب — حاول لاحقًا.',
            statusCode: res.statusCode);
      }
      if (res.statusCode >= 400) {
        throw ApiException('أعاد المصدر الخطأ HTTP ${res.statusCode}.',
            statusCode: res.statusCode);
      }
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } on TimeoutException {
      throw ApiException('انتهت مهلة الطلب — تحقّق من اتصالك.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('تعذّر الوصول إلى المصدر — تحقّق من اتصالك.');
    }
  }

  /// GET an AJAX endpoint → decoded JSON envelope (`{status, html|result}`).
  Future<dynamic> getAjax(Uri uri,
      {Duration timeout = const Duration(seconds: 14)}) async {
    final String body = await getRaw(uri, ajax: true, timeout: timeout);
    if (body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(body);
    } catch (_) {
      // Cloudflare interstitials / HTML error pages land here.
      throw ApiException('المصدر غير متاح مؤقتًا — حاول لاحقًا.');
    }
  }

  /// POST JSON body → decoded JSON (kept for custom backends / login).
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 12)}) async {
    final Uri uri = _config.uri(path);
    try {
      final http.Response res = await _client
          .post(uri,
              headers: _headers(ajax: true, jsonBody: true),
              body: jsonEncode(body))
          .timeout(timeout);
      if (res.statusCode >= 400) {
        throw ApiException('أعاد المصدر الخطأ HTTP ${res.statusCode}.',
            statusCode: res.statusCode);
      }
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on TimeoutException {
      throw ApiException('انتهت مهلة الطلب — تحقّق من اتصالك.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('تعذّر الوصول إلى المصدر — تحقّق من اتصالك.');
    }
  }

  /// Pulls the HTML fragment out of a standard envelope.
  static String fragmentOf(dynamic body, {String key = 'html'}) {
    if (body is! Map) return '';
    final dynamic v = body[key] ?? body['result'];
    if (v is String) return v;
    return '';
  }

  // ----- Catalog -----

  /// Trending fragment (`/ajax/v2/trending`). `movId` is optional — the
  /// endpoint also answers for the global trending list.
  Future<List<Anime>> fetchTrending({String? movId}) async {
    final dynamic body = await getAjax(_config.trendingUri(movId: movId));
    if (body is Map && body['status'] != 200 && body['status'] != true) {
      throw ApiException('قائمة الرائج غير متاحة حاليًا.');
    }
    final List<Anime> list = parseItemCards(fragmentOf(body));
    if (list.isEmpty) throw ApiException('قائمة الرائج فارغة حاليًا.');
    _noteId(list.first.watchId);
    return list;
  }

  /// Scrapes a genre page (`/genre/{slug}`) — same item-card markup.
  Future<List<Anime>> scrapeGenre(String slug) async {
    final String html = await getRaw(_config.genreUri(slug));
    return parseItemCards(html);
  }

  /// Home page scrape as a final catalog fallback.
  Future<List<Anime>> scrapeHome() async {
    final String html = await getRaw(_config.uri('/home'));
    return parseItemCards(html);
  }

  /// Builds the catalog: trending first, then genre pages to widen the list.
  /// Dedupes by slug/id and keeps order (trending titles rank first).
  ///
  /// Note: the trending endpoint answers with an empty body unless `mov_id`
  /// is present (confirmed live), so an id is sourced from a genre page when
  /// no id is known yet.
  Future<List<Anime>> fetchCatalog() async {
    final LinkedHashMapStyle seen = LinkedHashMapStyle();
    final List<Anime> out = <Anime>[];

    void addAll(List<Anime> list) {
      for (final Anime a in list) {
        if (seen.add(a.id)) out.add(a);
      }
    }

    // 1. Trending when an id is already known (repeat launches).
    final String? known = _knownId;
    if (known != null && known.isNotEmpty) {
      try {
        addAll(await fetchTrending(movId: known));
      } on ApiException {
        // Fall through to genre scrape.
      }
    }

    // 2. Genre pages — always work and yield ids for trending.
    for (final String g in ApiConfig.genreCandidates) {
      if (out.length >= 30) break;
      try {
        addAll(await scrapeGenre(g));
      } on ApiException {
        // Genre pages are optional enrichment.
      }
    }

    // 3. Trending with a discovered id (ranks its items first).
    if (out.isNotEmpty) {
      final String? id = out.first.watchId;
      if (id != null && id != known) {
        try {
          addAll(await fetchTrending(movId: id));
        } on ApiException {
          // Optional — catalog already populated.
        }
      }
    }

    // 4. Home page scrape as a final fallback.
    if (out.isEmpty) {
      try {
        addAll(await scrapeHome());
      } catch (_) {}
    }

    if (out.isEmpty) {
      throw ApiException('الكتالوج غير متاح حاليًا.');
    }
    return out;
  }

  /// Details from the watch page: synopsis, genres, score, poster, title.
  Future<Anime> fetchDetails(Anime anime) async {
    final String slug = anime.slug ?? anime.id;
    final String html = await getRaw(_config.watchUri(slug));
    final Anime rich = parseWatchDetails(anime, html);
    _noteId(rich.watchId);
    return rich;
  }

  /// Episode list for a numeric show id (`/ajax/episode/list/{id}?vrf=`).
  Future<List<Episode>> fetchEpisodes(String id) async {
    final dynamic body = await getAjax(_config.episodesUri(id));
    if (body is Map && body['status'] != 200 && body['status'] != true) {
      throw ApiException('قائمة الحلقات غير متاحة حاليًا.');
    }
    final String frag = fragmentOf(body, key: 'result');
    final List<Episode> list = parseEpisodeList(frag);
    if (list.isEmpty) throw ApiException('لا توجد حلقات لهذا العنوان.');
    _noteId(id);
    return list;
  }

  /// Streaming servers for one episode (`/ajax/server/list?servers={id}&eps={ep}`).
  /// The returned [EpisodeServer.linkId] tokens are passed through opaquely —
  /// they are only ever handed to [fetchSources] for playback.
  Future<List<EpisodeServer>> fetchServers(String id, String ep) async {
    final dynamic body = await getAjax(_config.serversUri(id, ep));
    if (body is Map && body['status'] != 200 && body['status'] != true) {
      throw ApiException('قائمة السيرفرات غير متاحة حاليًا.');
    }
    final List<EpisodeServer> list =
        parseServerList(fragmentOf(body, key: 'result'));
    if (list.isEmpty) throw ApiException('لا توجد سيرفرات لهذه الحلقة.');
    return list;
  }

  /// Resolves a server's `data-link-id` into the embed player URL the site
  /// itself loads in its iframe (`/ajax/sources?id={linkId}`). The URL is
  /// used exactly as delivered — no decoding of any kind happens here.
  Future<EpisodeSource> fetchSources(String linkId) async {
    final dynamic body = await getAjax(_config.sourcesUri(linkId));
    final EpisodeSource? src = parseSourceResult(body);
    if (src == null) {
      throw ApiException('لا يوجد مصدر قابل للتشغيل على هذا السيرفر حاليًا');
    }
    return src;
  }

  /// Release schedule for one day (`/ajax/schedule/date?date=YYYY-MM-DD`).
  Future<List<ScheduleItem>> fetchSchedule(DateTime date) async {
    final dynamic body = await getAjax(_config.scheduleUri(date));
    return parseSchedule(fragmentOf(body, key: 'result'));
  }

  /// "More like this" (`/ajax/v2/recommendations?page=&mov_id=`).
  /// Returns an empty list when the backend disables recommendations
  /// (`{"status": false, "html": false}` in the captured traffic).
  Future<List<Anime>> fetchRecommendations(String id, {int page = 1}) async {
    final dynamic body = await getAjax(_config.recommendationsUri(id, page: page));
    if (body is! Map) return const <Anime>[];
    final dynamic st = body['status'];
    if (st == false || st == 'false') return const <Anime>[];
    return parseItemCards(fragmentOf(body));
  }

  /// Registers a view (`/ajax/anime/views/{id}`) — fire-and-forget.
  Future<void> recordView(String id) async {
    try {
      await getAjax(_config.viewsUri(id), timeout: const Duration(seconds: 8));
    } on ApiException {
      // Counting views is best-effort; never surface errors.
    }
  }

  /// Session/user state (`/ajax/user/panel`).
  Future<Map<String, dynamic>> fetchUserPanel() async {
    final dynamic body = await getAjax(_config.userPanelPath.isEmpty
        ? _config.uri('/ajax/user/panel')
        : _config.uri(_config.userPanelPath));
    if (body is Map && body['result'] is Map) {
      return Map<String, dynamic>.from(body['result'] as Map);
    }
    return const <String, dynamic>{};
  }

  /// Keyword search — scrapes the `/filter?keyword={q}` results page
  /// (the endpoint the site's own search form navigates to, captured in the
  /// user's HAR). Falls back to the generic item-card parser when the page
  /// serves the compact card layout instead.
  Future<List<Anime>> search(String query) async {
    final String html = await getRaw(_config.searchUri(query));
    final List<Anime> list = parseFilterCards(html);
    final List<Anime> out = list.isNotEmpty ? list : parseItemCards(html);
    for (final Anime a in out) {
      _noteId(a.watchId);
    }
    return out;
  }

  // ----- Auth (generic REST fallback) -----
  //
  // The captured Aniwaves API keeps sign-in behind a session cookie + CSRF
  // form flow, so these helpers target generic JSON auth endpoints. When the
  // backend has none (like aniwaves.tv), login() throws and the UI falls
  // back to the local profile.

  /// Attempts login against candidate auth paths.
  /// Returns `(token, user)`; throws [ApiException] on bad credentials /
  /// unreachable backend.
  Future<(String?, AuthUser?)> login(String email, String password) async {
    ApiException? last;
    for (final String path in const <String>[
      '/auth/login', '/login', '/api/auth/login', '/api/login',
    ]) {
      try {
        final dynamic body = await post(path, <String, dynamic>{
          'email': email,
          'password': password,
          'username': email,
        });
        final String? token = tokenFromResponse(body);
        final Map<String, dynamic>? userJson = userFromResponse(body);
        final AuthUser? user =
            userJson == null ? null : authUserFromJson(userJson);
        return (token, user);
      } on ApiException catch (e) {
        last = e;
        if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 400) {
          throw ApiException('البريد الإلكتروني أو كلمة المرور غير صحيحة');
        }
      }
    }
    throw last ?? ApiException('خدمة تسجيل الدخول غير متوفرة');
  }
}

/// Tiny insertion-ordered set used to dedupe catalog entries.
class LinkedHashMapStyle {
  final Set<String> _seen = <String>{};

  bool add(String id) => _seen.add(id);
}
