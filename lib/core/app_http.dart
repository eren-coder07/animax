import 'dart:io' show Platform;

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Platform-aware HTTP client factory.
///
/// hentaihaven.xxx (and other CF-fronted backends) serve a Cloudflare bot
/// challenge (`cf-mitigated: challenge`, HTTP 403) to dart:io's TLS
/// fingerprint — verified live: curl passes, Dart's HttpClient gets 403
/// "Just a moment...". Cronet is Chromium's own network library, so its TLS
/// handshake is indistinguishable from a real Chrome browser and passes.
///
/// * Android → Cronet (embedded build via `--dart-define=cronetHttpNoPlay=true`,
///   so devices without Google Play Services still work).
/// * Tests / other hosts → dart:io IOClient (unchanged behavior).
http.Client createHttpClient() {
  if (Platform.isAndroid) {
    try {
      final CronetEngine engine = CronetEngine.build(enableHttp2: true);
      return CronetClient.fromCronetEngine(engine, closeEngine: true);
    } catch (_) {
      // Cronet could not be built on this device — fall through to dart:io.
    }
  }
  return IOClient();
}
