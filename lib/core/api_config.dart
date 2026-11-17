import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Base URL baked in at build time (optional):
///   flutter build apk --release --dart-define=ANIMAX_API_BASE=https://host
const String kDefaultApiBaseOverride = String.fromEnvironment('ANIMAX_API_BASE');

/// Default backend captured in the user's HAR (`upload/myapi`).
const String kDefaultApiBase = 'https://aniwaves.ru';

/// Token baked in at build time (optional):
///   --dart-define=ANIMAX_API_TOKEN=eyJhbGciOi...
const String kDefaultApiToken = String.fromEnvironment('ANIMAX_API_TOKEN');

/// User-editable backend connection settings (no UI — defaults are baked
/// in at build time).
///
/// Defaults target the captured Aniwaves AJAX contract:
/// `/ajax/v2/trending`, `/ajax/episode/list/{id}`, `/ajax/server/list`,
/// `/ajax/user/panel`, `/ajax/v2/recommendations`, `/ajax/anime/views/{id}`.
class ApiConfig {
  ApiConfig({
    String? baseUrl,
    String? authToken,
    this.apiKeyHeader = '',
    this.apiKeyValue = '',
    String? trendingPath,
    String? episodesPath,
    String? serversPath,
    String? userPanelPath,
    String? recommendationsPath,
    String? viewsPath,
    String? watchPath,
    String? searchPath,
    String? sourcesPath,
    String? schedulePath,
  })  : baseUrl = baseUrl ??
            (kDefaultApiBaseOverride.isNotEmpty
                ? kDefaultApiBaseOverride
                : kDefaultApiBase),
        authToken = authToken ?? kDefaultApiToken,
        trendingPath = _orDefault(trendingPath, '/ajax/v2/trending'),
        episodesPath = _orDefault(episodesPath, '/ajax/episode/list'),
        serversPath = _orDefault(serversPath, '/ajax/server/list'),
        userPanelPath = _orDefault(userPanelPath, '/ajax/user/panel'),
        recommendationsPath =
            _orDefault(recommendationsPath, '/ajax/v2/recommendations'),
        viewsPath = _orDefault(viewsPath, '/ajax/anime/views'),
        watchPath = _orDefault(watchPath, '/watch'),
        searchPath = _orDefault(searchPath, '/filter'),
        sourcesPath = _orDefault(sourcesPath, '/ajax/sources'),
        schedulePath = _orDefault(schedulePath, '/ajax/schedule/date');

  /// Empty/blank overrides fall back to the captured defaults.
  static String _orDefault(String? value, String fallback) {
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  /// e.g. `https://aniwaves.ru`.
  String baseUrl;

  /// Optional. Sent as `Authorization: Bearer <authToken>` on every request.
  String authToken;

  /// Optional custom auth header, e.g. `x-api-key`.
  String apiKeyHeader;
  String apiKeyValue;

  // ----- Endpoint paths (defaults match the captured Aniwaves API) -----
  String trendingPath;
  String episodesPath;
  String serversPath;
  String userPanelPath;
  String recommendationsPath;
  String viewsPath;
  String watchPath;
  String searchPath;

  /// `/ajax/sources` — resolves a server `data-link-id` into the embed
  /// player URL that the site itself loads inside its iframe.
  String sourcesPath;

  /// `/ajax/schedule/date` — release schedule for one calendar day.
  String schedulePath;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  String get cleanBase {
    String b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  /// Normalizes a path fragment to `/foo/bar` form.
  static String normalizePath(String p) {
    String s = p.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('/')) s = '/$s';
    while (s.endsWith('/') && s.length > 1) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Uri uri(String path, [Map<String, String>? query]) {
    final String full = cleanBase + normalizePath(path);
    return Uri.parse(full).replace(queryParameters: query);
  }

  // ----- Genre pages scraped as extra catalog sources -----
  static const List<String> genreCandidates = <String>[
    'action', 'adventure', 'comedy', 'fantasy', 'romance', 'sci-fi',
  ];

  Uri trendingUri({String? movId}) =>
      uri(trendingPath, movId == null ? null : <String, String>{'mov_id': movId});

  Uri episodesUri(String id) =>
      uri('$episodesPath/$id', <String, String>{'vrf': ''});

  Uri serversUri(String id, String ep) =>
      uri(serversPath, <String, String>{'servers': id, 'eps': ep});

  Uri recommendationsUri(String id, {int page = 1}) => uri(
      recommendationsPath,
      <String, String>{'page': '$page', 'mov_id': id});

  Uri viewsUri(String id) => uri('$viewsPath/$id');

  Uri watchUri(String slug) => uri('$watchPath/$slug');

  /// Keyword search. The backend renders results on the `/filter` page
  /// (`/filter?keyword=one+piece` — captured in the user's HAR); the same
  /// item-card markup as the genre pages is reused for parsing.
  Uri searchUri(String keyword) =>
      uri(searchPath, <String, String>{'keyword': keyword});

  Uri genreUri(String slug) => uri('/genre/$slug');

  Uri sourcesUri(String linkId) => uri(sourcesPath, <String, String>{
        'id': linkId,
        'asi': '0',
        'autoPlay': '1',
      });

  Uri scheduleUri(DateTime date) {
    final String mm = date.month.toString().padLeft(2, '0');
    final String dd = date.day.toString().padLeft(2, '0');
    return uri(schedulePath, <String, String>{'date': '${date.year}-$mm-$dd'});
  }

  // ----- Persistence -----

  static const String _storageKey = 'animax_api_config_v2';

  factory ApiConfig.fromJson(Map<String, dynamic> j) => ApiConfig(
        baseUrl: (j['baseUrl'] ?? '') as String,
        authToken: (j['authToken'] ?? '') as String,
        apiKeyHeader: (j['apiKeyHeader'] ?? '') as String,
        apiKeyValue: (j['apiKeyValue'] ?? '') as String,
        trendingPath: (j['trendingPath'] ?? '') as String,
        episodesPath: (j['episodesPath'] ?? '') as String,
        serversPath: (j['serversPath'] ?? '') as String,
        userPanelPath: (j['userPanelPath'] ?? '') as String,
        sourcesPath: (j['sourcesPath'] ?? '') as String,
        schedulePath: (j['schedulePath'] ?? '') as String,
        searchPath: (j['searchPath'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'baseUrl': baseUrl,
        'authToken': authToken,
        'apiKeyHeader': apiKeyHeader,
        'apiKeyValue': apiKeyValue,
        'trendingPath': trendingPath,
        'episodesPath': episodesPath,
        'serversPath': serversPath,
        'userPanelPath': userPanelPath,
        'sourcesPath': sourcesPath,
        'schedulePath': schedulePath,
        'searchPath': searchPath,
      };

  static Future<ApiConfig> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return ApiConfig();
      return ApiConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return ApiConfig();
    }
  }

  Future<void> save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(toJson()));
    } catch (_) {
      // Persistence is best-effort; the in-memory config still works.
    }
  }

  Future<void> clear() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}
