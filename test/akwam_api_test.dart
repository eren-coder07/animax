import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:animax/core/akwam_api.dart';

String fix(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('AkwamApi.parseAkwamCards (live movies page fixture)', () {
    final List<AkwamItem> items = AkwamApi.parseAkwamCards(fix('akwam_movies.html'));

    test('extracts all 3 catalog cards', () {
      expect(items.length, 3);
    });

    test('first card: id, path, kind, title', () {
      final AkwamItem a = items.first;
      expect(a.id, '11687');
      expect(a.path, '/movie/11687/insidious-possession');
      expect(a.kind, AkwamKind.movie);
      expect(a.title, 'Insidious Possession');
      expect(a.isSeries, isFalse);
    });

    test('first card: poster, rating, quality, year', () {
      final AkwamItem a = items.first;
      expect(a.poster,
          startsWith('https://img.downet.net/thumb/178x260/uploads/'));
      expect(a.rating, 4.0);
      expect(a.qualityLabel, 'WEB-DL');
      expect(a.year, '2026');
    });

    test('every card carries a resolvable item path', () {
      for (final AkwamItem it in items) {
        expect(it.path, startsWith('/'));
        expect(it.path, contains(RegExp(r'/(movie|series|show)/\d+/')));
      }
    });
  });

  group('AkwamApi.parseAkwamDetails (live series page fixture)', () {
    final AkwamItem base = AkwamItem(
      id: '5946',
      path: '/series/5946/the-perfect-lie',
      kind: AkwamKind.series,
      title: 'The Perfect Lie',
    );
    final AkwamItem rich =
        AkwamApi.parseAkwamDetails(base, fix('akwam_series.html'));

    test('enriches synopsis from the story block', () {
      expect(rich.synopsis, isNotEmpty);
      expect(rich.synopsis.length, greaterThan(60));
    });

    test('parses 6 episodes with ascending numbers', () {
      expect(rich.episodes.length, 6);
      expect(
        rich.episodes.map((AkwamEpisode e) => e.number).toList(),
        <int>[1, 2, 3, 4, 5, 6],
      );
    });

    test('episode 1: id, label, air-date and page path', () {
      final AkwamEpisode ep = rich.episodes.first;
      expect(ep.id, '104508');
      expect(ep.number, 1);
      expect(ep.label, isNotEmpty);
      expect(ep.date, isNotEmpty);
      expect(ep.path, startsWith('/episode/104508/'));
    });

    test('episode paths are unique and playable-looking', () {
      final Set<String> paths =
          rich.episodes.map((AkwamEpisode e) => e.path).toSet();
      expect(paths.length, 6);
      for (final String p in paths) {
        expect(p, contains('/episode/'));
      }
    });
  });

  group('AkwamApi.parseAkwamSources (live quality tabs)', () {
    test('movie page exposes 720p and 480p watch links with sizes', () {
      final List<AkwamSource> sources =
          AkwamApi.parseAkwamSources(fix('akwam_movie.html'));
      expect(sources.length, 2);
      expect(sources.first.quality, '720p');
      expect(sources.first.size, '581.1 MB');
      expect(sources.first.watchPath,
          '/watch/184784/11687/insidious-possession');
      expect(sources.last.quality, '480p');
      expect(sources.last.size, '262.6 MB');
    });

    test('episode page exposes its 720p watch link', () {
      final List<AkwamSource> sources =
          AkwamApi.parseAkwamSources(fix('akwam_episode.html'));
      expect(sources.length, 1);
      expect(sources.first.quality, '720p');
      expect(sources.first.watchPath, contains('/watch/184941/105419/'));
      expect(sources.first.size, '519.3 MB');
    });
  });

  group('AkwamApi.extractAkwamStreamUrl (live watch page fixture)', () {
    test('finds the direct MP4 on the watch page', () {
      final String url = AkwamApi.extractAkwamStreamUrl(fix('akwam_watch.html'));
      expect(url, isNotEmpty);
      expect(url, endsWith('.mp4'));
      expect(url, contains('downet.net'));
    });

    test('returns empty for pages without a stream', () {
      expect(AkwamApi.extractAkwamStreamUrl('<html><body>nothing here</body></html>'),
          isEmpty);
    });
  });
}
