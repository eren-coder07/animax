import 'dart:typed_data';

import 'package:animax/core/akwam_api.dart';
import 'package:animax/core/download_manager.dart';
import 'package:animax/core/hls_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

void main() {
  group('HlsParser master', () {
    // Live shape (octopusmanifest CDN, 2026-11-20).
    const String master = '''#EXTM3U
#EXT-X-VERSION:7
#EXT-X-MEDIA:URI="snd/a.m3u8",TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="en",NAME="English",DEFAULT=YES,AUTOSELECT=YES
#EXT-X-STREAM-INF:BANDWIDTH=2077570,RESOLUTION=1280x720,CODECS="avc1.4d4028,mp4a.40.2",AUDIO="audio"
7sop/v.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d4028,mp4a.40.2",AUDIO="audio"
3cop/v.m3u8
''';
    final Uri base = Uri.parse('https://cdn.example.org/abc/playlist.m3u8');

    test('picks the best variant and its audio rendition', () {
      final HlsMaster m = HlsParser.parseMaster(master, base);
      expect(m.variants.length, 2);
      final HlsStreamVariant v = m.best()!;
      expect(v.height, 720);
      expect(v.uri.toString(), 'https://cdn.example.org/abc/7sop/v.m3u8');
      expect(m.audioFor(v)!.uri.toString(),
          'https://cdn.example.org/abc/snd/a.m3u8');
      expect(m.best(maxHeight: 480)!.height, 360);
    });

    test('muxed variants have no separate audio', () {
      final HlsMaster m = HlsParser.parseMaster(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nhi.m3u8\n', base);
      expect(m.audioFor(m.best()!), isNull);
    });
  });

  group('HlsParser media', () {
    test('fMP4 init map, absolute + relative segments, durations', () {
      const String body = '''#EXTM3U
#EXT-X-MEDIA-SEQUENCE:1
#EXT-X-TARGETDURATION:2
#EXT-X-MAP:URI="https://cdn.e621.tv/x/7sop/i.mp4"
#EXTINF:2,
https://cdn.e621.tv/x/7sop/ha1.html
#EXTINF:1.5,
ha2.html
#EXT-X-ENDLIST
''';
      final HlsMediaPlaylist p = HlsParser.parseMedia(
          body, Uri.parse('https://cdn.e621.tv/x/7sop/v.m3u8'));
      expect(p.isFragmentedMp4, isTrue);
      expect(p.initUri.toString(), 'https://cdn.e621.tv/x/7sop/i.mp4');
      expect(p.segments.length, 2);
      expect(p.segments[1].uri.toString(), 'https://cdn.e621.tv/x/7sop/ha2.html');
      expect(p.segments[0].sequence, 1);
      expect(p.segments[1].sequence, 2);
      expect(p.totalSeconds, 3.5);
    });

    test('AES-128 keys, IVs and byte ranges', () {
      const String body = '''#EXTM3U
#EXT-X-MEDIA-SEQUENCE:7
#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x000102030405060708090a0b0c0d0e0f
#EXTINF:4,
#EXT-X-BYTERANGE:100@0
all.ts
#EXT-X-KEY:METHOD=AES-128,URI="key2.bin"
#EXTINF:4,
#EXT-X-BYTERANGE:50
all.ts
#EXT-X-KEY:METHOD=NONE
#EXTINF:4,
plain.ts
''';
      final HlsMediaPlaylist p =
          HlsParser.parseMedia(body, Uri.parse('https://h/p/x.m3u8'));
      expect(p.segments.length, 3);
      final HlsSegment a = p.segments[0];
      expect(a.key!.uri.toString(), 'https://h/p/key.bin');
      expect(a.key!.iv![15], 0x0f);
      expect(a.range!.header, 'bytes=0-99');
      final HlsSegment b = p.segments[1];
      expect(b.range!.offset, 100); // continues after previous range
      expect(b.key!.iv, isNull);
      // Derived IV = sequence number, big-endian.
      expect(HlsParser.ivFor(b.key!, b.sequence)[15], 8);
      expect(p.segments[2].key, isNull);
    });

    test('AES-128-CBC round trip', () {
      final Uint8List key = Uint8List.fromList(List<int>.generate(16, (int i) => i));
      final Uint8List iv = Uint8List.fromList(List<int>.generate(16, (int i) => 15 - i));
      final Uint8List plain = Uint8List.fromList('hello animax segment'.codeUnits);
      final PaddedBlockCipherImpl enc =
          PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
            ..init(
                true,
                PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
                    ParametersWithIV<KeyParameter>(KeyParameter(key), iv), null));
      final Uint8List cipher = enc.process(plain);
      expect(HlsParser.decryptAes128(cipher, key, iv), plain);
    });
  });

  group('DownloadItem', () {
    test('JSON round trip keeps resume state and status', () {
      final DownloadItem it = DownloadItem(
        id: 'x1',
        kind: DownloadKind.video,
        title: 'One Piece',
        subtitle: 'Episode 1',
        url: 'https://h/master.m3u8',
        headers: const <String, String>{'Referer': 'https://r/'},
        isHls: true,
        status: DownloadStatus.paused,
        progress: 0.5,
        resume: <String, List<int>>{'v': <int>[10, 12345]},
      );
      final DownloadItem back = DownloadItem.fromJson(it.toJson());
      expect(back.status, DownloadStatus.paused);
      expect(back.isHls, isTrue);
      expect(back.headers['Referer'], 'https://r/');
      expect(back.resume['v'], <int>[10, 12345]);
      expect(back.fileBase, 'One Piece - Episode 1');
    });

    test('file names are sanitized', () {
      expect(sanitizeFileName('a/b:c*?"<>|d'), 'a_b_c______d');
      expect(sanitizeFileName('   '), 'animax');
      expect(sanitizeFileName('x' * 300).length, 110);
    });
  });

  group('Details-page downloads', () {
    test('resolvable items persist source, ref and key', () {
      final DownloadItem it = DownloadItem(
        id: 'r1',
        kind: DownloadKind.video,
        title: 'مسلسل',
        subtitle: 'الحلقة 3',
        source: 'akwam',
        ref: const <String, String>{'path': '/episode/1/x'},
        key: 'akwam:/episode/1/x',
      );
      final DownloadItem back = DownloadItem.fromJson(it.toJson());
      expect(back.source, 'akwam');
      expect(back.ref['path'], '/episode/1/x');
      expect(back.key, 'akwam:/episode/1/x');
      expect(back.url, isEmpty); // resolved later
    });

    test('url downloads use the url as their key', () {
      final DownloadItem it = DownloadItem(
          id: 'u', kind: DownloadKind.video, title: 't', url: 'https://x/a.mp4');
      expect(it.key, 'https://x/a.mp4');
    });

    test('bestAkwamSource picks the highest resolution', () {
      const List<AkwamSource> s = <AkwamSource>[
        AkwamSource(quality: '480p', watchPath: '/watch/1'),
        AkwamSource(quality: '1080p', watchPath: '/watch/3'),
        AkwamSource(quality: '720p', watchPath: '/watch/2'),
      ];
      expect(bestAkwamSource(s).watchPath, '/watch/3');
      expect(
          bestAkwamSource(const <AkwamSource>[
            AkwamSource(quality: 'HD', watchPath: '/watch/9'),
          ]).watchPath,
          '/watch/9');
    });
  });
}
