import 'dart:convert';
import 'dart:io';

import 'package:animax/core/app_data.dart';
import 'package:animax/core/api_html.dart';
import 'package:animax/core/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  streamResolverTests();
  searchParserTests();

  test('AnimaxData carries UI-only statics (no sample anime)', () {
    // The app is API-pure: no bundled sample catalog / artwork.
    expect(AnimaxData.genres, isNotEmpty);
    expect(AnimaxData.faqs, isNotEmpty);
  });

  test('schedule rows parse from the captured fragment shape', () {
    const String frag = '<div class="items">'
        '<a class="item old" href="/watch/kyouran-reijou-82794/ep-4">'
        '<div class="time" data-tip="82794">12:26 PM</div>'
        '<div class="ep"><i class="fas fa-play"></i><span>Episode 4</span></div>'
        '<div class="title d-title" data-jp="Kyouran Reijou Nia Liston">'
        'Nia Liston: The Merciless Maiden</div></a>'
        '<a class="item" href="/watch/another-show-81000/ep-2">'
        '<div class="time" data-tip="81000">09:00 AM</div>'
        '<div class="title d-title" data-jp="Another Show">Another Show</div></a>'
        '</div>';
    final List<ScheduleItem> rows = parseSchedule(frag);
    expect(rows.length, 2);
    expect(rows[0].slug, 'kyouran-reijou-82794');
    expect(rows[0].episode, 4);
    expect(rows[0].title, 'Nia Liston: The Merciless Maiden');
    expect(scheduleTime24h(rows[0].time), '12:26');
    expect(scheduleTime24h(rows[1].time), '09:00');
  });

  test('sources envelope resolves the embed player URL', () {
    final EpisodeSource? src = parseSourceResult(<String, dynamic>{
      'status': 200,
      'result': <String, dynamic>{
        'url': 'https://play.echovideo.ru/embed-20/abc?v=1',
        'server': 14,
        'skip_data': <String, dynamic>{
          'intro': <dynamic>[10, 85],
          'outro': <dynamic>[0, 0],
        },
      },
    });
    expect(src, isNotNull);
    expect(src!.url, 'https://play.echovideo.ru/embed-20/abc?v=1');
    expect(src.server, 14);
    expect(src.hasIntro, isTrue);
    expect(src.introStart, 10);
    expect(src.introEnd, 85);
  });

  test('sources envelope rejects failures and empty urls', () {
    expect(parseSourceResult(<String, dynamic>{'status': false}), isNull);
    expect(
      parseSourceResult(<String, dynamic>{
        'status': 200,
        'result': <String, dynamic>{'url': ''},
      }),
      isNull,
    );
  });
}

void streamResolverTests() {
  test('extractEmbedSource finds token + getSources path', () {
    const String html = '<div id="art-player">'
        '<div id="mg-player" data-id="aLongOpaqueToken1234567890abcdefghij">'
        '</div></div>'
        "<script>fetch('getSources?id=' + muxet)</script>";
    final EmbedSource? src = extractEmbedSource(html);
    expect(src, isNotNull);
    expect(src!.id, 'aLongOpaqueToken1234567890abcdefghij');
    expect(src.sourcesPath, 'getSources?id=%ID%');
  });

  test('extractEmbedSource returns null on encrypted pages', () {
    expect(extractEmbedSource('<html><body>no token here</body></html>'),
        isNull);
  });

  test('parseGetSources handles the quality-map shape', () {
    final ResolvedStream? s = parseGetSources(<String, dynamic>{
      'sources': <String, dynamic>{
        'HD': <String>['https://cdn.example/hd'],
        'SD': <String>['https://cdn.example/sd'],
      },
    });
    expect(s, isNotNull);
    expect(s!.url, 'https://cdn.example/hd'); // HQ/HD preferred over SD
    expect(s.hasQualities, isTrue);
    expect(s.qualities['HD'], 'https://cdn.example/hd');
  });

  test('parseGetSources handles the single-HLS-url shape', () {
    final ResolvedStream? s = parseGetSources(<String, dynamic>{
      'sources': 'https://cdn.example/playlist.m3u8',
    });
    expect(s, isNotNull);
    expect(s!.url, 'https://cdn.example/playlist.m3u8');
    expect(s.isHls, isTrue);
    expect(s.hasQualities, isFalse);
  });

  test('parseGetSources handles episode-keyed payloads and junk', () {
    final ResolvedStream? keyed = parseGetSources(<String, dynamic>{
      '1171': <String, dynamic>{
        'HQ': <String>['https://cdn.example/hq'],
      },
    });
    expect(keyed, isNotNull);
    expect(keyed!.url, 'https://cdn.example/hq');

    expect(parseGetSources(<String, dynamic>{}), isNull);
    expect(parseGetSources(<String, dynamic>{'sources': <dynamic>[]}), isNull);
  });

  test('parseGetSources flags HLS for query-string-only m3u8 URLs', () {
    // The backend serves playlists as /cdn/{hash}?t.m3u8&v.m3u8 — the .m3u8
    // marker is only in the query. The player relies on isHls for the
    // ExoPlayer format hint.
    final ResolvedStream? s = parseGetSources(<String, dynamic>{
      'sources':
          'https://ru-cdn1.echovideo.to/cdn/092e3d2d14736a0a?t.m3u8&v.m3u8',
    });
    expect(s, isNotNull);
    expect(s!.isHls, isTrue);
  });
}

void searchParserTests() {
  test('parseFilterCards reads the live /filter page fixture', () {
    final String html = File('test/fixtures/filter_page.html')
        .readAsStringSync(encoding: utf8);
    final List<Anime> rows = parseFilterCards(html);
    expect(rows.length, greaterThanOrEqualTo(20));
    expect(rows.first.slug, 'one-piece-81553');
    expect(rows.first.title, 'One Piece');
    expect(rows.first.poster, startsWith('https://static.aniwaves.ru'));
    expect(rows.first.genres, contains('Shounen'));
    expect(rows.map((Anime a) => a.slug), contains('one-piece-movie-01-76117'));
  });

  test('parseFilterCards reads the /filter?keyword= result layout', () {
    const String html = '<div id="list-items" class="ani items">'
        '<div class="item "><div class="inner">'
        '<div class="ani poster tip" data-tip="81553">'
        '<a href="/watch/one-piece-81553">'
        '<img src="https://static.aniwaves.ru/resources/thumbnails/200x280/100/a.jpg" alt="One Piece">'
        '<div class="meta"></div></a></div>'
        '<div class="info"><div class="b1">'
        '<a class="name d-title" href="/watch/one-piece-81553" data-jp="One Piece">One Piece</a>'
        '<div class="genre"><a href="/genre/action">Action</a>, <a href="/genre/shounen">Shounen</a></div>'
        '</div>'
        '<div class="meta">'
        '<div class="m-item"><span> 1180 </span><label>Sub</label></div>'
        '<div class="m-item rated"><span> 9</span><label><i class="fas fa-star"></i></label></div>'
        '</div></div></div></div>'
        '<div class="item "><div class="inner">'
        '<div class="ani poster tip" data-tip="76117">'
        '<a href="/watch/one-piece-movie-01-76117">'
        '<img src="https://static.aniwaves.ru/resources/thumbnails/200x280/100/b.jpg" alt="Movie">'
        '</a></div>'
        '<div class="info"><div class="b1">'
        '<a class="name d-title" href="/watch/one-piece-movie-01-76117">One Piece: The Movie</a>'
        '</div><div class="meta"></div></div></div></div>'
        '</div>';
    final List<Anime> rows = parseFilterCards(html);
    expect(rows.length, 2);
    expect(rows[0].slug, 'one-piece-81553');
    expect(rows[0].title, 'One Piece');
    expect(rows[0].poster, contains('static.aniwaves.ru'));
    expect(rows[0].score, 9);
    expect(rows[0].genres, <String>['Action', 'Shounen']);
    expect(rows[1].slug, 'one-piece-movie-01-76117');
    expect(rows[1].title, 'One Piece: The Movie');
  });

  test('parseItemCards accepts the trailing-space class variant', () {
    const String html = '<a class="item " href="/watch/one-piece-81553">'
        '<img src="/thumb.jpg"><div class="name">One Piece</div>'
        '<span class="dot score">9.1</span><span class="dot">TV</span>'
        '<span class="dot">1999</span></a>'
        '<a class="item" href="/watch/frieren-82499">'
        '<img src="/thumb2.jpg"><div class="name">Frieren</div></a>';
    final List<Anime> rows = parseItemCards(html);
    expect(rows.length, 2);
    expect(rows[0].slug, 'one-piece-81553');
    expect(rows[0].score, 9.1);
    expect(rows[0].year, '1999');
    expect(rows[1].slug, 'frieren-82499');
  });
}
