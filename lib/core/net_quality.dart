import 'dart:async';

import 'package:flutter/services.dart';

import 'app_prefs.dart';

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
  static bool get isSlow => AppPrefs.I.dataSaver || _slow;

  static Future<bool> check() async {
    if (AppPrefs.I.dataSaver) return true;
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
