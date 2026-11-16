import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_http.dart';
import 'stream_resolver.dart';

/// Bandwidth-aware quality selection for native HLS playback.
///
/// "Watch based on the user's Wi-Fi speed": on every stream start the master
/// playlist is parsed into quality variants, a quick ranged download from the
/// same CDN measures the real throughput, and the highest variant that fits
/// the measured bandwidth (with headroom) is selected. ExoPlayer's own ABR
/// stays available through the `Master (ABR)` entry in the quality menu.
///
/// Live-verified master format (2026-11-16, egybestvid CDN):
/// ```
/// #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=884042,RESOLUTION=1280x532,...
/// https://…/index-v1-a1.m3u8?…
/// ```
class HlsVariant {
  const HlsVariant({
    required this.bandwidth,
    required this.uri,
    this.width = 0,
    this.height = 0,
    this.name = '',
  });

  /// Declared bitrate, bits per second.
  final int bandwidth;
  final Uri uri;
  final int width;
  final int height;
  final String name;

  String get label {
    if (name.isNotEmpty) return name;
    if (height > 0) return '${height}p';
    return '${(bandwidth / 1000000).toStringAsFixed(1)}Mbps';
  }
}

class HlsQuality {
  HlsQuality._();

  static final http.Client _client = createHttpClient();

  static const MethodChannel _channel = MethodChannel('animax/app');

  /// Headroom applied to measured Mbps. Wi-Fi keeps headroom stable; cellular
  /// fluctuates, so stay further below capacity.
  static const double wifiHeadroom = 0.7;
  static const double cellularHeadroom = 0.45;

  // -------------------------------------------------------------------------
  // Master playlist parsing
  // -------------------------------------------------------------------------

  /// Parses a master playlist into its variants (empty for media playlists).
  static List<HlsVariant> parseMaster(String body, Uri base) {
    final List<HlsVariant> out = <HlsVariant>[];
    final List<Match> matches =
        RegExp(r'#EXT-X-STREAM-INF:([^\r\n]+)').allMatches(body).toList();
    for (int i = 0; i < matches.length; i++) {
      final Map<String, String> a = <String, String>{};
      // Split attributes on commas not inside quotes (CODECS="…").
      final String raw = matches[i].group(1)!;
      final StringBuffer cur = StringBuffer();
      bool inQuote = false;
      for (int c = 0; c < raw.length; c++) {
        final String ch = raw[c];
        if (ch == '"') inQuote = !inQuote;
        if (ch == ',' && !inQuote) {
          _addAttr(a, cur.toString());
          cur.clear();
        } else {
          cur.write(ch);
        }
      }
      _addAttr(a, cur.toString());
      final int bw = int.tryParse(a['BANDWIDTH'] ?? '') ?? 0;
      if (bw <= 0) continue;
      int w = 0;
      int h = 0;
      final RegExpMatch? rm =
          RegExp(r'^(\d+)x(\d+)$').firstMatch((a['RESOLUTION'] ?? '').trim());
      if (rm != null) {
        w = int.tryParse(rm.group(1)!) ?? 0;
        h = int.tryParse(rm.group(2)!) ?? 0;
      }
      // The variant URI is the next non-comment, non-empty line.
      final int end = matches[i].end;
      final int next =
          i + 1 < matches.length ? matches[i + 1].start : body.length;
      String? line;
      for (final String l in body.substring(end, next).split('\n')) {
        final String t = l.trim();
        if (t.isNotEmpty && !t.startsWith('#')) {
          line = t;
          break;
        }
      }
      if (line == null) continue;
      final Uri? uri = Uri.tryParse(base.resolveUri(Uri.parse(line)).toString());
      if (uri == null || !uri.hasScheme) continue;
      out.add(HlsVariant(
        bandwidth: bw,
        uri: uri,
        width: w,
        height: h,
        name: a['NAME'] ?? '',
      ));
    }
    return out;
  }

  static void _addAttr(Map<String, String> map, String chunk) {
    final int eq = chunk.indexOf('=');
    if (eq <= 0) return;
    final String key = chunk.substring(0, eq).trim().toUpperCase();
    String value = chunk.substring(eq + 1).trim();
    if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
      value = value.substring(1, value.length - 1);
    }
    map[key] = value;
  }

  // -------------------------------------------------------------------------
  // Bandwidth probing
  // -------------------------------------------------------------------------

  static const int _probeBytes = 1500000;
  static const Duration _cacheTtl = Duration(minutes: 5);
  static final Map<String, _BwEntry> _cache = <String, _BwEntry>{};

  /// Measures download Mbps by ranging ~1.5 MB off a media segment that lives
  /// on the same CDN as the stream (signed query strings are preserved).
  /// Cached per host for [_cacheTtl]; failures return the previous value or a
  /// conservative 5 Mbps so playback always starts.
  static Future<double> measure(Uri url,
      {Map<String, String> headers = const <String, String>{}}) async {
    final String host = url.host;
    final _BwEntry? hit = _cache[host];
    if (hit != null && DateTime.now().difference(hit.at) < _cacheTtl) {
      return hit.mbps;
    }
    double mbps = hit?.mbps ?? 5;
    try {
      final Stopwatch sw = Stopwatch()..start();
      final http.Response res = await _client
          .get(url, headers: <String, String>{
            ...headers,
            'Range': 'bytes=0-$_probeBytes',
          })
          .timeout(const Duration(seconds: 7));
      sw.stop();
      if (res.statusCode == 200 || res.statusCode == 206) {
        final int bytes = res.bodyBytes.length;
        if (bytes > 100000) {
          final double secs = sw.elapsedMicroseconds / 1000000.0;
          if (secs > 0.15) mbps = (bytes * 8) / 1000000 / secs;
        }
      }
    } catch (_) {
      // keep previous / conservative estimate
    }
    _cache[host] = _BwEntry(mbps: mbps, at: DateTime.now());
    return mbps;
  }

  /// Wi-Fi / cellular / none, via the Android platform channel.
  static Future<bool> isOnWifi() async {
    try {
      final String? t = await _channel
          .invokeMethod<String>('networkType')
          .timeout(const Duration(seconds: 2));
      return t == 'wifi';
    } catch (_) {
      return true; // assume Wi-Fi (higher quality) when unknown
    }
  }

  // -------------------------------------------------------------------------
  // Selection
  // -------------------------------------------------------------------------

  /// Highest variant that fits [mbps] with headroom for [onWifi].
  static HlsVariant? pick(List<HlsVariant> variants, double mbps, bool onWifi) {
    if (variants.isEmpty) return null;
    final double target = mbps * (onWifi ? wifiHeadroom : cellularHeadroom);
    final List<HlsVariant> sorted = <HlsVariant>[...variants]
      ..sort((HlsVariant a, HlsVariant b) => b.bandwidth - a.bandwidth);
    for (final HlsVariant v in sorted) {
      if (v.bandwidth <= target * 1000000) return v;
    }
    return sorted.last; // even the lowest does not fit — take it anyway
  }

  /// Replaces a master-playlist stream with the bandwidth-appropriate variant.
  ///
  /// The returned stream's [ResolvedStream.qualities] carries every variant
  /// (chosen one first, labelled `Auto (720p)`) plus `Master (ABR)`, so the
  /// existing quality menu can switch manually.
  static Future<ResolvedStream> autoSelect(ResolvedStream rs,
      {Map<String, String> headers = const <String, String>{}}) async {
    if (!rs.isHls || rs.qualities.length > 1) return rs;
    final Uri base = Uri.parse(rs.url);
    try {
      final http.Response res = await _client
          .get(base, headers: <String, String>{...headers, 'Accept': '*/*'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return rs;
      final String body = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (!body.contains('#EXT-X-STREAM-INF')) return rs; // media playlist
      final List<HlsVariant> variants = parseMaster(body, base);
      if (variants.isEmpty) return rs;
      // Probe throughput against a real media segment: take the highest
      // variant's playlist, then its first segment URL.
      Uri probeUrl = variants.first.uri;
      try {
        final http.Response pl = await _client
            .get(variants.first.uri,
                headers: <String, String>{...headers, 'Accept': '*/*'})
            .timeout(const Duration(seconds: 8));
        if (pl.statusCode == 200) {
          final String plBody =
              utf8.decode(pl.bodyBytes, allowMalformed: true);
          for (final String l in plBody.split('\n')) {
            final String t = l.trim();
            if (t.isNotEmpty && !t.startsWith('#')) {
              probeUrl = variants.first.uri.resolveUri(Uri.parse(t));
              break;
            }
          }
        }
      } catch (_) {/* fall back to probing the variant playlist itself */}
      final bool wifi = await isOnWifi();
      final double mbps = await measure(probeUrl, headers: headers);
      final HlsVariant? chosen = pick(variants, mbps, wifi);
      if (chosen == null) return rs;
      final Map<String, String> qualities = <String, String>{
        'Auto (${chosen.label})': chosen.uri.toString(),
        for (final HlsVariant v in variants
            .where((HlsVariant v) => v.uri != chosen.uri))
          v.label: v.uri.toString(),
        'Master (ABR)': rs.url,
      };
      return ResolvedStream(
        url: chosen.uri.toString(),
        qualities: qualities,
        introStart: rs.introStart,
        introEnd: rs.introEnd,
        referer: rs.referer,
      );
    } catch (_) {
      return rs;
    }
  }
}

class _BwEntry {
  const _BwEntry({required this.mbps, required this.at});
  final double mbps;
  final DateTime at;
}
