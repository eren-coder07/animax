/// Parsers for the Aniwaves-style AJAX API.
///
/// This backend returns JSON envelopes whose payloads are **HTML fragments**
/// rendered server-side:
///
///   { "status": 200, "html" | "result": "<div class=…>…" }
///
/// The parsers below turn those fragments into the app's models using
/// regex extraction (zero third-party HTML dependencies). The shapes match
/// the captured traffic:
///
///  * Catalog/trending cards   `<a class="item" href="/watch/slug-81553">…`
///  * Episode rows             `<li … data-num="1" data-aired="…" data-sub="1">`
///  * Server rows              `<li data-sv-id="14" data-link-id="…">Name</li>`
///  * Watch page               og:* meta, h1, film-description, /genre/ links
library;

import 'app_data.dart';

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

const Map<String, String> _namedEntities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'rsquo': '\u2019',
  'lsquo': '\u2018',
  'rdquo': '\u201d',
  'ldquo': '\u201c',
};

/// Decodes HTML entities: named (`&amp;`) and numeric (`&#039;`, `&#x27;`).
String decodeEntities(String input) {
  if (!input.contains('&')) return input;
  return input.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'),
      (Match m) {
    final String body = m.group(1)!;
    if (body.startsWith('#')) {
      final bool hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final int? code =
          int.tryParse(body.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
      if (code != null && code > 0) {
        return String.fromCharCode(code);
      }
      return m.group(0)!;
    }
    return _namedEntities[body.toLowerCase()] ?? m.group(0)!;
  });
}

String _stripTags(String s) =>
    decodeEntities(s.replaceAll(RegExp(r'<[^>]*>'), ' ').trim());

/// Extracts `attr="value"` pairs from a raw tag string.
Map<String, String> _attrs(String tag) {
  final Map<String, String> out = <String, String>{};
  for (final RegExpMatch m
      in RegExp(r'([\w:-]+)\s*=\s*"([^"]*)"').allMatches(tag)) {
    out[m.group(1)!.toLowerCase()] = decodeEntities(m.group(2)!);
  }
  for (final RegExpMatch m
      in RegExp(r"([\w:-]+)\s*=\s*'([^']*)'").allMatches(tag)) {
    out.putIfAbsent(m.group(1)!.toLowerCase(), () => decodeEntities(m.group(2)!));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Item cards (trending / recommendations / catalog pages)
// ---------------------------------------------------------------------------

/// Parses `<a class="item" href="/watch/slug-81553">` catalog cards.
///
/// Works for the `/ajax/v2/trending`, `/ajax/v2/recommendations` fragments and
/// for full catalog pages (home, `/genre/{slug}`, `/filter?keyword=…`) that
/// reuse the same card markup.
List<Anime> parseItemCards(String html) {
  final List<Anime> out = <Anime>[];
  // `class="item"` and `class="item "` (trailing space, as served by the
  // /filter search page) plus any modifier variants.
  final RegExp card = RegExp(
    r'<a\s+class="item(?:\s[^"]*)?"\s+href="/watch/([^"]+)"(.*?)</a>',
    dotAll: true,
  );

  for (final RegExpMatch m in card.allMatches(html)) {
    final String slug = decodeEntities(m.group(1)!);
    final String body = m.group(2)!;

    final RegExpMatch? img =
        RegExp(r'<img[^>]+src="(https?://[^"]+|/[^"]+)"').firstMatch(body);
    final String poster = img == null ? '' : decodeEntities(img.group(1)!);

    final RegExpMatch? name = RegExp(
      r'class="name[^"]*"[^>]*>([^<]+)<',
      dotAll: true,
    ).firstMatch(body);
    final String title = name == null ? '' : _stripTags(name.group(1)!);
    if (title.isEmpty || slug.isEmpty) continue;

    // Meta dots: <span class="dot score …">… 9</span><span class="dot">TV</span><span class="dot">1999</span>
    double score = 0;
    String type = 'TV';
    String year = '';
    final RegExp dot =
        RegExp(r'<span class="dot([^"]*)"[^>]*>(.*?)</span>', dotAll: true);
    bool scoreSeen = false;
    final List<String> rest = <String>[];
    for (final RegExpMatch d in dot.allMatches(body)) {
      final String cls = d.group(1) ?? '';
      final String text = _stripTags(d.group(2)!);
      if (cls.contains('score')) {
        final double? v = double.tryParse(text.trim());
        if (v != null) {
          score = v;
          scoreSeen = true;
          continue;
        }
      }
      if (text.isNotEmpty) rest.add(text);
    }
    if (!scoreSeen && rest.isNotEmpty) {
      // Some layouts put the score in a plain dot first.
      final double? v = double.tryParse(rest.first);
      if (v != null && v >= 1 && v <= 10) {
        score = v;
        rest.removeAt(0);
      }
    }
    for (final String t in rest) {
      if (RegExp(r'^\d{4}$').hasMatch(t)) {
        year = t;
      } else if (type == 'TV') {
        type = t;
      }
    }

    out.add(Anime(
      id: slug,
      title: title,
      poster: poster,
      score: score,
      year: year,
      genres: const <String>[],
      synopsis: '',
      slug: slug,
      isRemote: true,
      type: type,
    ));
  }
  return out;
}

/// Numeric Aniwaves id (e.g. `82796`) from a slug like
/// `tsuihou-sareta-…-82796`. Falls back to the whole slug when there is no
/// trailing number.
String? watchIdOf(String? slug) {
  if (slug == null || slug.isEmpty) return null;
  final RegExpMatch? m = RegExp(r'(\d+)\s*$').firstMatch(slug);
  if (m != null) return m.group(1);
  return slug;
}

/// Parses the full-width result cards the `/filter` page renders for keyword
/// searches (`<div id="list-items" class="ani items"><div class="item …">`).
///
/// Shape (captured in the user's HAR):
/// ```html
/// <div class="item "><div class="inner">
///   <div class="ani poster …" data-tip="81553">
///     <a href="/watch/one-piece-81553"><img src="…thumbnail…" alt="…">…</a>
///   </div>
///   <div class="info"><div class="b1">
///     <a class="name d-title" href="/watch/one-piece-81553" data-jp="One Piece">One Piece</a>
///     <div class="genre"><a href="/genre/action">Action</a>, …</div>
///   </div>
///   <div class="meta">… <div class="m-item rated"><span> 9</span> … star …
/// ```
List<Anime> parseFilterCards(String html) {
  final List<Anime> out = <Anime>[];

  // Split into card blocks: each starts with `<div class="item…">` followed
  // by `<div class="inner">`. The lookahead keeps the next card boundary.
  final RegExp block = RegExp(
    r'<div class="item(?:\s[^"]*)?">\s*<div class="inner">(.*?)(?=<div class="item(?:\s[^"]*)?">\s*<div class="inner">|</div>\s*</div>\s*$)',
    dotAll: true,
  );

  for (final RegExpMatch m in block.allMatches(html)) {
    final String body = m.group(1)!;

    final RegExpMatch? link =
        RegExp(r'<a href="/watch/([^"]+)"').firstMatch(body);
    final String slug = link == null ? '' : decodeEntities(link.group(1)!);

    final RegExpMatch? name = RegExp(
      r'<a class="name[^"]*"[^>]*>([^<]+)</a>',
      dotAll: true,
    ).firstMatch(body);
    final String title = name == null ? '' : _stripTags(name.group(1)!);
    if (slug.isEmpty || title.isEmpty) continue;

    final RegExpMatch? img =
        RegExp(r'<img[^>]+src="(https?://[^"]+|/[^"]+)"').firstMatch(body);
    final String poster = img == null ? '' : decodeEntities(img.group(1)!);

    final List<String> genres = <String>[];
    final RegExpMatch? genreBlock =
        RegExp(r'<div class="genre">(.*?)</div>', dotAll: true).firstMatch(body);
    if (genreBlock != null) {
      for (final RegExpMatch g
          in RegExp(r'>([^<>]+)</a>').allMatches(genreBlock.group(1)!)) {
        final String t = _stripTags(g.group(1)!);
        if (t.isNotEmpty) genres.add(t);
      }
    }

    double score = 0;
    final RegExpMatch? rated = RegExp(
      r'm-item rated"><span>\s*([\d.]+)\s*</span>',
      dotAll: true,
    ).firstMatch(body);
    if (rated != null) score = double.tryParse(rated.group(1)!) ?? 0;

    String type = 'TV';
    final RegExpMatch? right =
        RegExp(r'<div class="right">([^<]*)</div>').firstMatch(body);
    if (right != null && right.group(1)!.trim().isNotEmpty) {
      type = _stripTags(right.group(1)!);
    }

    out.add(Anime(
      id: slug,
      title: title,
      poster: poster,
      score: score,
      year: '',
      genres: genres,
      synopsis: '',
      slug: slug,
      isRemote: true,
      type: type,
    ));
  }
  return out;
}

extension AnimeWatchId on Anime {
  /// Numeric backend id used by `/ajax/episode/list/{id}` and friends.
  String? get watchId => watchIdOf(slug ?? id);

  /// Watch-page URL for episode [ep] (defaults to the show page).
  String watchUrl({String base = 'https://aniwaves.tv', int? ep}) {
    final String s = slug ?? id;
    return ep == null ? '$base/watch/$s' : '$base/watch/$s/ep-$ep';
  }
}

// ---------------------------------------------------------------------------
// Episode list  —  /ajax/episode/list/{id}
// ---------------------------------------------------------------------------

/// Parses the episode-list fragment into [Episode]s.
///
/// Row shape (captured):
/// `<li title="Release: 2026/10/06 15:00 GMT - Title" …><a href="/watch/82796/ep-1"
///     data-num="1" data-aired="2026-10-07T00:00:00+09:00"
///     data-timestamp="2026-10-06 15:00:00" data-duration="1420"
///     data-sub="1" data-dub="1" …><b>1</b>
///     <span class="d-title" data-jp="…">English title</span></a></li>`
List<Episode> parseEpisodeList(String html) {
  final List<Episode> out = <Episode>[];
  final RegExp anchor =
      RegExp(r'<a\s+[^>]*data-num="(\d+)"[^>]*>(.*?)</a>', dotAll: true);

  for (final RegExpMatch m in anchor.allMatches(html)) {
    final Map<String, String> a = _attrs(m.group(0)!);
    final int num = int.tryParse(m.group(1)!) ?? (out.length + 1);

    final RegExpMatch? t = RegExp(
      r'<span class="d-title"[^>]*>(.*?)</span>',
      dotAll: true,
    ).firstMatch(m.group(2)!);
    String title = t == null ? '' : _stripTags(t.group(1)!);
    if (title.isEmpty || title == 'الحلقة $num') {
      title = 'الحلقة $num';
    }

    final int? durSec = int.tryParse(a['data-duration'] ?? '');
    final String duration =
        durSec == null || durSec <= 0 ? '' : '${(durSec / 60).round()}m';

    out.add(Episode(
      num,
      title,
      duration,
      '', // episode stills are not provided by this endpoint
      aired: (a['data-aired'] ?? '').isNotEmpty
          ? a['data-aired']
          : a['data-timestamp'],
      hasSub: a['data-sub'] == '1',
      hasDub: a['data-dub'] == '1',
    ));
  }

  out.sort((Episode x, Episode y) => x.number.compareTo(y.number));
  return out;
}

// ---------------------------------------------------------------------------
// Server list  —  /ajax/server/list?servers={id}&eps={ep}
// ---------------------------------------------------------------------------

class EpisodeServer {
  const EpisodeServer(this.name, this.kind, this.svId, this.linkId);
  final String name;

  /// `sub`, `ssub` (soft-sub) or `dub`.
  final String kind;
  final String svId;

  /// Opaque player token as delivered by the backend — passed through
  /// untouched; the app never decodes it (decoding is the site's own
  /// client-side job).
  final String linkId;
}

/// Parses the server-list fragment, grouped by audio track
/// (`<div class="type" data-type="sub|ssub|dub">`).
List<EpisodeServer> parseServerList(String html) {
  final List<EpisodeServer> out = <EpisodeServer>[];
  final RegExp block = RegExp(
    r'<div class="type" data-type="(\w+)">(.*?)(?=<div class="type"|$)',
    dotAll: true,
  );
  final RegExp row = RegExp(r'<li\s+[^>]*data-sv-id="[^"]*"[^>]*>(.*?)</li>',
      dotAll: true);

  for (final RegExpMatch b in block.allMatches(html)) {
    final String kind = b.group(1)!;
    for (final RegExpMatch r in row.allMatches(b.group(2)!)) {
      final Map<String, String> attrs = _attrs(r.group(0)!);
      final String name = _stripTags(r.group(1)!);
      if (name.isEmpty) continue;
      out.add(EpisodeServer(
        name,
        kind,
        attrs['data-sv-id'] ?? '',
        attrs['data-link-id'] ?? '',
      ));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Release schedule  —  /ajax/schedule/date?date=YYYY-MM-DD
// ---------------------------------------------------------------------------

/// One row of the site's daily schedule.
class ScheduleItem {
  const ScheduleItem({
    required this.slug,
    required this.episode,
    required this.time,
    this.title = '',
    this.jpTitle = '',
  });

  /// Watch slug incl. numeric id, e.g. `kyouran-reijou-…-82794`.
  final String slug;
  final int episode;

  /// Time exactly as shown on the site, e.g. `12:26 PM`.
  final String time;
  final String title;
  final String jpTitle;
}

/// Parses the schedule fragment:
/// `<a class="item" href="/watch/{slug}/ep-{n}"><div class="time"
///  data-tip="{id}">12:26 PM</div>…<div class="title d-title"
///  data-jp="…">English title</div></a>`
List<ScheduleItem> parseSchedule(String html) {
  final List<ScheduleItem> out = <ScheduleItem>[];
  final RegExp row = RegExp(
    r'<a\s+class="item[^"]*"\s+href="/watch/([^"]+?)/ep-(\d+)"(.*?)</a>',
    dotAll: true,
  );

  for (final RegExpMatch m in row.allMatches(html)) {
    final String slug = decodeEntities(m.group(1)!);
    final int ep = int.tryParse(m.group(2)!) ?? 1;
    final String body = m.group(3)!;

    final RegExpMatch? t =
        RegExp(r'<div class="time[^"]*"[^>]*>(.*?)</div>', dotAll: true)
            .firstMatch(body);
    final String time = t == null ? '' : _stripTags(t.group(1)!);

    final RegExpMatch? title = RegExp(
      r'<div class="title[^"]*"[^>]*data-jp="([^"]*)"[^>]*>(.*?)</div>',
      dotAll: true,
    ).firstMatch(body);
    final String jp = title == null ? '' : decodeEntities(title.group(1)!);
    String name = title == null ? '' : _stripTags(title.group(2)!);
    if (name.isEmpty) name = jp;

    if (slug.isEmpty) continue;
    out.add(ScheduleItem(
      slug: slug,
      episode: ep,
      time: time,
      title: name,
      jpTitle: jp,
    ));
  }
  return out;
}

/// Converts `12:26 PM` → `12:26` (24h) so calendar rows align with the
/// UI-kit timeline; passes through unknown formats untouched.
String scheduleTime24h(String raw) {
  final RegExpMatch? m = RegExp(
    r'^\s*(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?\s*$',
  ).firstMatch(raw);
  if (m == null) return raw;
  int h = int.tryParse(m.group(1)!) ?? 0;
  final int min = int.tryParse(m.group(2)!) ?? 0;
  final String meridiem = (m.group(3) ?? '').toUpperCase();
  if (meridiem == 'PM' && h < 12) h += 12;
  if (meridiem == 'AM' && h == 12) h = 0;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Playback source  —  /ajax/sources?id={linkId}
// ---------------------------------------------------------------------------

/// Resolved playback page for one streaming server.
///
/// [url] is the embed player URL the site loads inside its own iframe
/// (e.g. `https://play.echovideo.ru/embed-20/…`). The app opens it in an
/// in-app WebView — the embed is used exactly as delivered, nothing is
/// decoded client-side.
class EpisodeSource {
  const EpisodeSource(
    this.url, {
    this.server = 0,
    this.introStart = 0,
    this.introEnd = 0,
  });

  final String url;
  final int server;
  final int introStart;
  final int introEnd;

  bool get hasIntro => introEnd > introStart;
}

/// Parses the `/ajax/sources` envelope:
/// `{"status":200,"result":{"url":"…","server":14,
///   "skip_data":{"intro":[0,0],"outro":[0,0]},…}}`
EpisodeSource? parseSourceResult(dynamic body) {
  if (body is! Map) return null;
  final dynamic status = body['status'];
  if (status != 200 && status != true) return null;
  final dynamic result = body['result'];
  if (result is! Map) return null;
  final dynamic url = result['url'];
  if (url is! String || url.trim().isEmpty) return null;

  int introStart = 0;
  int introEnd = 0;
  final dynamic skip = result['skip_data'];
  if (skip is Map && skip['intro'] is List) {
    final List<dynamic> intro = skip['intro'] as List<dynamic>;
    if (intro.length >= 2) {
      introStart = (intro[0] as num?)?.toInt() ?? 0;
      introEnd = (intro[1] as num?)?.toInt() ?? 0;
    }
  }
  return EpisodeSource(
    url,
    server: (result['server'] as num?)?.toInt() ?? 0,
    introStart: introStart,
    introEnd: introEnd,
  );
}

// ---------------------------------------------------------------------------
// Watch page details  —  GET /watch/{slug}
// ---------------------------------------------------------------------------

/// Enriches [anime] with details scraped from its watch page:
/// title (h1 / og:title), synopsis (`film-description`), poster (og:image),
/// score/type/year (meta dots) and genres (`/genre/{slug}` links).
Anime parseWatchDetails(Anime anime, String html) {
  String title = anime.title;
  final RegExpMatch? h1 = RegExp(
    r'<h1[^>]*>(.*?)</h1>',
    dotAll: true,
  ).firstMatch(html);
  if (h1 != null) {
    final String t = _stripTags(h1.group(1)!);
    if (t.isNotEmpty) title = t;
  }

  String synopsis = anime.synopsis;
  final RegExpMatch? desc = RegExp(
    r'class="[^"]*film-description[^"]*"[^>]*>(.*?)</div>',
    dotAll: true,
  ).firstMatch(html);
  if (desc != null) {
    final String d = _stripTags(desc.group(1)!);
    if (d.length > synopsis.length) synopsis = d;
  }

  String poster = anime.poster;
  final RegExpMatch? og = RegExp(
    r'property="og:image"\s+content="([^"]+)"',
  ).firstMatch(html);
  if (og != null) poster = decodeEntities(og.group(1)!);

  double score = anime.score;
  String type = anime.type == 'TV' ? '' : anime.type;
  String year = anime.year;
  final RegExp dot =
      RegExp(r'<span class="dot([^"]*)"[^>]*>(.*?)</span>', dotAll: true);
  final List<String> rest = <String>[];
  for (final RegExpMatch d in dot.allMatches(html)) {
    final String cls = d.group(1) ?? '';
    final String text = _stripTags(d.group(2)!);
    if (cls.contains('score')) {
      final double? v = double.tryParse(text.trim());
      if (v != null && v >= 1 && v <= 10 && score == 0) score = v;
      continue;
    }
    if (text.isNotEmpty) rest.add(text);
  }
  for (final String t in rest) {
    if (RegExp(r'^\d{4}$').hasMatch(t) && year.isEmpty) year = t;
    if (RegExp(r'^(TV|Movie|OVA|ONA|Special|Music)$').hasMatch(t) &&
        type.isEmpty) {
      type = t;
    }
  }

  final Set<String> genres = anime.genres.toSet();
  for (final RegExpMatch g
      in RegExp(r'href="/genre/([a-z0-9-]+)"').allMatches(html)) {
    final String raw = g.group(1)!;
    final String nice = raw
        .split('-')
        .map((String w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    genres.add(nice);
  }

  return Anime(
    id: anime.id,
    title: title,
    poster: poster.isNotEmpty ? poster : anime.poster,
    score: score,
    year: year,
    genres: genres.toList(),
    synopsis: synopsis,
    episodeCount: anime.episodeCount,
    ageRating: anime.ageRating,
    isMovie: type.toLowerCase().contains('movie') || anime.isMovie,
    duration: anime.duration,
    slug: anime.slug ?? anime.id,
    isRemote: true,
    type: type.isEmpty ? anime.type : type,
    status: anime.status,
    studio: anime.studio,
  );
}

/// Number of episodes parsed from an episode-range hint like `001-004`.
int episodeCountHint(String html) {
  int max = 0;
  for (final RegExpMatch m
      in RegExp(r'data-num="(\d+)"').allMatches(html)) {
    final int v = int.tryParse(m.group(1)!) ?? 0;
    if (v > max) max = v;
  }
  return max;
}
