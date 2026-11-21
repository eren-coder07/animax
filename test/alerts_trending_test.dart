import 'package:animax/core/episode_alerts.dart';
import 'package:animax/core/library_store.dart';
import 'package:animax/core/social.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final LibEntry series = LibEntry(
    key: 'akwam:/series/5744/x',
    title: 'ما زلت في 17',
    poster: 'p',
    kind: 'akwam',
    status: LibStatus.values.first,
  );

  test(
    'first sighting is only a baseline; a higher count raises one alert',
    () {
      final DateTime now = DateTime(2026, 11, 21);
      var r = EpisodeAlerts.compare(series, null, 24, now);
      expect(r.count, 24);
      expect(r.alert, isNull);
      r = EpisodeAlerts.compare(series, 24, 24, now);
      expect(r.alert, isNull);
      r = EpisodeAlerts.compare(series, 24, 26, now);
      expect(r.count, 26);
      expect(r.alert!.episode, 26);
      expect(r.alert!.path, '/series/5744/x');
      // A failed fetch (0) never resets the stored count.
      r = EpisodeAlerts.compare(series, 26, 0, now);
      expect(r.count, 26);
      expect(r.alert, isNull);
    },
  );

  test('only Akwam series / shows in My List are checked', () {
    final List<LibEntry> picked = EpisodeAlerts.watched(<LibEntry>[
      series,
      LibEntry(
        key: 'akwam:/movie/1/m',
        title: 'm',
        poster: '',
        kind: 'akwam',
        status: LibStatus.values.first,
      ),
      LibEntry(
        key: 'anime:x',
        title: 'a',
        poster: '',
        kind: 'anime',
        status: LibStatus.values.first,
      ),
      LibEntry(
        key: 'akwam:/show/9/s',
        title: 's',
        poster: '',
        kind: 'akwam',
        status: LibStatus.values.first,
      ),
      LibEntry(
        key: 'akwam:/series/2/n',
        title: 'n',
        poster: '',
        kind: 'akwam',
      ), // not in list
    ]);
    expect(picked.map((LibEntry e) => e.key), <String>[
      'akwam:/series/5744/x',
      'akwam:/show/9/s',
    ]);
  });

  test('trending favours engagement and freshness', () {
    final DateTime now = DateTime(2026, 11, 21, 12);
    VideoClip c(
      String id, {
      int likes = 0,
      int views = 0,
      required int hoursAgo,
    }) => VideoClip(
      id: id,
      title: id,
      kind: 'akwam',
      source: 'akwam',
      ref: const <String, String>{},
      startMs: 0,
      endMs: 1000,
      likes: likes,
      views: views,
      at: now.subtract(Duration(hours: hoursAgo)),
    );
    final VideoClip hotNew = c('hot', likes: 20, views: 200, hoursAgo: 2);
    final VideoClip oldHit = c('old', likes: 20, views: 200, hoursAgo: 72);
    final VideoClip quietNew = c('quiet', hoursAgo: 1);
    expect(
      Social.trendScore(hotNew, now),
      greaterThan(Social.trendScore(oldHit, now)),
    );
    expect(
      Social.trendScore(hotNew, now),
      greaterThan(Social.trendScore(quietNew, now)),
    );
  });
}
