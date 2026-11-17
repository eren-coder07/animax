import 'package:flutter_test/flutter_test.dart';

import 'package:animax/core/cinema_api.dart';
import 'package:animax/core/hls_quality.dart';
import 'package:animax/core/stream_resolver.dart';

void main() {
  group('HlsQuality.parseMaster', () {
    const String master = '''#EXTM3U
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=884042,RESOLUTION=1280x532,FRAME-RATE=60.000,CODECS="avc1.640020,mp4a.40.2",VIDEO-RANGE=SDR
https://cdn.example.com/hls/index-v1-a1.m3u8?t=abc&s=1
#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=34866,RESOLUTION=1280x532,CODECS="avc1.640020",URI="https://cdn.example.com/hls/iframe.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1920x1080,NAME="1080p"
/relative/path/index-1080.m3u8?x=1
''';

    test('extracts variants, skips I-FRAME entries, resolves relative URIs',
        () {
      final List<HlsVariant> variants =
          HlsQuality.parseMaster(master, Uri.parse('https://cdn.example.com/hls/master.m3u8?tok=1'));
      expect(variants.length, 2);
      expect(variants[0].bandwidth, 884042);
      expect(variants[0].height, 532);
      expect(variants[0].uri.host, 'cdn.example.com');
      expect(variants[0].uri.query, 't=abc&s=1');
      expect(variants[1].bandwidth, 2500000);
      expect(variants[1].height, 1080);
      expect(variants[1].label, '1080p');
      expect(variants[1].uri.host, 'cdn.example.com');
      expect(variants[1].uri.path, '/relative/path/index-1080.m3u8');
    });

    test('media playlists parse to an empty list', () {
      const String media =
          '#EXTM3U\n#EXTINF:10.0,\nseg-1.ts\n#EXTINF:10.0,\nseg-2.ts\n';
      expect(
          HlsQuality.parseMaster(
              media, Uri.parse('https://cdn.example.com/v.m3u8')),
          isEmpty);
    });

    test('pick prefers the highest variant within the bandwidth budget', () {
      final List<HlsVariant> vs = <HlsVariant>[
        HlsVariant(bandwidth: 500000, uri: Uri.parse('https://x/0.m3u8')),
        HlsVariant(bandwidth: 900000, uri: Uri.parse('https://x/1.m3u8')),
        HlsVariant(bandwidth: 2500000, uri: Uri.parse('https://x/2.m3u8')),
      ];
      // 8 Mbps Wi-Fi → target 5.6 Mbps → 2.5 Mbps variant.
      expect(HlsQuality.pick(vs, 8, true)!.bandwidth, 2500000);
      // 1 Mbps cellular → target 0.45 Mbps → lowest variant.
      expect(HlsQuality.pick(vs, 1, false)!.bandwidth, 500000);
    });
  });

  group('CinemaApi payload parsing', () {
    test('CinemaItem.fromJson reads the Cinemeta catalog shape', () {
      final CinemaItem it = CinemaItem.fromJson(<String, dynamic>{
        'imdb_id': 'tt0137523',
        'name': 'Fight Club',
        'type': 'movie',
        'poster': 'https://image.tmdb.org/p.jpg',
        'releaseInfo': '1999',
        'imdbRating': '8.4',
        'genre': <dynamic>['Drama', 'Thriller'],
      });
      expect(it.id, 'tt0137523');
      expect(it.imdbRating, closeTo(8.4, 0.001));
      expect(it.genres, <String>['Drama', 'Thriller']);
      expect(it.isSeries, isFalse);
    });

    test('CinemaMeta.fromJson extracts episodes and seasons', () {
      final CinemaMeta m = CinemaMeta.fromJson(<String, dynamic>{
        'imdb_id': 'tt0903747',
        'name': 'Breaking Bad',
        'type': 'series',
        'imdbRating': 9.5,
        'videos': <dynamic>[
          <String, dynamic>{'season': 1, 'number': 2, 'name': 'Cat\'s in the Bag...'},
          <String, dynamic>{'season': 1, 'number': 1, 'name': 'Pilot'},
          <String, dynamic>{'season': 2, 'number': 1, 'name': 'Seven Thirty-Seven'},
          <String, dynamic>{'name': 'Special'}, // no season — skipped
        ],
        'trailerStreams': <dynamic>[
          <String, dynamic>{'source': 'H9aE8tL2mQk', 'type': 'Trailer'},
        ],
      });
      expect(m.episodes.length, 3);
      expect(m.episodes.first.number, 1); // sorted by season then number
      expect(m.seasonNumbers, <int>[1, 2]);
      expect(m.trailers.length, 1);
      expect(m.trailers.first.isYouTube, isTrue);
    });

    test('CinemaPlayback builds verified embed URLs', () {
      expect(CinemaPlayback.movieUrl('tt0137523'),
          'https://vidsrc.sh/embed/movie/tt0137523');
      expect(CinemaPlayback.episodeUrl('tt0903747', 1, 1),
          'https://vidsrc.sh/embed/tv/tt0903747/01-01');
      expect(CinemaPlayback.isAllowedHost('stellarconductornexus.com'), isTrue);
      expect(CinemaPlayback.isAllowedHost('evil-ads.example.com'), isFalse);
    });
  });

  group('autoSelect guard rails', () {
    test('non-HLS streams pass through untouched', () async {
      const ResolvedStream rs = ResolvedStream(url: 'https://cdn.x/video.mp4');
      final ResolvedStream out = await HlsQuality.autoSelect(rs);
      expect(out.url, rs.url);
      expect(out.qualities.length, rs.qualities.length);
    });
  });
}
