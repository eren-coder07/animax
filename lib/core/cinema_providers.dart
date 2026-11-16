/// Multi-provider embed engine for the Cinema section.
///
/// The previous release used a single embed host; when that host decided to
/// run its bot-verification against the in-app WebView the player ended on a
/// "Verification failed" screen with no way out. This registry gives every
/// title several independent servers: the player loads them in order,
/// detects the failure screens through a JS probe ([verificationProbeJs]) and
/// silently moves to the next server, or the user picks one manually.
library;

/// One embed server (provider) that can play movies + episodes by IMDb id.
class CinemaProvider {
  const CinemaProvider({
    required this.id,
    required this.name,
    required this.home,
    required this.movie,
    required this.tv,
    this.needsTmdbForTv = false,
  });

  /// Stable id persisted in settings (`pref.cinemaProvider`).
  final String id;
  final String name;

  /// Landing host (shown in the server sheet).
  final String home;

  /// URL template for movies — `{id}` is replaced with the IMDb id.
  final String movie;

  /// URL template for episodes — `{id}` IMDb, `{tmdb}` TMDB, `{s}`/`{e}`
  /// season / episode numbers, `{ss}`/`{ee}` zero-padded.
  final String tv;

  /// True when the TV template only works with a TMDB id.
  final bool needsTmdbForTv;

  String buildMovie(String imdbId) => movie.replaceAll('{id}', imdbId);

  String? buildTv(
      {required String imdbId, String? tmdbId, required int season, required int episode}) {
    if (needsTmdbForTv && (tmdbId == null || tmdbId.isEmpty)) return null;
    return tv
        .replaceAll('{id}', imdbId)
        .replaceAll('{tmdb}', tmdbId ?? imdbId)
        .replaceAll('{ss}', season.toString().padLeft(2, '0'))
        .replaceAll('{ee}', episode.toString().padLeft(2, '0'))
        .replaceAll('{s}', season.toString())
        .replaceAll('{e}', episode.toString());
  }
}

/// Verified server order (2026-11-17): the first three answer HTTP 200 from
/// a plain HTTP client; the rest are Cloudflare-fronted (reachable from
/// consumer networks, kept as fallbacks / manual picks).
const List<CinemaProvider> cinemaProviders = <CinemaProvider>[
  CinemaProvider(
    id: 'vidsrc',
    name: 'Server 1 · VidSrc',
    home: 'vidsrc.sh',
    movie: 'https://vidsrc.sh/embed/movie/{id}',
    tv: 'https://vidsrc.sh/embed/tv/{id}/{ss}-{ee}',
  ),
  CinemaProvider(
    id: 'vidfast',
    name: 'Server 2 · VidFast',
    home: 'vidfast.pro',
    movie: 'https://vidfast.pro/movie/{id}',
    tv: 'https://vidfast.pro/tv/{id}/{s}/{e}',
  ),
  CinemaProvider(
    id: 'vidlink',
    name: 'Server 3 · VidLink',
    home: 'vidlink.pro',
    movie: 'https://vidlink.pro/movie/{id}',
    tv: 'https://vidlink.pro/tv/{tmdb}/{s}/{e}',
    needsTmdbForTv: true,
  ),
  CinemaProvider(
    id: 'vidsrccc',
    name: 'Server 4 · VidSrc CC',
    home: 'vidsrc.cc',
    movie: 'https://vidsrc.cc/v2/embed/movie/{id}',
    tv: 'https://vidsrc.cc/v2/embed/tv/{id}/{s}-{e}',
  ),
  CinemaProvider(
    id: 'twoembed',
    name: 'Server 5 · 2Embed',
    home: '2embed.cc',
    movie: 'https://www.2embed.cc/embed/{id}',
    tv: 'https://www.2embed.cc/embed/{id}/{s}-{e}',
  ),
  CinemaProvider(
    id: 'multiembed',
    name: 'Server 6 · MultiEmbed',
    home: 'multiembed.mov',
    movie: 'https://multiembed.mov/?video_id={id}',
    tv: 'https://multiembed.mov/?video_id={id}&s={s}&e={e}',
  ),
  CinemaProvider(
    id: 'vidsrcxyz',
    name: 'Server 7 · VidSrc X',
    home: 'vidsrc.xyz',
    movie: 'https://vidsrc.xyz/embed/movie?imdb={id}',
    tv: 'https://vidsrc.xyz/embed/tv?imdb={id}&season={s}&episode={e}',
  ),
];

CinemaProvider providerById(String id) {
  for (final CinemaProvider p in cinemaProviders) {
    if (p.id == id) return p;
  }
  return cinemaProviders.first;
}

/// Hosts the in-app WebView is allowed to navigate inside (all embed
/// providers + their CDN subdomains). Everything else (popunders, ad
/// redirects) is blocked by the navigation delegate.
const List<String> cinemaAllowedHosts = <String>[
  'vidsrc.sh',
  'vidsrc.me',
  'vidsrc.to',
  'vidsrc.xyz',
  'vidsrc.cc',
  'vidsrc.vip',
  'vidlink.pro',
  'vidfast.pro',
  'vidfast.vc',
  '2embed.cc',
  'multiembed.mov',
  'embed.su',
  'vidora.su',
  'vidjoy.pro',
  'vidapi.cloud',
  'vidcore.io',
  'vidcore.net',
  'stellarconductornexus.com',
  'vidsrcme.ru',
  'data.vidsrc.sh',
  'data.vidsrcme.ru',
  'nectarandnectary.space',
  'streamsrcs.2embed.cc',
  'cloudflare.com',
  'challenges.cloudflare.com',
];

bool isCinemaAllowedHost(String host) {
  for (final String h in cinemaAllowedHosts) {
    if (host == h || host.endsWith('.$h')) return true;
  }
  return false;
}

/// JS probe injected into the WebView every few seconds.
///
/// Returns a JSON string:
///  `{ "bad": bool,   — page shows a verification / failure screen
///     "video": bool, — a <video> element exists
///     "iframe": bool,— an embed iframe exists
///     "text": "…" }  — first 90 chars of page text (debugging)
const String verificationProbeJs = '''
(function() {
  var t = '';
  try { t = (document.body ? document.body.innerText : '') || ''; } catch (e) {}
  var low = t.toLowerCase();
  var bad =
    low.indexOf('verification failed') >= 0 ||
    low.indexOf('failed to verify') >= 0 ||
    low.indexOf('could not verify') >= 0 ||
    low.indexOf('unable to verify') >= 0 ||
    low.indexOf('verify you are human') >= 0 ||
    low.indexOf('checking your browser') >= 0 ||
    low.indexOf('access denied') >= 0 ||
    low.indexOf('no servers available') >= 0 ||
    low.indexOf('video not found') >= 0 ||
    low.indexOf('media not found') >= 0;
  var video = false, iframe = false;
  try { video = document.querySelector('video') !== null; } catch (e) {}
  try { iframe = document.querySelector('iframe') !== null; } catch (e) {}
  var out = { bad: bad, video: video, iframe: iframe, text: t.substring(0, 90) };
  if (window.animaxBridge) { window.animaxBridge.postMessage(JSON.stringify(out)); }
  return JSON.stringify(out);
})()
''';

/// JS message-pump that forwards the provider player's postMessage events
/// (play / pause / ended …) to the Flutter side through the `animaxBridge`
/// channel, enabling auto-next-episode for embed players that emit events.
const String messagePumpJs = '''
(function() {
  if (window.__animaxPump) return;
  window.__animaxPump = true;
  window.addEventListener('message', function(ev) {
    try {
      var d = ev.data;
      if (d === null || d === undefined) return;
      var kind = '';
      if (typeof d === 'string') { kind = d; }
      else if (typeof d === 'object') {
        kind = (d.event || d.type || d.message || '') + '';
        var src = (d.source || d.origin || '') + '';
        if (src) kind = src + ':' + kind;
      }
      if (!kind) return;
      kind = kind.toLowerCase();
      if (kind.indexOf('ended') >= 0 || kind.indexOf('finished') >= 0 ||
          kind.indexOf('complete') >= 0 || kind.indexOf('episodeend') >= 0) {
        if (window.animaxBridge) {
          window.animaxBridge.postMessage(JSON.stringify({ event: 'ended' }));
        }
      }
    } catch (e) {}
  });
})()
''';
