import 'package:animax/core/manga_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('titles with string numbers (lastChapter: "120") are not dropped', () {
    final List<MangaItem> items = MangaApi.I.parseItems(<String, dynamic>{
      'data': <dynamic>[
        <String, dynamic>{
          'id': 'a1',
          'type': 'manga',
          'attributes': <String, dynamic>{
            'title': <String, dynamic>{'en': 'One'},
            'lastChapter': '120',
            'followedCount': 5,
          },
          'relationships': <dynamic>[],
        },
        <String, dynamic>{
          'id': 'a2',
          'type': 'manga',
          'attributes': <String, dynamic>{
            'title': <String, dynamic>{'en': 'Two'},
            'lastChapter': '',
            'rating': <String, dynamic>{'bayesian': '8.6'},
          },
          'relationships': <dynamic>[],
        },
      ],
    });
    expect(items.length, 2);
    expect(items.first.chapterCount, 120);
    expect(items[1].chapterCount, 0);
  });
}
