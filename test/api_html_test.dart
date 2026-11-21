import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:animax/core/api_html.dart';
import 'package:animax/core/app_data.dart';

String fix(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('parseItemCards (real trending fragment)', () {
    final List<Anime> items = parseItemCards(fix('trending.html'));

    test('extracts all 8 trending cards', () {
      expect(items.length, 8);
    });

    test('first card is One Piece with poster, score, type, year', () {
      final Anime a = items.first;
      expect(a.id, 'one-piece-81553');
      expect(a.slug, 'one-piece-81553');
      expect(a.title, 'One Piece');
      expect(a.score, 9.0);
      expect(a.type, 'TV');
      expect(a.year, '1999');
      expect(a.poster,
          startsWith('https://static.aniwaves.ru/resources/thumbnails/'));
      expect(a.isNetworkPoster, isTrue);
    });

    test('second card is Slime Season 4 (2026)', () {
      final Anime a = items[1];
      expect(a.title, 'That Time I Got Reincarnated as a Slime Season 4');
      expect(a.year, '2026');
      expect(a.score, 8.0);
    });

    test('watchId derives numeric id from slug', () {
      expect(items.first.watchId, '81553');
    });

    test('watchUrl builds episode links', () {
      expect(items.first.watchUrl(ep: 1),
          'https://aniwaves.tv/watch/one-piece-81553/ep-1');
    });
  });

  group('parseEpisodeList (real episode fragment)', () {
    final List<Episode> eps = parseEpisodeList(fix('episodes.html'));

    test('extracts 4 episodes', () {
      expect(eps.length, 4);
      expect(eps.map((Episode e) => e.number).toList(), <int>[1, 2, 3, 4]);
    });

    test('episode 1 fields (long title, entity decoding, sub+dub)', () {
      final Episode e1 = eps.first;
      expect(
          e1.title,
          startsWith(
              "Everyone Knows What It's Like When Nothing Goes Right"));
      expect(e1.title.contains('&'), isFalse); // &#039; decoded
      expect(e1.duration, '24m'); // 1420s → 24m
      expect(e1.hasSub, isTrue);
      expect(e1.hasDub, isTrue);
      expect(e1.aired, '2026-10-07T00:00:00+09:00');
    });

    test('unnumbered episode 4 falls back to a clean title', () {
      expect(eps[3].title, 'Episode 4');
    });
  });

  group('parseServerList (real server fragment)', () {
    final List<EpisodeServer> servers = parseServerList(fix('servers.html'));

    test('extracts servers across sub/ssub/dub groups', () {
      expect(servers.length, greaterThanOrEqualTo(8));
      expect(servers.any((EpisodeServer s) => s.kind == 'sub'), isTrue);
      expect(servers.any((EpisodeServer s) => s.kind == 'dub'), isTrue);
    });

    test('first sub server is DatSaV with sv-id 14 and an opaque token', () {
      final EpisodeServer s =
          servers.firstWhere((EpisodeServer s) => s.kind == 'sub');
      expect(s.name, 'DatSaV');
      expect(s.svId, '14');
      expect(s.linkId, isNotEmpty);
      expect(s.linkId.length, greaterThan(50));
    });

    test('server names are decoded', () {
      expect(
          servers.map((EpisodeServer s) => s.name),
          containsAll(<String>['Vidplay', 'BYFMS', 'MyCloud']));
    });
  });

  group('parseWatchDetails (real watch page)', () {
    final Anime base = Anime(
        id: 'tsuihou-sareta-82796',
        title: 'placeholder',
        poster: '',
        score: 0,
        year: '',
        genres: const <String>[],
        synopsis: '');
    final Anime details = parseWatchDetails(base, fix('watch_page.html'));

    test('title comes from h1', () {
      expect(details.title,
          'The Laid-Off Cheat-Granting Mage Enjoys a Second Lease on Life');
    });

    test('synopsis from film-description', () {
      expect(details.synopsis, startsWith('Rein, an enchanter'));
      expect(details.synopsis.length, greaterThan(100));
    });

    test('poster from og:image', () {
      expect(details.poster,
          'https://static.aniwaves.ru/resources/cover/1200x630/100/4388c81b954c213864d7c1bc862e00c6.jpg');
    });

    test('genres parsed from /genre/ links', () {
      expect(details.genres, contains('Action'));
      expect(details.genres, contains('Adventure'));
      expect(details.genres.length, greaterThan(5));
    });
  });

  group('decodeEntities', () {
    test('named + numeric + hex', () {
      expect(decodeEntities('A &amp; B &#039;C&#x27; &quot;D&quot;'),
          "A & B 'C' \"D\"");
    });
  });
}
