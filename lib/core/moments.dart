import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cloud.dart';

/// Per-episode community layer shared by every player:
///
/// ```
/// moments/{ek}/{clipId}   startSec   — "hot moments" (where people clip)
/// tcomments/{ek}/{id}     {uid, name, text, t, at} — comments pinned to a
///                                     second of the episode
/// ```
/// `ek` = [CloudDb.key] of an episode key from [episodeKey].
class Moments {
  Moments._();

  /// Stable key of the *episode* (or movie) a source points at — the same
  /// for every quality / server of it.
  ///  * akwam: `/watch/{file}/{id}/…` → `akwam:{id}` (episode or movie id)
  ///  * anime: `anime:{watchId}:{ep}`
  ///  * hh:    `hh:{slug}:{ep}`
  static String episodeKey(String source, Map<String, String> ref) {
    switch (source) {
      case 'akwam':
        final RegExpMatch? m =
            RegExp(r'^/watch/\d+/(\d+)').firstMatch(ref['path'] ?? '');
        return m == null ? '' : 'akwam:${m.group(1)}';
      case 'anime':
        final String w = ref['watchId'] ?? '';
        return w.isEmpty ? '' : 'anime:$w:${ref['ep'] ?? '1'}';
      case 'hh':
        final String s = ref['slug'] ?? '';
        return s.isEmpty ? '' : 'hh:$s:${ref['ep'] ?? '1'}';
    }
    return '';
  }

  static final Map<String, ({List<int> secs, DateTime at})> _cache =
      <String, ({List<int> secs, DateTime at})>{};

  /// Start seconds of every clip cut from this episode.
  static Future<List<int>> load(String ek, {bool fresh = false}) async {
    if (ek.isEmpty) return const <int>[];
    final ({List<int> secs, DateTime at})? hit = _cache[ek];
    if (!fresh && hit != null && DateTime.now().difference(hit.at).inSeconds < 60) {
      return hit.secs;
    }
    final dynamic v = await CloudDb.I.get('moments/${CloudDb.key(ek)}');
    final List<int> out = <int>[];
    if (v is Map) {
      for (final dynamic s in v.values) {
        if (s is num && s >= 0) out.add(s.toInt());
      }
    }
    out.sort();
    _cache[ek] = (secs: out, at: DateTime.now());
    return out;
  }

  static void forget(String ek) => _cache.remove(ek);

  /// Buckets [secs] into [bins] slots over [durationSec] (0..1 heat each).
  static List<double> heat(List<int> secs, int durationSec, {int bins = 48}) {
    final List<double> h = List<double>.filled(bins, 0);
    if (durationSec <= 0 || secs.isEmpty) return h;
    for (final int s in secs) {
      if (s > durationSec) continue;
      // A clip covers ~10 s: spread its weight over neighbouring bins.
      final double pos = (s + 5) / durationSec * bins;
      for (int i = 0; i < bins; i++) {
        final double d = (i + 0.5 - pos).abs();
        if (d < 2.5) h[i] += 1 - d / 2.5;
      }
    }
    final double mx = h.fold<double>(0, (double a, double b) => b > a ? b : a);
    if (mx <= 0) return h;
    return h.map((double v) => v / mx).toList();
  }

  /// The most clipped second (start of the hottest window), or null.
  static int? peak(List<int> secs, int durationSec) {
    if (secs.isEmpty) return null;
    int best = secs.first, bestN = 0;
    for (final int s in secs) {
      if (durationSec > 0 && s > durationSec) continue;
      final int n = secs.where((int o) => (o - s).abs() <= 15).length;
      if (n > bestN) {
        bestN = n;
        best = s;
      }
    }
    return best;
  }
}

/// A comment pinned to second [t] of an episode.
class TimedComment {
  const TimedComment({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.t,
  });
  final String id;
  final String uid;
  final String name;
  final String text;
  final int t;

  static TimedComment fromJson(String id, Map<dynamic, dynamic> j) => TimedComment(
        id: id,
        uid: (j['uid'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        t: ((j['t'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      );
}

/// Loads / posts the timed comments of one episode and the hot moments,
/// for the player overlay. One instance per opened episode.
class EpisodeSocial extends ChangeNotifier {
  EpisodeSocial(this.ek) {
    if (ek.isNotEmpty) unawaited(refresh());
  }

  final String ek;
  List<int> moments = const <int>[];
  List<TimedComment> comments = const <TimedComment>[];
  bool loaded = false;
  bool _disposed = false;

  static const int maxText = 120;

  Future<void> refresh() async {
    try {
      final List<dynamic> r = await Future.wait(<Future<dynamic>>[
        Moments.load(ek),
        CloudDb.I.get('tcomments/${CloudDb.key(ek)}', query: <String, String>{
          'orderBy': '"\$key"',
          'limitToLast': '400',
        }),
      ]);
      moments = r[0] as List<int>;
      final List<TimedComment> cs = <TimedComment>[];
      if (r[1] is Map) {
        (r[1] as Map<dynamic, dynamic>).forEach((dynamic id, dynamic c) {
          if (c is Map) cs.add(TimedComment.fromJson(id.toString(), c));
        });
      }
      cs.sort((TimedComment a, TimedComment b) => a.t.compareTo(b.t));
      comments = cs;
    } catch (_) {}
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  /// Posts [text] at second [t]. Throws [CloudException] (e.g. not signed in).
  Future<void> post(int t, String text) async {
    final CloudUser? u = CloudAuth.I.user;
    if (u == null) {
      throw CloudException('سجّل الدخول لاستخدام هذه الميزة.', code: 'login');
    }
    final String s = text.trim();
    if (s.isEmpty) throw CloudException('اكتب تعليقًا أولًا.');
    if (s.length > maxText) {
      throw CloudException('التعليق طويل جدًا ($maxText حرفًا كحد أقصى).');
    }
    final String id = await CloudDb.I.push('tcomments/${CloudDb.key(ek)}',
        <String, dynamic>{
          'uid': u.uid,
          'name': u.name,
          'text': s,
          't': t,
          'at': serverTime,
        });
    comments = <TimedComment>[
      ...comments,
      TimedComment(id: id, uid: u.uid, name: u.name, text: s, t: t),
    ]..sort((TimedComment a, TimedComment b) => a.t.compareTo(b.t));
    if (!_disposed) notifyListeners();
  }

  Future<void> delete(TimedComment c) async {
    if (c.uid != CloudAuth.I.user?.uid) return;
    await CloudDb.I.delete('tcomments/${CloudDb.key(ek)}/${c.id}');
    comments = comments.where((TimedComment x) => x.id != c.id).toList();
    if (!_disposed) notifyListeners();
  }

  /// Comments whose moment is within the last [window] seconds of [pos].
  List<TimedComment> activeAt(double pos, {double window = 7}) => comments
      .where((TimedComment c) => c.t <= pos && pos - c.t < window)
      .toList();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
