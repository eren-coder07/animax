import 'dart:convert';
import 'dart:io';

import 'package:animax/core/intro_detect.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real Akwam index data (keyframe times + frame sizes, first 4 minutes) of
/// episodes 2 and 3 of two series.
void main() {
  final Map<String, dynamic> fx = jsonDecode(
    File('test/fixtures/intro_fingerprints.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  IntroRange? run(String a, String b) {
    final Map<String, dynamic> x = fx[a] as Map<String, dynamic>,
        y = fx[b] as Map<String, dynamic>;
    return IntroDetector.detect(
      keysA: (x['keys'] as List<dynamic>)
          .cast<num>()
          .map((num n) => n.toDouble())
          .toList(),
      sizesA: (x['sizes'] as List<dynamic>).cast<int>(),
      frameA: (x['fs'] as num).toDouble(),
      keysB: (y['keys'] as List<dynamic>)
          .cast<num>()
          .map((num n) => n.toDouble())
          .toList(),
      sizesB: (y['sizes'] as List<dynamic>).cast<int>(),
      frameB: (y['fs'] as num).toDouble(),
    );
  }

  test(
    'finds the opening credits of «احتمال حب» (0 – 77.96 s, frame-checked)',
    () {
      final IntroRange? r = run('5695#2', '5695#3');
      expect(r, isNotNull);
      expect(r!.start, closeTo(0, 0.1));
      expect(r.end, closeTo(77.96, 0.05));
      expect(run('5695#3', '5695#2')!.end, closeTo(77.96, 0.05));
    },
  );

  test(
    'later episodes: GOPs shifted by 0.28 s after a different logo (eps 41/42)',
    () {
      final IntroRange? r = run('5695#41', '5695#42');
      expect(r, isNotNull);
      expect(r!.end, closeTo(78.12, 0.05));
      expect(r.start, lessThan(15));
    },
  );

  test(
    'no false intro for «ما زلت في 17» (only a 10 s channel logo is shared)',
    () {
      expect(run('5744#2', '5744#3'), isNull);
    },
  );

  test('different series never match', () {
    expect(run('5695#2', '5744#3'), isNull);
  });
}
