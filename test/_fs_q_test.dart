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
  test('qualities', () async {
    HttpOverrides.global = _Net();
    for (final String page in <String>['/movie/11708/steps', '/movie/11687/insidious-possession']) {
      final List<AkwamSource> src = await AkwamApi.I.sourcesForPath(page);
      for (final AkwamSource s in src) {
        final String url = await AkwamApi.I.resolveStream(s.watchPath);
        final RangeReader r = RangeReader(url, <String, String>{'User-Agent': AkwamApi.ua, 'Referer': '${AkwamApi.base}/'});
        await r.read(0, 16);
        print('$page ${s.quality} ${s.size} ${s.watchPath} -> ${url.split('/').last} len=${(r.totalLength / 1e6).toStringAsFixed(0)}MB');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
