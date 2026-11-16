import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

import 'app_http.dart';

/// A playback stream resolved into a **direct media URL** the native player
/// can open (progressive MP4 or an HLS playlist).
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    this.qualities = const <String, String>{},
    this.introStart = 0,
    this.introEnd = 0,
    this.referer = '',
  });

  /// Primary URL handed to the player.
  final String url;

  /// Quality label -> URL (HD / SD / HQ…). Empty when the source is a
  /// single adaptive stream (HLS) with no discrete qualities.
  final Map<String, String> qualities;

  /// Intro window (seconds) from the backend's `skip_data`, if any.
  final int introStart;
  final int introEnd;

  /// Referer the stream was resolved against — sent by the player so the
  /// CDN accepts the request.
  final String referer;

  bool get hasIntro => introEnd > introStart;

  bool get hasQualities => qualities.length > 1;

  /// Guesses HLS from the extension / payload marker so the UI can label it.
  bool get isHls {
    final String path = Uri.tryParse(url)?.path ?? '';
    if (path.toLowerCase().endsWith('.m3u8')) return true;
    return url.toLowerCase().contains('.m3u8');
  }
}

/// Exception with a user-presentable message for stream resolution failures.
class StreamResolveException implements Exception {
  StreamResolveException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Resolves an episode server into a direct stream URL.
///
/// Chain (verified against the live backend):
///
///   1. `/ajax/sources?id={linkId}`  -> embed player page URL
///   2. GET the embed page           -> `<div id="…player" data-id="{token}">`
///   3. `{embedBase}/getSources?id={token}` (Referer = embed page)
///        -> `{"sources": {"HD": ["…mp4"], "SD": ["…"]}}`   (quality map)
///        -> `{"sources": "https://…/playlist.m3u8"}`       (single HLS)
///
/// Servers whose embed page hides the token behind client-side decoding are
/// reported as unresolvable (returns null) so the caller can fall back to
/// the next server.
class StreamResolver {
  StreamResolver._();
  static final StreamResolver I = StreamResolver._();

  final http.Client _client = createHttpClient();

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// Resolves [server]. Returns null when the server cannot be turned into
  /// a direct stream (caller should try another server).
  Future<ResolvedStream?> resolve(EpisodeServer server,
      {Duration timeout = const Duration(seconds: 14)}) async {
    try {
      // 1. Embed player page URL (also carries the intro skip window).
      final EpisodeSource src =
          await ApiService.I.fetchSources(server.linkId);
      final Uri embedUri = Uri.parse(src.url);
      final String embedUrl = src.url;

      // 2. Embed page HTML — carries the source token.
      final http.Response page = await _client
          .get(embedUri, headers: <String, String>{
        'User-Agent': _ua,
        'Referer': ApiService.I.config.cleanBase,
        'Accept': 'text/html,*/*',
      }).timeout(timeout);
      if (page.statusCode >= 400) return null;
      final String html = utf8.decode(page.bodyBytes, allowMalformed: true);

      // 3. Extract token + the getSources call the page itself uses.
      final EmbedSource? token = extractEmbedSource(html);
      if (token == null) return null;
      final Uri sourcesUri =
          embedUri.resolve(token.sourcesPath.replaceFirst('%ID%', token.id));

      // 4. Ask for the direct sources (Referer = the embed page).
      final http.Response res = await _client.get(sourcesUri, headers: <String, String>{
        'User-Agent': _ua,
        'Referer': embedUrl,
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
      }).timeout(timeout);
      if (res.statusCode >= 400) return null;
      final dynamic body =
          jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));

      return parseGetSources(body,
          introStart: src.introStart,
          introEnd: src.introEnd,
          referer: embedUrl);
    } on ApiException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}

/// Token + relative getSources path scraped from an embed page.
class EmbedSource {
  const EmbedSource(this.id, this.sourcesPath);
  final String id;

  /// `%ID%` is replaced with [id]; resolved against the embed page URL.
  final String sourcesPath;
}

/// Finds the source token in an embed page.
///
/// Matches `<any-tag … data-id="{long token}" …>` on player divs and the
/// `fetch('getSources?id=…')` / `getSources?id=` path the page's own player
/// script calls. Returns null when the page keeps its source encrypted.
EmbedSource? extractEmbedSource(String html) {
  // Token: long opaque value inside data-id (>= 20 chars, URL-safe alphabet).
  final RegExpMatch? m = RegExp(
    r'data-id="([A-Za-z0-9_\-+/=]{20,})"',
  ).firstMatch(html);
  if (m == null) return null;

  // Relative sources path as the page itself uses it.
  final RegExpMatch? gs = RegExp(
    r'''fetch\(\s*['"]([^'"]*getSources[^'"]*)['"]''',
  ).firstMatch(html);
  final String rel = gs == null ? 'getSources?id=%ID%' : gs.group(1)!;
  final String path = rel.contains('%ID%') ? rel : '$rel%ID%';
  return EmbedSource(m.group(1)!, path);
}

/// Parses the getSources JSON payload.
///
/// Handles all observed shapes:
///  * `{"sources": {"HD": ["url"], "SD": ["url"]}}`   — quality map (MP4)
///  * `{"sources": "https://…/x.m3u8"}`               — single HLS URL
///  * `{"1171": {"HD": ["url"], …}}`                  — keyed by episode id
/// Returns null when nothing playable is found.
ResolvedStream? parseGetSources(dynamic body,
    {int introStart = 0, int introEnd = 0, String referer = ''}) {
  if (body is! Map) return null;
  final dynamic raw = body['sources'] ?? _firstPlayableValue(body);

  if (raw is String && raw.trim().isNotEmpty) {
    final String url = raw.trim();
    return ResolvedStream(
      url: url,
      qualities: <String, String>{'Auto': url},
      introStart: introStart,
      introEnd: introEnd,
      referer: referer,
    );
  }

  if (raw is Map) {
    final Map<String, String> qualities = <String, String>{};
    raw.forEach((dynamic k, dynamic v) {
      final String label = k.toString().toUpperCase();
      String? url;
      if (v is String && v.trim().isNotEmpty) {
        url = v.trim();
      } else if (v is List && v.isNotEmpty) {
        final dynamic first = v.first;
        if (first is String && first.trim().isNotEmpty) url = first.trim();
      }
      if (url != null) qualities.putIfAbsent(label, () => url!);
    });
    if (qualities.isEmpty) return null;
    // Prefer the best-looking default: HQ > HD > first entry.
    String url = qualities.values.first;
    for (final String pref in const <String>['HQ', 'HD', 'FHD', 'SD']) {
      if (qualities.containsKey(pref)) {
        url = qualities[pref]!;
        break;
      }
    }
    return ResolvedStream(
      url: url,
      qualities: qualities,
      introStart: introStart,
      introEnd: introEnd,
      referer: referer,
    );
  }
  return null;
}

/// Some backends key the payload by episode id: `{"1171": {…qualities…}}`.
dynamic _firstPlayableValue(Map<dynamic, dynamic> body) {
  for (final dynamic v in body.values) {
    if (v is Map || v is String) return v;
  }
  return null;
}
