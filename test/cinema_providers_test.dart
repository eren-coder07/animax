import 'package:flutter_test/flutter_test.dart';

import 'package:animax/core/app_prefs.dart';
import 'package:animax/core/cinema_api.dart';
import 'package:animax/core/cinema_providers.dart';
import 'package:animax/core/library_store.dart';

void main() {
  group('CinemaProviders', () {
    test('builds movie URLs per provider', () {
      expect(cinemaProviders[0].buildMovie('tt0137523'),
          'https://vidsrc.sh/embed/movie/tt0137523');
      expect(providerById('vidfast').buildMovie('tt0137523'),
          'https://vidfast.pro/movie/tt0137523');
      expect(providerById('vidsrcxyz').buildMovie('tt0137523'),
          'https://vidsrc.xyz/embed/movie?imdb=tt0137523');
    });

    test('builds padded TV URLs for vidsrc', () {
      final String url = providerById('vidsrc')
          .buildTv(imdbId: 'tt0903747', season: 1, episode: 1)!;
      expect(url, 'https://vidsrc.sh/embed/tv/tt0903747/01-01');
      final String s10e5 = providerById('vidsrc')
          .buildTv(imdbId: 'tt0903747', season: 10, episode: 5)!;
      expect(s10e5, contains('/10-05'));
    });

    test('vidlink TV needs a TMDB id', () {
      expect(
        providerById('vidlink').buildTv(
            imdbId: 'tt0903747', season: 1, episode: 1),
        isNull,
      );
      final String? url = providerById('vidlink').buildTv(
          imdbId: 'tt0903747', tmdbId: '1396', season: 2, episode: 3);
      expect(url, 'https://vidlink.pro/tv/1396/2/3');
    });

    test('vidfast TV uses raw season/episode numbers', () {
      final String url = providerById('vidfast')
          .buildTv(imdbId: 'tt0903747', season: 4, episode: 13)!;
      expect(url, 'https://vidfast.pro/tv/tt0903747/4/13');
    });

    test('every provider id is unique and list is ordered', () {
      final Set<String> ids =
          cinemaProviders.map((CinemaProvider p) => p.id).toSet();
      expect(ids.length, cinemaProviders.length);
      expect(cinemaProviders.first.id, 'vidsrc');
      expect(cinemaProviders.length, greaterThanOrEqualTo(6));
    });

    test('host allowlist covers all provider homes', () {
      for (final CinemaProvider p in cinemaProviders) {
        expect(isCinemaAllowedHost(p.home), isTrue,
            reason: 'provider ${p.id} host ${p.home} must be allowed');
      }
      // Known CDN / subdomain forms pass too.
      expect(isCinemaAllowedHost('www.2embed.cc'), isTrue);
      expect(isCinemaAllowedHost('data.vidsrc.sh'), isTrue);
      // Ads / popunders are blocked.
      expect(isCinemaAllowedHost('evil-ads.example.com'), isFalse);
      expect(isCinemaAllowedHost('random-tracker.net'), isFalse);
    });

    test('verification probe JS contains the failure signatures', () {
      expect(verificationProbeJs, contains('verification failed'));
      expect(verificationProbeJs, contains('animaxBridge'));
      expect(messagePumpJs, contains('ended'));
      expect(messagePumpJs, contains('__animaxPump'));
    });
  });

  group('CinemaMeta parsing', () {
    test('parses moviedb_id for TMDB-backed providers', () {
      final CinemaMeta m = CinemaMeta.fromJson(<String, dynamic>{
        'imdb_id': 'tt0903747',
        'name': 'Breaking Bad',
        'type': 'series',
        'moviedb_id': 1396,
        'videos': <dynamic>[
          <String, dynamic>{'season': 1, 'number': 1, 'name': 'Pilot'},
          <String, dynamic>{'season': 1, 'number': 2, 'name': 'Cat in the Bag…'},
        ],
      });
      expect(m.tmdbId, '1396');
      expect(m.episodes.length, 2);
      expect(m.seasonNumbers, <int>[1]);
      expect(m.episodes[0].label, 'S01 · E01');
    });
  });

  group('LibraryStore', () {
    late LibraryStore store;

    setUp(() async {
      store = LibraryStore.I;
      await store.load();
      store.clearHistory();
    });

    test('list statuses round-trip', () {
      store.setListStatus(
          key: 'anime:one-piece',
          title: 'One Piece',
          poster: 'https://x/p.jpg',
          kind: 'anime',
          status: LibStatus.watching,
          meta: '2026 · TV');
      expect(store.isListed('anime:one-piece'), isTrue);
      expect(store.entryOf('anime:one-piece')!.status, LibStatus.watching);

      store.setListStatus(
          key: 'anime:one-piece',
          title: 'One Piece',
          poster: '',
          kind: 'anime',
          status: LibStatus.done);
      expect(store.entryOf('anime:one-piece')!.status, LibStatus.done);

      store.removeListEntry('anime:one-piece');
      expect(store.isListed('anime:one-piece'), isFalse);
    });

    test('progress save/read + watched flags', () {
      store.saveProgress(
          key: 'anime:a1', sub: '5', positionSec: 300, durationSec: 1400);
      final ProgressEntry p = store.progressOf('anime:a1', '5')!;
      expect(p.positionSec, 300);
      expect(p.fraction, closeTo(300 / 1400, 0.001));
      expect(store.isWatched('anime:a1', '5'), isFalse);

      store.markWatched('anime:a1', '5', watched: true);
      expect(store.isWatched('anime:a1', '5'), isTrue);
    });

    test('progressForItem returns the latest row of any sub', () async {
      store.saveProgress(key: 'cinema:tt1', sub: 'S1E1', positionSec: 10);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      store.saveProgress(key: 'cinema:tt1', sub: 'S1E2', positionSec: 20);
      expect(store.progressForItem('cinema:tt1').sub, 'S1E2');
    });

    test('history dedupes by key+sub and caps at 60', () {
      for (int i = 0; i < 70; i++) {
        store.pushHistory(
            key: 'anime:h$i',
            title: 'T$i',
            poster: '',
            kind: 'anime',
            sub: '1',
            label: 'Episode 1');
      }
      expect(store.history.length, 60);
      store.pushHistory(
          key: 'anime:h69',
          title: 'T69',
          poster: '',
          kind: 'anime',
          sub: '1',
          label: 'Episode 1');
      expect(
          store.history.where((HistoryRow r) => r.key == 'anime:h69').length,
          1);
    });

    test('export/import round-trips entries and progress', () {
      store.setListStatus(
          key: 'manga:m1',
          title: 'Manga One',
          poster: '',
          kind: 'manga',
          status: LibStatus.plan);
      store.saveProgress(key: 'manga:m1', sub: 'ch-3', positionSec: 2);
      final Map<String, dynamic> data = store.exportJson();
      expect((data['entries'] as List<dynamic>).length, greaterThanOrEqualTo(1));

      // Fresh store import.
      store.importJson(<String, dynamic>{'entries': data['entries'], 'progress': data['progress']});
      expect(store.isListed('manga:m1'), isTrue);
      expect(store.progressOf('manga:m1', 'ch-3')!.positionSec, 2);
    });

    test('ratings clamp 0–10', () {
      store.setListStatus(
          key: 'anime:r1',
          title: 'Rated',
          poster: '',
          kind: 'anime',
          status: LibStatus.done);
      store.rate('anime:r1', 99);
      expect(store.ratingOf('anime:r1'), 10);
      store.rate('anime:r1', -5);
      expect(store.ratingOf('anime:r1'), 0);
    });
  });

  group('AccentTheme', () {
    test('byKey falls back to default green', () {
      expect(AccentTheme.byKey('red').name, 'أحمر سينمائي');
      expect(AccentTheme.byKey('nonsense'), AccentTheme.def);
      expect(AccentTheme.byKey('nonsense').key, 'green');
    });

    test('five accents with unique keys', () {
      final Set<String> keys = AccentTheme.all.map((AccentTheme a) => a.key).toSet();
      expect(keys.length, AccentTheme.all.length);
      expect(AccentTheme.all.length, 5);
    });
  });
}
