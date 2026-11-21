import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'fast_start.dart';

/// Opening sequence of an episode (seconds in that episode's timeline).
class IntroRange {
  const IntroRange(this.start, this.end);
  final double start;
  final double end;
  double get length => end - start;

  Map<String, dynamic> toJson() => <String, dynamic>{'s': start, 'e': end};
  static IntroRange? fromJson(Object? j) => j is Map
      ? IntroRange((j['s'] as num).toDouble(), (j['e'] as num).toDouble())
      : null;

  @override
  String toString() => 'IntroRange(${start.toStringAsFixed(2)}–${end.toStringAsFixed(2)})';
}

/// Finds the intro of a series episode **without decoding any audio or
/// video**, from two episodes' MP4 indexes only:
///
/// 1. Keyframe rhythm — an identical opening sequence is cut into GOPs at
///    the same places in every episode, so the gaps between keyframes match
///    for its whole length and diverge right where the episode begins.
/// 2. Frame-size fingerprint — identical pictures compress to (almost) the
///    same sizes; ≥ 60 % of frames in the matched span must agree to confirm.
///
/// Verified on Akwam: «احتمال حب» eps 1–3 → 0.00–77.96 s (the black cut
/// after the credits, frame-checked), «ما زلت في 17» (no intro) → none.
class IntroDetector {
  IntroDetector._();

  static const double minLength = 15;
  static const double maxLength = 180;
  static const double searchSeconds = 420; // the intro is in the first 7 min

  /// Pure core. [sizesA]/[sizesB] are frame sizes from frame 0; keyframe
  /// lists are presentation times. Returns the intro in A's timeline.
  static IntroRange? detect({
    required List<double> keysA,
    required List<int> sizesA,
    required double frameA,
    required List<double> keysB,
    required List<int> sizesB,
    required double frameB,
  }) {
    final double tol = 1.5 * math.max(frameA, frameB);
    final List<double> ka = keysA.where((double t) => t < searchSeconds).toList();
    final List<double> kb = keysB.where((double t) => t < searchSeconds).toList();
    if (ka.length < 4 || kb.length < 4) return null;
    final List<double> da = <double>[for (int i = 1; i < ka.length; i++) ka[i] - ka[i - 1]];
    final List<double> db = <double>[for (int i = 1; i < kb.length; i++) kb[i] - kb[i - 1]];
    double bestDur = 0;
    int bi = 0, bj = 0, br = 0;
    for (int i = 0; i < da.length; i++) {
      for (int j = 0; j < db.length; j++) {
        int r = 0;
        while (i + r < da.length && j + r < db.length && (da[i + r] - db[j + r]).abs() <= tol) {
          r++;
        }
        if (r >= 3) {
          final double dur = ka[i + r] - ka[i];
          if (dur > bestDur) {
            bestDur = dur;
            bi = i;
            bj = j;
            br = r;
          }
        }
      }
    }
    if (bestDur < minLength || bestDur > maxLength) return null;
    final double start = math.max(0, ka[bi]);
    final double end = ka[bi + br];
    final double offset = kb[bj] - ka[bi];
    // Confirm with the frame-size fingerprint: 1-second sums of frame sizes
    // (robust to shifted GOPs) must agree far better than at wrong
    // alignments. Real intros score ~1.0 vs ~0.15–0.35 noise.
    final double score = _sizeScore(sizesA, frameA, sizesB, frameB, start, end, offset, 0);
    final List<double> noise = <double>[
      for (final int sh in <int>[-50, -37, -25, 25, 37, 50])
        _sizeScore(sizesA, frameA, sizesB, frameB, start, end, offset, sh)
    ]..sort();
    final double noiseMedian = (noise[2] + noise[3]) / 2;
    if (score < 0.7 || score < noiseMedian + 0.3) return null;
    return IntroRange(start, end);
  }

  /// Share of 1-second windows in [start, end) whose summed frame sizes
  /// agree within ±15 % between A and B (B shifted by [offset] s and
  /// [shiftFrames] frames).
  static double _sizeScore(List<int> a, double fa, List<int> b, double fb,
      double start, double end, double offset, int shiftFrames) {
    final int w = math.max(1, (1 / fa).round());
    int hits = 0, total = 0;
    for (int f = (start / fa).floor(); f + w <= (end / fa).floor(); f += w) {
      final int g = ((f * fa + offset) / fb).round() + shiftFrames;
      if (g < 0 || g + w > b.length || f + w > a.length) break;
      int sa = 0, sb = 0;
      for (int k = 0; k < w; k++) {
        sa += a[f + k];
        sb += b[g + k];
      }
      total++;
      if ((math.log(sa + 1) - math.log(sb + 1)).abs() < 0.15) hits++;
    }
    return total < 10 ? 0 : hits / total;
  }

  static final Map<String, IntroRange?> _memo = <String, IntroRange?>{};

  /// Intro of the episode at [url], compared with a neighbouring episode at
  /// [neighbourUrl] (same quality). ~50 KB of index data per episode; the
  /// result is cached on the device per episode [cacheKey].
  static Future<IntroRange?> forEpisode({
    required String cacheKey,
    required String url,
    required List<String> neighbourUrls,
    required Map<String, String> headers,
  }) async {
    if (_memo.containsKey(cacheKey)) return _memo[cacheKey];
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final String? raw = sp.getString('intro.$cacheKey');
    if (raw != null) {
      final Object? j = jsonDecode(raw);
      return _memo[cacheKey] = j == null ? null : IntroRange.fromJson(j);
    }
    final Mp4Index me = await FastStart.index(url, headers);
    final List<int> mine =
        await me.videoFrameSizes(0, (searchSeconds / me.frameSeconds).round());
    IntroRange? r;
    // Some episodes differ (special opening): try up to two neighbours.
    for (final String n in neighbourUrls.take(2)) {
      try {
        final Mp4Index other = await FastStart.index(n, headers);
        r = detect(
          keysA: me.keyframeTimes,
          sizesA: mine,
          frameA: me.frameSeconds,
          keysB: other.keyframeTimes,
          sizesB: await other
              .videoFrameSizes(0, (searchSeconds / other.frameSeconds).round()),
          frameB: other.frameSeconds,
        );
      } catch (_) {
        r = null;
      }
      if (r != null) break;
    }
    await sp.setString('intro.$cacheKey', jsonEncode(r?.toJson()));
    return _memo[cacheKey] = r;
  }
}
