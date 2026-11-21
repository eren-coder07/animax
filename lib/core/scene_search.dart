import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'api_service.dart';
import 'app_data.dart';
import 'app_http.dart';

/// One match of a screenshot: which anime, episode and second.
class SceneMatch {
  const SceneMatch({
    required this.title,
    required this.altTitle,
    required this.episode,
    required this.from,
    required this.to,
    required this.similarity,
    required this.preview,
    required this.isAdult,
  });
  final String title; // romaji
  final String altTitle; // english / native
  final int episode;
  final double from;
  final double to;
  final double similarity;
  final String preview; // still image URL of the matched moment
  final bool isAdult;

  static SceneMatch fromJson(Map<String, dynamic> r) {
    final Map<String, dynamic> a =
        (r['anilist'] is Map ? r['anilist'] : <String, dynamic>{})
            as Map<String, dynamic>;
    final Map<String, dynamic> t =
        (a['title'] is Map ? a['title'] : <String, dynamic>{})
            as Map<String, dynamic>;
    final Object? ep = r['episode'];
    return SceneMatch(
      title: (t['romaji'] ?? t['english'] ?? r['filename'] ?? '').toString(),
      altTitle: (t['english'] ?? t['native'] ?? '').toString(),
      episode: ep is num ? ep.toInt() : int.tryParse('$ep') ?? 1,
      from: (r['from'] as num?)?.toDouble() ?? 0,
      to: (r['to'] as num?)?.toDouble() ?? 0,
      similarity: (r['similarity'] as num?)?.toDouble() ?? 0,
      preview: (r['image'] ?? '').toString(),
      isAdult: a['isAdult'] == true,
    );
  }
}

/// «ابحث بالمشهد»: a screenshot → the anime, episode and second it comes
/// from (trace.moe frame index), then the exact moment opens in our player.
class SceneSearch {
  SceneSearch._();

  static const MethodChannel _ch = MethodChannel('animax/app');

  /// Matches below this are dropped; below [sureSimilarity] shown as unsure.
  static const double minSimilarity = 0.85;
  static const double sureSimilarity = 0.92;
  static http.Client? _client;
  static http.Client get _http => _client ??= createHttpClient();

  /// Opens the system picker; null when cancelled.
  static Future<Uint8List?> pickImage() async {
    try {
      return await _ch.invokeMethod<Uint8List>('pickImage');
    } catch (_) {
      return null;
    }
  }

  /// Downscales to ≤ 640 px JPEG (a few dozen KB: fast on slow lines).
  static Uint8List shrink(Uint8List bytes) {
    try {
      final img.Image? im = img.decodeImage(bytes);
      if (im == null) return bytes;
      final img.Image small = im.width > 640
          ? img.copyResize(im, width: 640)
          : im;
      return Uint8List.fromList(img.encodeJpg(small, quality: 85));
    } catch (_) {
      return bytes;
    }
  }

  /// Best matches (most similar first). Throws [SceneSearchException].
  static Future<List<SceneMatch>> search(Uint8List image) async {
    final http.Response r = await _http
        .post(
          Uri.parse('https://api.trace.moe/search?anilistInfo&cutBorders'),
          headers: <String, String>{'Content-Type': 'image/jpeg'},
          body: shrink(image),
        )
        .timeout(const Duration(seconds: 40));
    if (r.statusCode == 402 || r.statusCode == 429) {
      throw SceneSearchException(
        'خدمة البحث بالمشهد مشغولة الآن — حاول بعد دقيقة.',
      );
    }
    if (r.statusCode >= 400) {
      throw SceneSearchException('تعذّر البحث بالمشهد (${r.statusCode}).');
    }
    final Map<String, dynamic> j =
        jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final List<SceneMatch> out = <SceneMatch>[
      for (final dynamic x in (j['result'] as List<dynamic>? ?? <dynamic>[]))
        if (x is Map<String, dynamic>) SceneMatch.fromJson(x),
    ];
    out.sort(
      (SceneMatch a, SceneMatch b) => b.similarity.compareTo(a.similarity),
    );
    // One row per title+episode, adult results dropped.
    final Set<String> seen = <String>{};
    // Below ~85 % the frame index is usually guessing (new / unknown shows).
    return out
        .where(
          (SceneMatch m) =>
              !m.isAdult &&
              m.similarity >= minSimilarity &&
              seen.add('${m.title}#${m.episode}'),
        )
        .take(5)
        .toList();
  }

  /// Finds the matched anime in our catalog (title search). Null if absent.
  static Future<Anime?> findInCatalog(SceneMatch m) async {
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    // Only Latin titles are searchable in our catalog; a non-Latin title
    // normalises to '' and must never "match" everything.
    for (final String q in <String>{
      m.title,
      m.altTitle,
    }.where((String q) => norm(q).length >= 3)) {
      try {
        final List<Anime> hits = await ApiService.I.search(q);
        for (final Anime a in hits) {
          final String t = norm(a.title);
          if (t == norm(m.title) ||
              (m.altTitle.isNotEmpty && t == norm(m.altTitle)))
            return a;
        }
        if (hits.isNotEmpty && hits.first.watchId != null) {
          // Close titles (season suffixes etc.): accept the top hit when it
          // starts with the query.
          final String t = norm(hits.first.title);
          if (t.startsWith(norm(q)) || norm(q).startsWith(t)) return hits.first;
        }
      } catch (_) {}
    }
    return null;
  }
}

class SceneSearchException implements Exception {
  SceneSearchException(this.message);
  final String message;
  @override
  String toString() => message;
}
