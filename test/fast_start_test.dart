import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:animax/core/akwam_api.dart';
import 'package:animax/core/fast_start.dart';
import 'package:animax/core/net_quality.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves [bytes] with HTTP range support (the "CDN").
Future<HttpServer> serve(Uint8List bytes) async {
  final HttpServer s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((HttpRequest rq) async {
    int a = 0, b = bytes.length - 1;
    final RegExpMatch? m = RegExp(r'bytes=(\d*)-(\d*)')
        .firstMatch(rq.headers.value('range') ?? '');
    if (m != null) {
      if (m.group(1)!.isNotEmpty) a = int.parse(m.group(1)!);
      if (m.group(2)!.isNotEmpty)
        b = math.min(bytes.length - 1, int.parse(m.group(2)!));
      rq.response.statusCode = 206;
      rq.response.headers.set('content-range', 'bytes $a-$b/${bytes.length}');
    }
    rq.response.headers.contentLength = b - a + 1;
    rq.response.add(bytes.sublist(a, b + 1));
    await rq.response.close();
  });
  return s;
}

Future<Uint8List> fetch(Uri u) async {
  final HttpClient c = HttpClient();
  final HttpClientResponse r = await (await c.getUrl(u)).close();
  final BytesBuilder b = BytesBuilder();
  await for (final List<int> x in r) {
    b.add(x);
  }
  c.close();
  return b.takeBytes();
}

void main() {
  final Uint8List mp4 = File('test/fixtures/faststart_sample.mp4')
      .readAsBytesSync();

  test('window index is small, keyframe-aligned and self-consistent', () async {
    final HttpServer cdn = await serve(mp4);
    final String url = 'http://127.0.0.1:${cdn.port}/a.mp4';
    final Mp4Index full = await Mp4Index.open(
      RangeReader(url, const <String, String>{}),
    );
    expect(full.durationSec, closeTo(40, 0.2));

    final FastWindow w = await FastStart.open(
      url,
      const <String, String>{},
      from: 2.5,
      length: 4,
    );
    // Starts on the keyframe at/before 2.5 s (GOP = 2 s) and ends on one;
    // more than 30 s remain, so it is not merged into the last window.
    expect(w.offset, lessThanOrEqualTo(2.5));
    expect(w.offset, greaterThan(1.9));
    expect(w.length, greaterThanOrEqualTo(4));
    expect(w.isLast, isFalse);

    // The virtual file parses back as an MP4 of the window's length, with
    // every sample inside the file.
    final Uint8List virt = await fetch(w.uri);
    final HttpServer v = await serve(virt);
    final Mp4Index ix = await Mp4Index.open(
      RangeReader('http://127.0.0.1:${v.port}/v.mp4', const <String, String>{}),
    );
    expect(ix.durationSec, closeTo(w.length, 0.1));
    final WindowPlan all = await ix.plan(from: 0, length: 1000);
    expect(all.regionEnd, lessThanOrEqualTo(virt.length));
    expect(all.tracks.length, 2); // video + audio
    expect(virt.length, lessThan(mp4.length ~/ 2));

    // Range requests are honoured by the local server.
    final HttpClient c = HttpClient();
    final HttpClientRequest rq = await c.getUrl(w.uri);
    rq.headers.set('range', 'bytes=10-19');
    final HttpClientResponse rs = await rq.close();
    expect(rs.statusCode, 206);
    final List<int> part = (await rs.toList())
        .expand((List<int> x) => x)
        .toList();
    expect(part, virt.sublist(10, 20));
    c.close();
    await v.close(force: true);
    await cdn.close(force: true);
  });

  test('chained windows join exactly; the last one reaches the end', () async {
    final HttpServer cdn = await serve(mp4);
    final String url = 'http://127.0.0.1:${cdn.port}/b.mp4';
    final FastWindow a = await FastStart.open(
      url,
      const <String, String>{},
      from: 0,
      length: 6,
    );
    final FastWindow b = await FastStart.open(
      url,
      const <String, String>{},
      from: a.end,
      length: 6,
    );
    expect(b.offset, closeTo(a.end, 0.001));
    final FastWindow z = await FastStart.open(
      url,
      const <String, String>{},
      from: 30,
      length: 100,
    );
    expect(z.isLast, isTrue);
    expect(z.end, closeTo(40, 0.2));
    await cdn.close(force: true);
  });

  test('clip windows end at the requested time', () async {
    final HttpServer cdn = await serve(mp4);
    final FastWindow w = await FastStart.open(
      'http://127.0.0.1:${cdn.port}/c.mp4',
      const <String, String>{},
      from: 20.3,
      to: 25.0,
    );
    expect(w.offset, lessThanOrEqualTo(20.3));
    expect(w.end, closeTo(25.0, 0.25)); // + B-frame delay
    await cdn.close(force: true);
  });

  group('Akwam qualities', () {
    test('every watch page lists each quality; pick by height / lowest', () {
      final String html = File('test/fixtures/akwam_watch_multi.html')
          .readAsStringSync();
      final Map<int, String> m = AkwamApi.extractAkwamStreams(html);
      expect(m.keys.toList(), <int>[720, 480, 360]);
      expect(m[360], endsWith('360p.mp4'));
      expect(AkwamApi.pickAkwamStream(m, height: 480), endsWith('480p.mp4'));
      expect(AkwamApi.pickAkwamStream(m, lowest: true), endsWith('360p.mp4'));
      expect(AkwamApi.pickAkwamStream(m), endsWith('720p.mp4'));
      expect(AkwamApi.pickAkwamStream(m, height: 1080), endsWith('720p.mp4'));
      expect(AkwamApi.pickAkwamStream(m, height: 240), endsWith('360p.mp4'));
    });
  });

  group('speed → quality', () {
    test('100 KB/s (≈ 800 kbit/s) picks 360p; fast lines pick more', () {
      expect(NetQuality.pickHeight(<int>[720, 480, 360], 800), 360);
      expect(NetQuality.pickHeight(<int>[720, 480, 360], 1300), 480);
      expect(NetQuality.pickHeight(<int>[1080, 720, 480], 5000), 1080);
      expect(NetQuality.pickHeight(<int>[720, 480, 360], -1), 360);
    });
  });

  test('adaptive quality: windows end on a keyframe shared by both renditions', () async {
    final HttpServer a = await serve(mp4);
    final HttpServer b = await serve(File('test/fixtures/faststart_sample_b.mp4').readAsBytesSync());
    final String ua = 'http://127.0.0.1:${a.port}/a.mp4', ub = 'http://127.0.0.1:${b.port}/b.mp4';
    final List<double> keysB = (await FastStart.index(ub, const <String, String>{})).keyframeTimes;
    // Rendition A has a keyframe every 2 s, B every 3 s → shared every 6 s.
    final FastWindow w1 = await FastStart.open(ua, const <String, String>{},
        from: 1, length: 3, alignTo: <List<double>>[keysB]);
    expect(Mp4Index.hasKeyframeNear(keysB, w1.endKeyTime, 0.06), isTrue);
    expect(w1.end, closeTo(6, 0.1)); // display time of the shared keyframe
    // The next window from B starts exactly where A's ends.
    final FastWindow w2 = await FastStart.open(ub, const <String, String>{}, from: w1.end, length: 6);
    expect(w2.offset, closeTo(w1.end, 0.05));
    await a.close(force: true);
    await b.close(force: true);
  });
}
