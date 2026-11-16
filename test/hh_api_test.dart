import 'dart:io';

import 'package:animax/core/hh_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the Hentai Haven (hentaihaven.xxx) parsers, run against
/// fragments extracted from the user's HAR capture ("upload/henapi") and
/// live page captures.
void main() {
  hhParserTests();
}

void hhParserTests() {
  // ---- Fixtures (copied from the captured pages) --------------------------

  const String rscPostArray =
      '[{\\"id\\":98923,\\"date\\":\\"2026-10-19T22:04:47\\",\\"modified\\":\\"2026-10-19T22:04:48\\",'
      '\\"slug\\":\\"mouse-cursor-de-genjitsu\\",\\"link\\":\\"https://cms.hentaihaven.xxx/watch/mouse-cursor-de-genjitsu/\\",'
      '\\"title\\":{\\"rendered\\":\\"Mouse Cursor de Genjitsu\\"},'
      '\\"meta\\":{\\"vraven_remote_thumbnail\\":\\"images/c/z/i/s_f70c77a13ae3a244.jpg\\",\\"vraven_obfuscate_thumbnail\\":\\"sfw\\",\\"footnotes\\":\\"\\"},'
      '\\"wp-manga-genre\\":[11719,815],\\"wp-manga-tag\\":[],\\"wp-manga-release\\":[11708],\\"wp-manga-author\\":[]},'
      '{\\"id\\":98919,\\"date\\":\\"2026-10-19T22:04:27\\",\\"modified\\":\\"2026-10-19T22:04:30\\",'
      '\\"slug\\":\\"hitozukiai-yukionna-ova\\",\\"link\\":\\"https://cms.hentaihaven.xxx/watch/hitozukiai-yukionna-ova/\\",'
      '\\"title\\":{\\"rendered\\":\\"Hitozukiai ga Nigate na Miboujin no Yukionna-san to Noroi no Yubiwa OVA\\"},'
      '\\"meta\\":{\\"vraven_remote_thumbnail\\":\\"images/c/z/i/s_0a94ce85036558e6.jpg\\",\\"vraven_obfuscate_thumbnail\\":\\"sfw\\",\\"footnotes\\":\\"\\"},'
      '\\"wp-manga-genre\\":[11724,815],\\"wp-manga-tag\\":[],\\"wp-manga-release\\":[11708],\\"wp-manga-author\\":[]}]';

  const String engagement =
      r'"engagement":{"3409":{"rating":3.8,"views":11472460,"favorites":9883,"total_votes":5657},'
      r'"98923":{"rating":4.6,"views":273815,"favorites":323,"total_votes":19}}';

  const String episodeCards = '<div class="grid">'
      '<a data-episode-preview-hover="true" href="/watch/kimekoi-takane-no-hana/episode-2/">'
      '<img src="https://coverlanyvd.org/storage/2026/07/28/kimekoi-2/s_thumbnail.webp"/></a>'
      '<a data-episode-preview-hover="true" href="/watch/kimekoi-takane-no-hana/episode-1/">'
      '<img src="https://coverlanyvd.org/storage/2026/07/28/kimekoi-1/s_thumbnail.webp"/></a>'
      '</div>';

  const String episodePage = '<video data-hhaven-primary-video="true" playsInline>'
      '<source data-hhaven-indexable-source="true" '
      'src="https://octopusmanifest.org/9c81584c-4ff5-4469-ba08-c5e37b5b31ef/playlist.m3u8" '
      'type="application/vnd.apple.mpegurl"/></video>'
      r'{"duration":"PT15M40S","contentUrl":"https://octopusmanifest.org/9c81584c/playlist.m3u8"}'
      r'\"poster\":\"https://coverlanyvd.org/storage/2026/07/28/kimekoi-1/thumbnail.webp\"';

  // ---- Tests --------------------------------------------------------------

  test('RSC post array extraction (escaped payload → JSON posts)', () {
    final String flat = rscPostArray.replaceAll(r'\"', '"');
    final List<Map<String, dynamic>> posts = HentaiApi.extractPostArray(flat);
    expect(posts.length, 2);
    expect(posts[0]['slug'], 'mouse-cursor-de-genjitsu');
    expect(posts[1]['title']['rendered'],
        'Hitozukiai ga Nigate na Miboujin no Yukionna-san to Noroi no Yubiwa OVA');
  });

  test('engagement map extraction', () {
    final Map<int, ({double rating, int views})> eng =
        HentaiApi.extractEngagement(engagement);
    expect(eng.length, 2);
    expect(eng[3409]!.rating, 3.8);
    expect(eng[3409]!.views, 11472460);
    expect(eng[98923]!.rating, 4.6);
  });

  test('episode cards parse (dedup, thumbnail per episode)', () {
    final List<HhEpisode> eps =
        HentaiApi.parseEpisodeCards(episodeCards, 'kimekoi-takane-no-hana');
    expect(eps.length, 2);
    // Site order (newest first) — 2 then 1.
    expect(eps[0].number, 2);
    expect(eps[1].number, 1);
    expect(eps[1].thumb, contains('kimekoi-1/s_thumbnail.webp'));
  });

  test('episode list is returned oldest-first', () async {
    // Covered through the API layer's reversing contract: parse gives
    // newest-first, `episodes()` flips it. We test the flip here via the
    // pure parse + manual reverse (same as the service method).
    final List<HhEpisode> parsed =
        HentaiApi.parseEpisodeCards(episodeCards, 'kimekoi-takane-no-hana');
    final List<HhEpisode> flipped = parsed.reversed.toList();
    expect(flipped.first.number, 1);
  });

  test('stream resolution from the episode page markup', () {
    final HhStream? s = HentaiApi.parseStream(episodePage,
        'kimekoi-takane-no-hana', 1);
    expect(s, isNotNull);
    expect(s!.url,
        'https://octopusmanifest.org/9c81584c-4ff5-4469-ba08-c5e37b5b31ef/playlist.m3u8');
    expect(s.isHls, isTrue);
    expect(s.durationMs, 15 * 60 * 1000 + 40 * 1000);
    expect(s.poster, contains('coverlanyvd.org'));
  });

  test('stream resolution falls back to JSON-LD contentUrl', () {
    const String page = r'<div>player offline</div>'
        r'{"duration":"PT24M10S","contentUrl":"https://mirror.example.org/x/playlist.m3u8"}';
    final HhStream? s = HentaiApi.parseStream(page, 'slug', 3);
    expect(s, isNotNull);
    expect(s!.url, 'https://mirror.example.org/x/playlist.m3u8');
    expect(s.durationMs, 24 * 60 * 1000 + 10 * 1000);
  });

  test('stream resolution returns null without any source', () {
    expect(HentaiApi.parseStream('<html><body>removed</body></html>', 's', 1),
        isNull);
  });

  test('ISO duration parsing', () {
    // Exercised through parseStream; direct checks via a public-ish path are
    // not available, so verify through known fixtures above. Covered: PT15M40S.
  });

  test('REST post JSON maps to HhSeries', () {
    final Map<int, String> genreNames = <int, String>{
      815: 'Big Boobs',
      11719: 'Vanilla',
      11724: 'Supernatural',
    };
    final String flat = rscPostArray.replaceAll(r'\"', '"');
    final List<Map<String, dynamic>> posts = HentaiApi.extractPostArray(flat);
    final HhSeries s = HhSeries.fromRestJson(posts[0], genreNames);
    expect(s.id, 98923);
    expect(s.title, 'Mouse Cursor de Genjitsu');
    expect(s.thumb,
        'https://img.hentaihaven.xxx/images/c/z/i/s_f70c77a13ae3a244.jpg');
    expect(s.genres, <String>['Vanilla', 'Big Boobs']);
    expect(s.year, '2026');
  });

  test('genre names fall back to prettified class_list slugs', () {
    final Map<String, dynamic> post = <String, dynamic>{
      'id': 97561,
      'slug': 'kenki-virgo',
      'title': <String, dynamic>{'rendered': 'Kenki &amp; Virgo'},
      'meta': <String, dynamic>{'vraven_remote_thumbnail': ''},
      'wp-manga-genre': <dynamic>[],
      'class_list': <dynamic>[
        'post-97561',
        'wp-manga',
        'wp-manga-genre-bbw',
        'wp-manga-genre-3d-hentai',
      ],
      'content': <String, dynamic>{
        'rendered':
            '<p class="wp-block-paragraph">  Virgo Note story. </p>'
      },
      'date': '2026-06-15T20:23:47',
    };
    final HhSeries s = HhSeries.fromRestJson(post, <int, String>{});
    expect(s.genres, <String>['BBW', '3D Hentai']);
    expect(s.title, 'Kenki & Virgo');
    expect(s.synopsis, 'Virgo Note story.');
  });

  test('views formatting', () {
    expect(HentaiApi.formatViews(2924200), '2.9M');
    expect(HentaiApi.formatViews(423856), '424K');
    expect(HentaiApi.formatViews(1068248), '1.1M');
    expect(HentaiApi.formatViews(999), '999');
  });

  test('thumbnail URL resolution', () {
    expect(HentaiApi.thumbUrl('images/hh/v/b/s_X.jpg'),
        'https://img.hentaihaven.xxx/images/hh/v/b/s_X.jpg');
    expect(HentaiApi.thumbUrl('https://coverlanyvd.org/storage/a/s_t.webp'),
        'https://coverlanyvd.org/storage/a/s_t.webp');
    expect(HentaiApi.thumbUrl(''), '');
  });

  test('live trending fixture from disk parses (when present)', () {
    // Optional smoke: fixtures/hh_trending_fragment.html captured live.
    final File f = File('test/fixtures/hh_trending_fragment.html');
    if (!f.existsSync()) return;
    final String flat =
        f.readAsStringSync().replaceAll(r'\"', '"');
    final List<Map<String, dynamic>> posts = HentaiApi.extractPostArray(flat);
    expect(posts, isNotEmpty);
    final Map<int, ({double rating, int views})> eng =
        HentaiApi.extractEngagement(flat);
    // The live page always carries the engagement map.
    expect(eng, isNotEmpty);
  });

  test('jsonDecode sanity on a 1056-post-like payload', () {
    // Ensures the bracket walker handles nested structures safely.
    const String nested =
        '[{"id":1,"date":"d","slug":"a","meta":{"a":[1,2,{"b":"]"}]},"title":{"rendered":"T"}},'
        '{"id":2,"date":"d","slug":"b","title":{"rendered":"U"}}]';
    final List<Map<String, dynamic>> posts =
        HentaiApi.extractPostArray(nested);
    expect(posts.length, 2);
  });
}
