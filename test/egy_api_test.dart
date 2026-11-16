import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:animax/core/egy_api.dart';

/// EgyDead API parsing — verified against the live HAR capture
/// (2026-11-15, user's browser session) stored in test/fixtures/egy/.
void main() {
  group('EgyTitle list parsing (channel payload)', () {
    test('channel_5381 parses into titles with primary videos', () async {
      final String raw = await File(
              'test/fixtures/egy/channel_5381.json')
          .readAsString();
      final dynamic body = jsonDecode(raw);
      final api = EgyApi.I;

      // _parseTitleList is private; exercise via the shape it must understand.
      final List<EgyTitle> titles = api.channelItemsForTest(body);
      expect(titles, isNotEmpty);
      expect(titles.length, 10);

      final EgyTitle first = titles.first;
      expect(first.id, 5531);
      expect(first.name, contains('Union County'));
      expect(first.poster, startsWith('https://image.tmdb.org'));
      expect(first.isSeries, isFalse);
      expect(first.rating, 7.2);
      expect(first.runtime, 97);
      expect(first.year, 2026);
      expect(first.primaryVideoId, 25100);
    });

    test('next page detection', () async {
      final dynamic body =
          jsonDecode(await File('test/fixtures/egy/channel_5381.json').readAsString());
      expect(EgyApi.I.nextPageForTest(body), isNull); // total=10, single page
    });
  });

  group('EgyTitle detail parsing', () {
    test('title_5540 parses with genres + images', () async {
      final dynamic body =
          jsonDecode(await File('test/fixtures/egy/title_5540.json').readAsString());
      final Map<String, dynamic> tm = Map<String, dynamic>.from(body['title']);
      final EgyTitle t = EgyTitle.fromJson(tm);
      expect(t.id, 5540);
      expect(t.originalTitle, 'Matchbox the Movie');
      expect(t.isSeries, isFalse);
      expect(t.genres, contains('حركة'));
      expect(t.images, isNotEmpty);
      expect(t.certification, 'pg-13');
    });
  });

  group('Watch payload', () {
    test('watch_25156 yields embed src + servers', () async {
      final dynamic body =
          jsonDecode(await File('test/fixtures/egy/watch_25156.json').readAsString());
      final Map<String, dynamic> m = Map<String, dynamic>.from(body);
      final EgyVideo video =
          EgyVideo.fromJson(Map<String, dynamic>.from(m['video']));
      expect(video.src, 'https://egybestvid.com/embed-71h1ddovyf7t.html');
      expect(video.type, 'embed');

      final List<EgyVideo> alt = <EgyVideo>[
        for (final dynamic v in (m['alternative_videos'] as List<dynamic>))
          EgyVideo.fromJson(Map<String, dynamic>.from(v)),
      ];
      final EgyWatch w = EgyWatch(video: video, alternatives: alt);
      expect(w.servers, isNotEmpty);
      expect(w.servers.first.id, 25156);
    });
  });

  group('Embed page stream extraction', () {
    test('extracts the live master.m3u8 with signed query', () async {
      final String html =
          await File('test/fixtures/egy/embed_page.html').readAsString();
      final String? url = EgyApi.extractEmbedFile(html);
      expect(url, isNotNull);
      expect(url, contains('master.m3u8'));
      expect(url!.startsWith('https://s1.egybestvid.com/hls2/'), isTrue);
      expect(url.contains('e=50400'), isTrue);
    });

    test('handles single-quoted and source-tag variants', () {
      expect(
          EgyApi.extractEmbedFile(
              r"""sources: [{file:'https://cdn.example.com/v.m3u8?x=1'}]"""),
          'https://cdn.example.com/v.m3u8?x=1');
      expect(
          EgyApi.extractEmbedFile(
              r'<source src="https://cdn.example.com/a.mp4">'),
          'https://cdn.example.com/a.mp4');
      expect(EgyApi.extractEmbedFile('<html>nothing here</html>'), isNull);
    });
  });

  group('ResolvedStream', () {
    test('HLS detection', () {
      expect(const ResolvedStream(url: 'https://x/y/master.m3u8?t=1').isHls,
          isTrue);
      expect(const ResolvedStream(url: 'https://x/y/video.mp4').isHls, isFalse);
    });
  });

  group('Episode parsing', () {
    test('season payload with videos + primary_video fallback', () async {
      final api = EgyApi.I;
      final List<EgyEpisode> eps = api.seasonForTest(<dynamic, dynamic>{
        'episodes': <dynamic>[
          <dynamic, dynamic>{
            'id': 9001,
            'name': 'Pilot',
            'episode_num': 1,
            'videos': <dynamic>[
              <dynamic, dynamic>{
                'id': 11,
                'name': 'السيرفر الاول',
                'src': 'https://egybestvid.com/embed-abc.html',
                'type': 'embed',
              },
            ],
          },
          <dynamic, dynamic>{
            'id': 9002,
            'name': 'Episode 2',
            'episode_num': 2,
            'primary_video': <dynamic, dynamic>{
              'id': 12,
              'name': 'السيرفر الاول',
              'src': 'https://egybestvid.com/embed-def.html',
              'type': 'embed',
            },
          },
        ],
      });
      expect(eps.length, 2);
      expect(eps[0].number, 1);
      expect(eps[0].videos.first.src, contains('embed-abc'));
      expect(eps[1].videos.first.id, 12);
    });
  });
}
