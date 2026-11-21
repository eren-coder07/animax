import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'app_prefs.dart';
import 'app_http.dart';
import 'data_budget.dart';

/// Slow-connection detection ("وضع الإنترنت الضعيف").
///
/// Slow when the user enabled data saver, or the active network reports
/// less than [slowKbps] downstream (≈ 190 KB/s). Results are cached for a
/// minute. When slow the app loads small images, starts videos at the
/// lowest quality and reads manga in data-saver pages.
class NetQuality {
  NetQuality._();

  static const MethodChannel _ch = MethodChannel('animax/app');
  static const int slowKbps = 1500;

  static bool _slow = false;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  /// Last known state (sync); refreshed by [check].
  static bool get isSlow =>
      AppPrefs.I.dataSaver || AppPrefs.I.audioOnly || DataBudget.I.nearLimit || _slow;

  // ------------------------------------------------- measured throughput

  /// Real download speed (kbit/s) measured from actual transfers, or -1.
  /// The OS "link speed" above is often wildly optimistic (a strong Wi-Fi
  /// signal on a slow line reports 50+ Mbit/s).
  static int measuredKbps = -1;
  static DateTime _measuredAt = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get hasFreshMeasure =>
      measuredKbps > 0 && DateTime.now().difference(_measuredAt).inMinutes < 3;

  /// Feeds one finished transfer (ignored when too small to be meaningful).
  static void record(int bytes, int ms) {
    if (bytes < 48 * 1024 || ms < 150) return;
    final int kbps = (bytes * 8 / ms).round();
    measuredKbps = measuredKbps <= 0 || !hasFreshMeasure
        ? kbps
        : (measuredKbps * 0.6 + kbps * 0.4).round();
    _measuredAt = DateTime.now();
    if (measuredKbps < slowKbps) _slow = true;
  }

  /// Downloads up to [maxBytes] of [url] (≤ 2.5 s) and returns kbit/s.
  static Future<int> probe(String url, Map<String, String> headers,
      {int maxBytes = 160 * 1024}) async {
    if (hasFreshMeasure) return measuredKbps;
    final HttpClient c = createIoHttpClient();
    try {
      final Stopwatch sw = Stopwatch()..start();
      final HttpClientRequest rq = await c.getUrl(Uri.parse(url));
      headers.forEach(rq.headers.set);
      // Skip the file header: measure plain media throughput.
      rq.headers.set(HttpHeaders.rangeHeader, 'bytes=1048576-${1048576 + maxBytes - 1}');
      final HttpClientResponse rs = await rq.close().timeout(const Duration(seconds: 8));
      final int t0 = sw.elapsedMilliseconds; // time to first byte (latency)
      int got = 0;
      await for (final List<int> chunk in rs.timeout(const Duration(seconds: 4))) {
        got += chunk.length;
        if (got >= maxBytes || sw.elapsedMilliseconds - t0 > 2500) break;
      }
      final int ms = math.max(1, sw.elapsedMilliseconds - t0);
      final int kbps = (got * 8 / ms).round();
      measuredKbps = kbps;
      _measuredAt = DateTime.now();
      if (kbps < slowKbps) _slow = true;
      return kbps;
    } catch (_) {
      return -1;
    } finally {
      c.close(force: true);
    }
  }

  /// Rough bitrate (kbit/s) of an Akwam encode by picture height.
  static int estimatedKbps(int height) => switch (height) {
        <= 0 => 1500,
        <= 240 => 350,
        <= 360 => 600,
        <= 480 => 900,
        <= 720 => 1600,
        _ => 3200,
      };

  /// Best height the measured speed sustains (30 % headroom).
  static int pickHeight(List<int> heights, int kbps) {
    final List<int> hs = heights.where((int h) => h > 0).toList()..sort();
    if (hs.isEmpty) return heights.isEmpty ? 0 : heights.first;
    if (kbps <= 0) return hs.first;
    int best = hs.first;
    for (final int h in hs) {
      if (estimatedKbps(h) * 1.3 <= kbps) best = h;
    }
    return best;
  }

  static Future<bool> check() async {
    if (AppPrefs.I.dataSaver || AppPrefs.I.audioOnly || DataBudget.I.nearLimit) {
      return true;
    }
    if (DateTime.now().difference(_at) < const Duration(minutes: 1)) {
      return _slow;
    }
    try {
      final int? kbps = await _ch
          .invokeMethod<int>('netSpeedKbps')
          .timeout(const Duration(seconds: 2));
      _slow = kbps != null && kbps > 0 && kbps < slowKbps;
    } catch (_) {
      _slow = false;
    }
    _at = DateTime.now();
    return _slow;
  }
}
