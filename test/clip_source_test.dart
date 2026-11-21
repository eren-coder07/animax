import 'package:animax/core/akwam_api.dart';
import 'package:animax/screens/clips_screen.dart';
import 'package:flutter_test/flutter_test.dart';

AkwamItem _it(String title, String path) =>
    AkwamItem(id: '1', path: path, kind: AkwamKind.movie, title: title);

void main() {
  test('movie watch path maps to its movie page without a request', () async {
    final AkwamItem? it = await AkwamApi.I
        .itemForWatch('/watch/185190/11708/steps', title: 'Steps', poster: 'p');
    expect(it, isNotNull);
    expect(it!.path, '/movie/11708/steps');
    expect(it.kind, AkwamKind.movie);
    expect(it.title, 'Steps');
    expect(it.poster, 'p');
  });

  test('non-watch paths are ignored', () async {
    expect(await AkwamApi.I.itemForWatch('/movie/1/x'), isNull);
    expect(await AkwamApi.I.itemForWatch(''), isNull);
  });

  test('title search only accepts an exact match', () {
    final List<AkwamItem> r = <AkwamItem>[
      _it('Perfect Liars مدبلج', '/movie/2/a'),
      _it('Steps', '/movie/3/b'),
    ];
    expect(bestAkwamMatch(r, '  steps ')?.path, '/movie/3/b');
    expect(bestAkwamMatch(r, 'ما زلت في 17 مدبلج'), isNull);
    expect(bestAkwamMatch(const <AkwamItem>[], 'x'), isNull);
  });

  test('bad percent-encoding in a stored path does not throw', () {
    expect(AkwamApi.itemFromPath('/series/5/100%-love')?.title, '100%-love');
  });
}
