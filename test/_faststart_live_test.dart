// Temporary live benchmark (deleted after use): Akwam at a simulated 100 KB/s.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:animax/core/akwam_api.dart';
import 'package:animax/core/app_http.dart' show kSsl2BuyIntermediatePem;
import 'package:animax/core/fast_start.dart';
import 'package:flutter_test/flutter_test.dart';

class _Net extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final SecurityContext ctx = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificates('/root/.ccr/ca-bundle.crt')
      ..setTrustedCertificatesBytes(utf8.encode(kSsl2BuyIntermediatePem));
    final HttpClient c = super.createHttpClient(ctx);
    c.findProxy = HttpClient.findProxyFromEnvironment;
    return c;
  }
}

const String out = String.fromEnvironment('OUT');
const int bps = 100 * 1024;

/// Local "slow internet": forwards range GETs to [origin] at [bps].
Future<HttpServer> throttle(String origin, Map<String, String> headers) async {
  final HttpClient up = HttpClient();
  final HttpServer s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((HttpRequest rq) async {
    try {
      final HttpClientRequest r = await up.getUrl(Uri.parse(origin));
      headers.forEach(r.headers.set);
      final String? range = rq.headers.value('range');
      if (range != null) r.headers.set('range', range);
      final HttpClientResponse u = await r.close();
      rq.response.statusCode = u.statusCode;
      for (final String h in <String>['content-type', 'content-length', 'content-range', 'accept-ranges']) {
        final String? v = u.headers.value(h);
        if (v != null) rq.response.headers.set(h, v);
      }
      final Stopwatch sw = Stopwatch()..start();
      int sent = 0;
      await for (final List<int> c in u) {
        for (int i = 0; i < c.length; i += 4096) {
          final List<int> part = c.sublist(i, math.min(c.length, i + 4096));
          sent += part.length;
          final int due = (sent * 1000 / bps).round() - sw.elapsedMilliseconds;
          if (due > 0) await Future<void>.delayed(Duration(milliseconds: due));
          rq.response.add(part);
          await rq.response.flush();
        }
      }
      await rq.response.close();
    } catch (_) {
      try { await rq.response.close(); } catch (_) {}
    }
  });
  return s;
}

/// Seconds until ffmpeg decodes the first video frame at [ss].
Future<double> firstFrame(String url, double ss, String png) async {
  final Stopwatch sw = Stopwatch()..start();
  final ProcessResult r = await Process.run('ffmpeg', <String>[
    '-v', 'error', '-y', '-rw_timeout', '120000000',
    if (ss > 0) ...<String>['-ss', ss.toStringAsFixed(3)],
    '-i', url, '-frames:v', '1', '-vf', 'scale=320:-1', png,
  ], environment: <String, String>{'no_proxy': '127.0.0.1', 'NO_PROXY': '127.0.0.1'});
  sw.stop();
  if (r.exitCode != 0) return -1;
  return sw.elapsedMilliseconds / 1000;
}

Future<String> probe(String url) async {
  final ProcessResult r = await Process.run('ffprobe', <String>[
    '-v', 'error', '-show_entries', 'stream=codec_type,duration:format=duration', '-of', 'compact', url,
  ], environment: <String, String>{'no_proxy': '127.0.0.1', 'NO_PROXY': '127.0.0.1'});
  return '${r.stdout}${r.stderr}'.trim().replaceAll('\n', ' | ');
}

Future<double> psnr(String a, String b) async {
  final ProcessResult r = await Process.run('ffmpeg', <String>['-v', 'info', '-i', a, '-i', b, '-lavfi', 'psnr', '-f', 'null', '-']);
  final RegExpMatch? m = RegExp(r'average:([\d.inf]+)').firstMatch('${r.stderr}');
  return m == null ? -1 : (m.group(1) == 'inf' ? 99 : double.parse(m.group(1)!));
}

void main() {
  test('fast start vs direct at 100 KB/s', () async {
    HttpOverrides.global = _Net();
    final StringBuffer rep = StringBuffer();
    void log(Object o) {
      print(o);
      rep.writeln(o);
    }

    Future<void> bench(String label, String watchPage, List<double> starts) async {
      final List<AkwamSource> src = await AkwamApi.I.sourcesForPath(watchPage);
      log('== $label: qualities ${src.map((AkwamSource s) => '${s.quality} ${s.size}').join(', ')}');
      final AkwamSource low = src.last;
      final String url = await AkwamApi.I.resolveStream(low.watchPath);
      final Map<String, String> h = <String, String>{'User-Agent': AkwamApi.ua, 'Referer': '${AkwamApi.base}/'};
      for (final double t in starts) {
        // Each run gets a fresh throttle + fresh index (cold cache).
        final HttpServer th = await throttle(url, h);
        final String slow = 'http://127.0.0.1:${th.port}/v.mp4';
        final double direct = await firstFrame(slow, t, '$out/fs_direct_$t.png');
        await th.close(force: true);

        final HttpServer th2 = await throttle(url, h);
        final String slow2 = 'http://127.0.0.1:${th2.port}/v.mp4';
        final Stopwatch sw = Stopwatch()..start();
        final FastWindow w = await FastStart.open(slow2, const <String, String>{}, from: t, length: 120);
        final double idx = sw.elapsedMilliseconds / 1000;
        final double ff = await firstFrame(w.uri.toString(), 0, '$out/fs_fast_$t.png');
        final double fast = idx + ff;
        log('  start ${t.toStringAsFixed(0)}s [${low.quality}]: direct=${direct.toStringAsFixed(1)}s  '
            'fast=${fast.toStringAsFixed(1)}s (index ${idx.toStringAsFixed(1)}s, ${(w.indexBytes / 1024).toStringAsFixed(0)} KB head) '
            'window ${w.offset.toStringAsFixed(2)}..${w.end.toStringAsFixed(2)} of ${w.total.toStringAsFixed(0)}s');
        // Correctness: same picture as the original at the same real time.
        final double tt = w.offset + 3.0;
        await firstFrame(url, tt, '$out/fs_ref_$t.png');
        await firstFrame(w.uri.toString(), 3.0, '$out/fs_win_$t.png');
        log('    frame match @${tt.toStringAsFixed(2)}s PSNR=${(await psnr('$out/fs_ref_$t.png', '$out/fs_win_$t.png')).toStringAsFixed(1)} dB; '
            'probe: ${await probe(w.uri.toString())}');
        await th2.close(force: true);
      }
    }

    // A movie (moov at the start) and a series episode.
    await bench('movie Steps', '/movie/11708/steps', <double>[0, 1800]);
    final List<AkwamSource> mv = await AkwamApi.I.sourcesForPath('/movie/11713/on-behalf-of-my-son');
    log('On Behalf (moov at end) qualities: ${mv.length}');
    await bench('movie On Behalf (moov at end)', '/movie/11713/on-behalf-of-my-son', <double>[1200]);
    File('$out/faststart_report.txt').writeAsStringSync(rep.toString());
  }, timeout: const Timeout(Duration(minutes: 25)));
}
