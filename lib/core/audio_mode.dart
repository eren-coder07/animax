import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_http.dart';
import 'app_prefs.dart';
import 'app_theme.dart';
import '../widgets/mb_ui.dart' show kFont;

/// "Sound only" playback shared by the players:
///  * HLS sources play their **audio-only rendition** (no video bytes at
///    all) or, when none is published, the lowest-bandwidth variant;
///  * progressive MP4 sources switch to the smallest quality;
///  * the controller keeps playing in the background / with the screen off,
///    held alive by a media foreground service (notification).
class AudioMode {
  AudioMode._();

  static const MethodChannel _ch = MethodChannel('animax/app');
  static http.Client? _client;
  static http.Client get _http => _client ??= createHttpClient();

  static bool get on => AppPrefs.I.audioOnly;

  /// Starts / stops the playback keep-alive service.
  static Future<void> keepAlive(bool active, {String title = ''}) async {
    try {
      await _ch.invokeMethod<bool>('audioKeepAlive', <String, dynamic>{
        'on': active,
        'title': title,
      });
    } catch (_) {}
  }

  /// For an HLS master playlist: the URL of its audio-only rendition, else
  /// its lowest-bandwidth variant. Returns [url] unchanged when it is not a
  /// master playlist or cannot be read.
  static Future<String> lightestHls(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final http.Response r = await _http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode >= 400) return url;
      return pickLightest(url, utf8.decode(r.bodyBytes, allowMalformed: true));
    } catch (_) {
      return url;
    }
  }

  /// Pure part of [lightestHls] (unit-tested).
  static String pickLightest(String url, String body) {
    if (!body.contains('#EXT-X-STREAM-INF')) return url;
    final Uri base = Uri.parse(url);
    // 1. Audio rendition: #EXT-X-MEDIA:TYPE=AUDIO,…,URI="…"
    for (final String line in const LineSplitter().convert(body)) {
      if (line.startsWith('#EXT-X-MEDIA') && line.contains('TYPE=AUDIO')) {
        final RegExpMatch? m = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (m != null) return base.resolve(m.group(1)!).toString();
      }
    }
    // 2. Lowest-bandwidth variant (audio-only variants have no RESOLUTION).
    final List<String> lines = const LineSplitter().convert(body);
    String? best;
    int bestBw = 1 << 62;
    bool bestAudioOnly = false;
    for (int i = 0; i < lines.length - 1; i++) {
      final String l = lines[i];
      if (!l.startsWith('#EXT-X-STREAM-INF')) continue;
      final int bw =
          int.tryParse(
            RegExp(r'[^-]BANDWIDTH=(\d+)').firstMatch(',$l')?.group(1) ?? '',
          ) ??
          (1 << 61);
      final bool audioOnly =
          !l.contains('RESOLUTION=') &&
          (l.contains('mp4a') && !l.contains('avc') && !l.contains('hvc'));
      String next = '';
      for (int j = i + 1; j < lines.length; j++) {
        final String n = lines[j].trim();
        if (n.isEmpty || n.startsWith('#')) continue;
        next = n;
        break;
      }
      if (next.isEmpty) continue;
      if ((audioOnly && !bestAudioOnly) ||
          (audioOnly == bestAudioOnly && bw < bestBw)) {
        best = next;
        bestBw = bw;
        bestAudioOnly = audioOnly;
      }
    }
    return best == null ? url : base.resolve(best).toString();
  }
}

/// Shown instead of the picture while sound-only mode is on.
class AudioOnlyCover extends StatelessWidget {
  const AudioOnlyCover({
    super.key,
    required this.poster,
    required this.title,
    this.onExit,
  });

  final String poster;
  final String title;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (poster.isNotEmpty)
          Opacity(
            opacity: 0.35,
            child: Image.network(
              poster,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            ),
          ),
        const ColoredBox(color: Color(0x88000000)),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGrad,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.headphones_rounded,
                  size: 46,
                  color: Color(0xFF07130D),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'وضع الصوت فقط',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: kFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'أقل استهلاك للبيانات — يستمر مع إطفاء الشاشة',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: kFont,
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
              if (onExit != null) ...<Widget>[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onExit,
                  icon: const Icon(Icons.videocam_rounded, color: Colors.white),
                  label: const Text(
                    'عرض الفيديو',
                    style: TextStyle(fontFamily: kFont, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
