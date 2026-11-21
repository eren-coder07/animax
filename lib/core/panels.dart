import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'app_http.dart';
import 'manga_api.dart';
import 'net_quality.dart';
import 'social.dart';

/// Manga panel clips: a rectangle (normalized 0..1) of one chapter page.
///
/// `ref` = {mangaId, chapterId, page, x, y, w, h}. Page image URLs come from
/// MangaDex's at-home servers and expire, so they are re-resolved from the
/// chapter id when a panel is shown (cached for 10 minutes).
class Panels {
  Panels._();

  static const int showMs = 6000; // a panel "plays" for 6 s in the feed

  static final Map<String, ({List<String> urls, DateTime at})> _pages =
      <String, ({List<String> urls, DateTime at})>{};
  static http.Client? _client;
  static http.Client get _http => _client ??= createHttpClient();

  static Future<String> pageUrl(String chapterId, int page) async {
    final ({List<String> urls, DateTime at})? hit = _pages[chapterId];
    List<String> urls;
    if (hit != null && DateTime.now().difference(hit.at).inMinutes < 10) {
      urls = hit.urls;
    } else {
      urls = await MangaApi.I.pages(chapterId, dataSaver: NetQuality.isSlow);
      _pages[chapterId] = (urls: urls, at: DateTime.now());
    }
    if (urls.isEmpty) throw StateError('no pages');
    return urls[page.clamp(0, urls.length - 1)];
  }

  /// Normalized crop rectangle stored in a clip ref.
  static Rect rectOf(Map<String, String> ref) {
    double v(String k, double d) =>
        (double.tryParse(ref[k] ?? '') ?? d).clamp(0.0, 1.0);
    final double x = v('x', 0), y = v('y', 0);
    final double w = v('w', 1).clamp(0.02, 1.0 - x);
    final double h = v('h', 1).clamp(0.02, 1.0 - y);
    return Rect.fromLTWH(x, y, w, h);
  }

  static Map<String, String> refFor({
    required String mangaId,
    required String chapterId,
    required int page,
    required Rect r,
  }) => <String, String>{
    'mangaId': mangaId,
    'chapterId': chapterId,
    'page': '$page',
    'x': r.left.toStringAsFixed(4),
    'y': r.top.toStringAsFixed(4),
    'w': r.width.toStringAsFixed(4),
    'h': r.height.toStringAsFixed(4),
  };

  /// Crop rectangle in pixels of an image of [size] (pure, unit-tested).
  static Rect pixelRect(Rect norm, Size size) => Rect.fromLTWH(
    (norm.left * size.width).floorToDouble(),
    (norm.top * size.height).floorToDouble(),
    (norm.width * size.width).ceilToDouble().clamp(1, size.width),
    (norm.height * size.height).ceilToDouble().clamp(1, size.height),
  );

  /// Downloads the page of [clip] and renders just the panel as PNG.
  static Future<Uint8List> panelPng(VideoClip clip) async {
    final String url = await pageUrl(
      clip.ref['chapterId'] ?? '',
      int.tryParse(clip.ref['page'] ?? '') ?? 0,
    );
    final http.Response r = await _http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode >= 400) throw StateError('HTTP ${r.statusCode}');
    final ui.Codec codec = await ui.instantiateImageCodec(r.bodyBytes);
    final ui.Image img = (await codec.getNextFrame()).image;
    final Rect src = pixelRect(
      rectOf(clip.ref),
      Size(img.width.toDouble(), img.height.toDouble()),
    );
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    c.drawImageRect(
      img,
      src,
      Rect.fromLTWH(0, 0, src.width, src.height),
      Paint()..filterQuality = FilterQuality.high,
    );
    final ui.Image out = await rec.endRecording().toImage(
      src.width.round(),
      src.height.round(),
    );
    final ByteData? png = await out.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    out.dispose();
    if (png == null) throw StateError('encode failed');
    return png.buffer.asUint8List();
  }
}
