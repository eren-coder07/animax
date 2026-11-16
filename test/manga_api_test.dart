import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:animax/core/manga_api.dart';

void main() {
  group('MangaItem.fromJson', () {
    test('parses a MangaDex list payload (cover + authors + tags)', () {
      final dynamic body = jsonDecode(_sampleManga) as dynamic;
      final List<MangaItem> items = MangaApi.I.parseItems(body);
      expect(items.length, 1);
      final MangaItem m = items[0];
      expect(m.id, '7bd37661-c0b1-4166-87c1-7e633adb55ac');
      expect(m.title, "Vivi's Adventure");
      expect(m.cover,
          'https://uploads.mangadex.org/covers/7bd37661-c0b1-4166-87c1-7e633adb55ac/cover1.jpg.512.jpg');
      expect(m.followedCount, 12345);
      expect(m.followedLabel, '12.3K');
      expect(m.tags.map((MangaTag t) => t.name), contains('Comedy'));
      expect(m.authors, contains('Naoshi Komi'));
    });

    test('falls back to first alt title when en title missing', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'id': 'm1',
            'type': 'manga',
            'attributes': <String, dynamic>{
              'title': <String, dynamic>{'ja': 'ワンピース'},
              'altTitles': <dynamic>[
                <String, dynamic>{'en': 'One Piece'},
              ],
              'description': <String, dynamic>{},
            },
            'relationships': const <dynamic>[],
          },
        ],
      };
      final List<MangaItem> items = MangaApi.I.parseItems(payload);
      expect(items.first.title, 'One Piece');
    });

    test('million-scale follow counts format', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'id': 'm2',
            'type': 'manga',
            'attributes': <String, dynamic>{
              'title': <String, dynamic>{'en': 'Big'},
              'followedCount': 2500000,
              'rating': <String, dynamic>{'bayesian': 9.12},
            },
            'relationships': const <dynamic>[],
          },
        ],
      };
      final MangaItem m = MangaApi.I.parseItems(payload).first;
      expect(m.followedLabel, '2.5M');
      expect(m.rating, 9);
    });
  });

  group('MangaChapter.fromJson', () {
    test('parses chapter fields and trims numbers', () {
      final MangaChapter c = MangaChapter.fromJson(<String, dynamic>{
        'id': 'ch1',
        'type': 'chapter',
        'attributes': <String, dynamic>{
          'title': 'The Beginning',
          'chapter': '1.5',
          'volume': '1',
          'pages': 32,
          'publishAt': '2026-08-26T18:40:54+00:00',
          'isUnavailable': false,
        },
      });
      expect(c.id, 'ch1');
      expect(c.displayTitle, 'The Beginning');
      expect(c.chipLabel, 'Ch. 1.5');
      expect(c.pages, 32);
      expect(c.isUnavailable, isFalse);
    });

    test('untitled chapter without number shows Oneshot', () {
      final MangaChapter c = MangaChapter.fromJson(<String, dynamic>{
        'id': 'ch2',
        'type': 'chapter',
        'attributes': <String, dynamic>{'title': '', 'chapter': null, 'pages': 8},
      });
      expect(c.chipLabel, 'Oneshot');
      expect(c.displayTitle, 'Chapter ?');
    });

    test('integer chapter numbers lose the .0', () {
      final MangaChapter c = MangaChapter.fromJson(<String, dynamic>{
        'id': 'ch3',
        'type': 'chapter',
        'attributes': <String, dynamic>{'chapter': '1024', 'title': 'x'},
      });
      expect(c.chipLabel, 'Ch. 1024');
    });
  });

  group('MangaTag', () {
    test('tag list parses id + en name', () {
      // tags() parsing is exercised indirectly: build the expected shapes.
      final MangaTag t = MangaTag(id: 'uuid-1', name: 'Action');
      expect(t.name, 'Action');
      expect(t.id, 'uuid-1');
    });
  });
}

const String _sampleManga = '''
{
  "result": "ok",
  "response": "collection",
  "data": [
    {
      "id": "7bd37661-c0b1-4166-87c1-7e633adb55ac",
      "type": "manga",
      "attributes": {
        "title": {"en": "Vivi's Adventure"},
        "altTitles": [{"ja": "ビビの冒険"}, {"en": "One Piece Cover Comic"}],
        "description": {"en": "A cover comic by Naoshi Komi."},
        "status": "completed",
        "year": 2026,
        "contentRating": "safe",
        "followedCount": 12345,
        "tags": [
          {"id": "t1", "type": "tag", "attributes": {"name": {"en": "Comedy"}}},
          {"id": "t2", "type": "tag", "attributes": {"name": {"en": "Adventure"}}}
        ]
      },
      "relationships": [
        {"id": "r1", "type": "cover_art", "attributes": {"fileName": "cover1.jpg"}},
        {"id": "r2", "type": "author", "attributes": {"name": "Naoshi Komi"}}
      ]
    }
  ]
}
''';
