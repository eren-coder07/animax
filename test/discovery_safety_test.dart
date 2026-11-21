import 'dart:convert';

import 'package:animax/core/social.dart';
import 'package:flutter_test/flutter_test.dart';

String enc(String k) => base64Url.encode(utf8.encode(k)).replaceAll('=', '');

void main() {
  test('top items decode their keys and keep only supported kinds', () {
    final TopItem? a = TopItem.from(
      enc('akwam:/movie/11708/steps'),
      <String, dynamic>{
        'title': 'Steps',
        'poster': 'p',
        'kind': 'akwam',
        'views': 12,
      },
    );
    expect(a!.ref, '/movie/11708/steps');
    expect(a.views, 12);
    final TopItem? m = TopItem.from(enc('manga:abc-123'), <String, dynamic>{
      'title': 'M',
      'kind': 'manga',
    });
    expect(m!.ref, 'abc-123');
    // +18 and untitled rows never reach the general home row.
    expect(
      TopItem.from(enc('hh:slug'), <String, dynamic>{
        'title': 'x',
        'kind': 'hh',
      }),
      isNull,
    );
    expect(
      TopItem.from(enc('anime:1'), <String, dynamic>{'kind': 'anime'}),
      isNull,
    );
    expect(TopItem.from('%%%', <String, dynamic>{'title': 'x'}), isNull);
  });

  test('hidden clips and blocked users are filtered', () {
    VideoClip c(String id, String uid) => VideoClip(
      id: id,
      uid: uid,
      title: 't',
      kind: 'akwam',
      source: 'akwam',
      ref: const <String, String>{},
      startMs: 0,
      endMs: 1,
    );
    Blocks.I.hideClip('c2');
    final List<VideoClip> out = Blocks.I.visibleClips(<VideoClip>[
      c('c1', 'a'),
      c('c2', 'b'),
      c('c3', 'c'),
    ]);
    expect(out.map((VideoClip x) => x.id), <String>['c1', 'c3']);
    expect(Blocks.I.isBlocked(''), isFalse);
  });
}
