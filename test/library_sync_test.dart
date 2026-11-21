import 'package:animax/core/library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('progress + history survive an app restart (regression)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final LibraryStore a = LibraryStore.debugFresh();
    await a.load();
    a.saveProgress(
      key: 'akwam:/movie/1/x',
      sub: '0',
      positionSec: 600,
      durationSec: 6000,
    );
    a.pushHistory(
      key: 'akwam:/movie/1/x',
      title: 'X',
      poster: '',
      kind: 'akwam',
      sub: '0',
      label: 'فيلم',
    );
    final SharedPreferences sp = await SharedPreferences.getInstance();
    SharedPreferences.setMockInitialValues(<String, Object>{
      for (final String k in sp.getKeys()) k: sp.get(k)!,
    });
    final LibraryStore b = LibraryStore.debugFresh();
    await b.load();
    expect(b.progressOf('akwam:/movie/1/x', '0')?.positionSec, 600);
    expect(b.history.length, 1);
  });

  test('old map-shaped progress still loads', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lib.progress': '{"anime:x@3":{"key":"anime:x","sub":"3","pos":42,"dur":1400,"w":false,"at":5}}',
    });
    final LibraryStore s = LibraryStore.debugFresh();
    await s.load();
    expect(s.progressOf('anime:x', '3')?.positionSec, 42);
  });

  group('cloud merge', () {
    late LibraryStore phone;
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      phone = LibraryStore.debugFresh();
      await phone.load();
    });

    test('newer progress wins, older is ignored, history unions', () {
      phone.saveProgress(
        key: 'anime:a',
        sub: '1',
        positionSec: 100,
        durationSec: 1400,
      );
      final int later = DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch;
      final bool changed = phone.mergeJson(<String, dynamic>{
        'progress': <dynamic>[
          <String, dynamic>{
            'key': 'anime:a',
            'sub': '1',
            'pos': 900,
            'dur': 1400,
            'at': later,
          },
          <String, dynamic>{
            'key': 'anime:b',
            'sub': '2',
            'pos': 50,
            'dur': 1400,
            'at': 1,
          },
        ],
        'history': <dynamic>[
          <String, dynamic>{
            'key': 'anime:b',
            'title': 'B',
            'poster': '',
            'kind': 'anime',
            'sub': '2',
            'label': 'ح 2',
            'at': later,
          },
        ],
      });
      expect(changed, isTrue);
      expect(phone.progressOf('anime:a', '1')?.positionSec, 900);
      expect(phone.progressOf('anime:b', '2')?.positionSec, 50);
      expect(phone.history.first.key, 'anime:b');
      // Same snapshot again → nothing new.
      expect(
        phone.mergeJson(<String, dynamic>{
          'progress': <dynamic>[
            <String, dynamic>{
              'key': 'anime:a',
              'sub': '1',
              'pos': 10,
              'dur': 1400,
              'at': 2,
            },
          ],
        }),
        isFalse,
      );
      expect(phone.progressOf('anime:a', '1')?.positionSec, 900);
    });

    test('list removals sync; re-adding later wins over an old removal', () {
      phone.setListStatus(
        key: 'akwam:/series/1/s',
        title: 'S',
        poster: '',
        kind: 'akwam',
        status: LibStatus.values.first,
      );
      final int later = DateTime.now()
          .add(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      phone.mergeJson(<String, dynamic>{
        'removed': <String, int>{'akwam:/series/1/s': later},
      });
      expect(phone.isListed('akwam:/series/1/s'), isFalse);
      // A stale entry from another phone does not resurrect it.
      phone.mergeJson(<String, dynamic>{
        'entries': <dynamic>[
          <String, dynamic>{
            'key': 'akwam:/series/1/s',
            'title': 'S',
            'poster': '',
            'kind': 'akwam',
            'status': LibStatus.values.first.key,
            'updatedAt': 10,
          },
        ],
      });
      expect(phone.isListed('akwam:/series/1/s'), isFalse);
      // Re-adding locally clears the tombstone.
      phone.setListStatus(
        key: 'akwam:/series/1/s',
        title: 'S',
        poster: '',
        kind: 'akwam',
        status: LibStatus.values.first,
      );
      expect(phone.isListed('akwam:/series/1/s'), isTrue);
      expect(
        (phone.exportJson()['removed'] as Map<String, int>).containsKey(
          'akwam:/series/1/s',
        ),
        isFalse,
      );
    });
  });
}
