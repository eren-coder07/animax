import 'dart:async';

import 'package:flutter/material.dart';

import 'app_prefs.dart';
import 'social.dart';

/// Binge (marathon) mode: when an episode ends the next one starts after a
/// 5-second countdown (cancelable), intros are skipped and every finished
/// episode counts toward the marathon streak and the Bingo card.
class Binge {
  Binge._();

  static final Set<String> _handled = <String>{};
  static Timer? _timer;

  static bool get on => AppPrefs.I.bingeMode;

  /// Call when playback of [episodeKey] completes. [next] opens the next
  /// episode (null when there is none).
  static void episodeEnded(BuildContext context,
      {required String episodeKey, VoidCallback? next}) {
    if (!_handled.add(episodeKey)) return; // completion fires repeatedly
    if (!on) {
      next?.call();
      return;
    }
    BingeStore.I.episodeFinished();
    if (next == null) return;
    final ScaffoldMessengerState? m = ScaffoldMessenger.maybeOf(context);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), next);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      content: Text(
          '⚡ ماراثون — الحلقة التالية خلال 5 ثوانٍ (${BingeStore.I.session} متتالية)'),
      duration: const Duration(seconds: 5),
      persist: false,
      action: SnackBarAction(label: 'إلغاء', onPressed: cancel),
    ));
  }

  static void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// A new episode started: allow its completion to be handled again.
  static void started(String episodeKey) => _handled.remove(episodeKey);
}
