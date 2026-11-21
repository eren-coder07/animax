import 'dart:convert';
import 'dart:io';
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

void main() {
  test('probe', () async {
    HttpOverrides.global = _Net();
    final List<AkwamSource> src = await AkwamApi.I.sourcesForPath('/movie/11708/steps');
    final String url = await AkwamApi.I.resolveStream(src.last.watchPath);
    final Map<String, String> h = <String, String>{'User-Agent': AkwamApi.ua, 'Referer': '${AkwamApi.base}/'};
    for (final double t in <double>[0, 1800]) {
      final Stopwatch sw = Stopwatch()..start();
      final Mp4Index ix = await Mp4Index.open(RangeReader(url, h));
      final int tOpen = sw.elapsedMilliseconds;
      final int r0 = ix.reader.requests, b0 = ix.reader.fetched;
      final WindowPlan p = await ix.plan(from: t, length: 120);
      print('t=$t open: ${tOpen}ms ${r0} req ${(b0 / 1024).round()}KB | plan: ${sw.elapsedMilliseconds - tOpen}ms '
          '${ix.reader.requests - r0} req ${((ix.reader.fetched - b0) / 1024).round()}KB');
      print('   ${ix.reader.log.join(' ')}');
      print('   region ${(p.regionEnd - p.regionStart) ~/ 1024}KB');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
