/// Tolerant JSON → model mappers.
///
/// The app is built to work with many common REST backend shapes: field names
/// are looked up through alias lists (e.g. `poster`, `image`, `cover`,
/// `thumbnail` all map to [Anime.poster]) and relative image paths are
/// resolved against the configured base URL.
library;

import 'app_data.dart';

// ---------------------------------------------------------------------------
// Low-level tolerant readers
// ---------------------------------------------------------------------------

String _pick(Map<String, dynamic> j, List<String> keys, [String fallback = '']) {
  for (final String k in keys) {
    final dynamic v = j[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  return fallback;
}

double _num(Map<String, dynamic> j, List<String> keys, [double fallback = 0]) {
  for (final String k in keys) {
    final dynamic v = j[k];
    if (v is num) return v.toDouble();
    if (v is String) {
      final double? d = double.tryParse(v);
      if (d != null) return d;
    }
  }
  return fallback;
}

int _int(Map<String, dynamic> j, List<String> keys, [int fallback = 0]) {
  for (final String k in keys) {
    final dynamic v = j[k];
    if (v is num) return v.toInt();
    if (v is String) {
      final int? i = int.tryParse(v);
      if (i != null) return i;
      final double? d = double.tryParse(v);
      if (d != null) return d.toInt();
    }
  }
  return fallback;
}

bool _bool(Map<String, dynamic> j, List<String> keys, [bool fallback = false]) {
  for (final String k in keys) {
    final dynamic v = j[k];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final String s = v.toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
  }
  return fallback;
}

List<String> _strList(Map<String, dynamic> j, List<String> keys) {
  for (final String k in keys) {
    final dynamic v = j[k];
    if (v is List) {
      return v
          .map<String>((dynamic e) => e is Map
              ? (e['name'] ?? e['title'] ?? e['label'] ?? '').toString()
              : e.toString())
          .where((String s) => s.trim().isNotEmpty)
          .toList();
    }
    if (v is String && v.trim().isNotEmpty) {
      // Allow comma-separated strings: "Action, Comedy, Shounen".
      return v
          .split(RegExp(r'[,;|]'))
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
    }
  }
  return const <String>[];
}

String? _imageUrl(Map<String, dynamic> j, List<String> keys, String baseUrl) {
  for (final String k in keys) {
    dynamic v = j[k];
    if (v is Map) {
      // e.g. coverImage: { large: ..., medium: ..., original: ... }
      v = v['large'] ?? v['extraLarge'] ?? v['original'] ?? v['medium'] ?? v['url'] ?? v['src'];
    }
    if (v is List && v.isNotEmpty) v = v.first;
    if (v == null) continue;
    final String s = v.toString().trim();
    if (s.isEmpty) continue;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('/')) {
      // Relative path from the backend: resolve against base URL.
      return baseUrl.isNotEmpty ? '${baseUrl.trim()}$s' : s;
    }
    return s;
  }
  return null;
}

String _stripHtml(String s) =>
    s.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

// ---------------------------------------------------------------------------
// Anime
// ---------------------------------------------------------------------------

Anime animeFromJson(Map<String, dynamic> j, {String baseUrl = '', int index = 0}) {
  final String id = _pick(j, const <String>[
    'id', '_id', 'mal_id', 'animeId', 'anime_id', 'uuid', 'slug', 'key',
  ], 'remote-$index');

  final String title = _pick(j, const <String>[
    'title', 'name', 'titleEnglish', 'title_english', 'title_en',
    'titleEn', 'romaji', 'titleRomaji', 'display_name', 'displayName',
  ], 'بدون عنوان');

  final String? poster = _imageUrl(j, const <String>[
    'poster', 'image', 'posterUrl', 'poster_url', 'cover', 'coverImage',
    'cover_image', 'thumbnail', 'thumb', 'imageUrl', 'image_url', 'img',
    'bannerImage', 'art', 'picture', 'photo',
  ], baseUrl);

  double score = _num(j, const <String>[
    'score', 'rating', 'vote_average', 'voteAverage', 'rate', 'averageScore',
    'average_score', 'scored_by_avg', 'imdb',
  ], 0);
  if (score > 10) score = score / 10; // handle 0–100 scales
  if (score > 10) score = 10;

  String year = _pick(j, const <String>[
    'year', 'releaseYear', 'release_year', 'seasonYear', 'season_year',
    'start_date', 'startDate', 'releaseDate', 'release_date', 'aired_from',
    'premiered', 'first_air_date',
  ]);
  if (year.length >= 4) {
    final RegExpMatch? m = RegExp(r'(\d{4})').firstMatch(year);
    if (m != null) year = m.group(1)!;
  } else {
    year = '';
  }

  final String type = _pick(j, const <String>[
    'type', 'format', 'kind', 'media_type', 'mediaType',
  ], 'TV');

  final bool isMovie = _bool(j, const <String>['isMovie', 'is_movie', 'movie']) ||
      type.toLowerCase().contains('movie') ||
      type.toLowerCase() == 'film';

  String duration = _pick(j, const <String>[
    'duration', 'runtime', 'length', 'episode_length', 'episodeLength',
  ]);
  final dynamic rawDuration = j.containsKey('duration')
      ? j['duration']
      : (j.containsKey('runtime') ? j['runtime'] : null);
  if (rawDuration is num && rawDuration > 0) {
    duration = rawDuration >= 60
        ? '${rawDuration ~/ 60}h ${rawDuration % 60}m'
        : '${rawDuration.toInt()}m';
  }
  if (duration.isEmpty) duration = isMovie ? '1h 50m' : '24m';

  String status = _pick(j, const <String>[
    'status', 'airing_status', 'airingStatus', 'state',
  ]);
  if (j['airing'] is bool) status = (j['airing'] as bool) ? 'يُعرض الآن' : 'مكتمل';

  final String studio = _pick(j, const <String>[
    'studio', 'studios', 'producer', 'network', 'production',
  ]);

  String synopsis = _stripHtml(_pick(j, const <String>[
    'synopsis', 'description', 'overview', 'plot', 'summary', 'about', 'story',
  ]));

  int episodeCount = _int(j, const <String>[
    'episodeCount', 'episode_count', 'episodes', 'totalEpisodes',
    'total_episodes', 'nb_episodes', 'num_episodes', 'length',
  ], isMovie ? 1 : 12);
  if (episodeCount <= 0) episodeCount = isMovie ? 1 : 12;

  return Anime(
    id: id,
    title: title,
    poster: poster ?? '',
    score: score,
    year: year,
    genres: _strList(j, const <String>[
      'genres', 'categories', 'tags', 'themes', 'theme', 'category',
    ]),
    synopsis: synopsis,
    episodeCount: episodeCount,
    ageRating: _pick(j, const <String>[
      'ageRating', 'age_rating', 'rating', 'rated', 'mpaa', 'age',
    ], '13+'),
    isMovie: isMovie,
    duration: duration,
    slug: _pick(j, const <String>['slug', 'watchSlug', 'watch_slug', 'watch_path']),
    isRemote: true,
    type: type,
    status: status,
    studio: studio,
  );
}

// ---------------------------------------------------------------------------
// Episode
// ---------------------------------------------------------------------------

Episode episodeFromJson(Map<String, dynamic> j, {String baseUrl = '', int index = 0}) {
  int number = _int(j, const <String>[
    'number', 'num', 'episode', 'episode_number', 'episodeNumber', 'ep', 'index',
  ], index + 1);
  if (number <= 0) number = index + 1;

  String duration = _pick(j, const <String>['duration', 'runtime', 'length']);
  final dynamic rawDuration = j.containsKey('duration') ? j['duration'] : j['runtime'];
  if (rawDuration is num && rawDuration > 0) duration = '${rawDuration.toInt()}m';

  final String? thumb = _imageUrl(j, const <String>[
    'thumb', 'thumbnail', 'image', 'still', 'still_url', 'image_url', 'img',
  ], baseUrl);

  return Episode(
    number,
    _pick(j, const <String>['title', 'name'], 'الحلقة $number'),
    duration.isEmpty ? '24m' : duration,
    thumb ?? '',
    aired: _pick(j, const <String>[
      'aired', 'air_date', 'airDate', 'release_date', 'releaseDate', 'date',
    ]),
    hasSub: _bool(j, const <String>['hasSub', 'has_sub', 'sub', 'subbed'], true),
    hasDub: _bool(j, const <String>['hasDub', 'has_dub', 'dub', 'dubbed'], false),
  );
}

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

/// Builds a CalendarEntry from a map that must contain an `episode` number and
/// either a nested `anime` object, or an `animeId` resolvable in [byId], or a
/// minimal `{title, image}` pair.
CalendarEntry? calendarEntryFromJson(Map<String, dynamic> j,
    {String baseUrl = '', Map<String, Anime> byId = const <String, Anime>{}}) {
  final int episode = _int(j, const <String>[
    'episode', 'ep', 'episode_number', 'episodeNumber', 'number', 'epNum',
  ], 1);

  String time = _pick(j, const <String>[
    'time', 'airTime', 'air_time', 'airtime', 'at', 'release_time', 'releaseTime',
  ]);
  // Full ISO datetime → extract HH:MM.
  if (time.contains('T') || time.contains(' ')) {
    final DateTime? dt = DateTime.tryParse(time);
    if (dt != null) {
      time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }
  if (time.isEmpty) time = '00:00';

  Anime? anime;
  final dynamic nested = j['anime'] ?? j['title_anime'] ?? j['show'];
  if (nested is Map) {
    anime = animeFromJson(Map<String, dynamic>.from(nested), baseUrl: baseUrl);
  } else {
    final String refId = _pick(j, const <String>['animeId', 'anime_id', 'id']);
    if (refId.isNotEmpty && byId.containsKey(refId)) {
      anime = byId[refId];
    } else if (nested is String && nested.isNotEmpty) {
      // Bare title string — look it up or synthesize.
      for (final Anime a in byId.values) {
        if (a.title.toLowerCase() == nested.toLowerCase()) {
          anime = a;
          break;
        }
      }
      anime ??= Anime(id: 'cal-${j.hashCode}', title: nested, poster: '',
          score: 0, year: '', genres: const <String>[], synopsis: '', isRemote: true);
    }
  }
  if (anime == null) return null;
  return CalendarEntry(time, anime, episode);
}

// ---------------------------------------------------------------------------
// Notice (notifications)
// ---------------------------------------------------------------------------

Notice? noticeFromJson(Map<String, dynamic> j,
    {String baseUrl = '', Map<String, Anime> byId = const <String, Anime>{}}) {
  final int episode = _int(j, const <String>[
    'episode', 'ep', 'episode_number', 'episodeNumber', 'number',
  ], 1);

  String when = _pick(j, const <String>[
    'when', 'time', 'timeAgo', 'time_ago', 'createdAt', 'created_at', 'date', 'published_at',
  ]);
  final DateTime? dt = DateTime.tryParse(when);
  if (dt != null) {
    final Duration diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) {
      when = 'الآن';
    } else if (diff.inMinutes < 60) {
      when = 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      when = 'منذ ${diff.inHours} ساعة';
    } else if (diff.inDays == 1) {
      when = 'أمس';
    } else if (diff.inDays < 30) {
      when = 'منذ ${diff.inDays} يوم';
    } else {
      when = '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    }
  }
  if (when.isEmpty) when = 'مؤخرًا';

  Anime? anime;
  final dynamic nested = j['anime'] ?? j['show'];
  if (nested is Map) {
    anime = animeFromJson(Map<String, dynamic>.from(nested), baseUrl: baseUrl);
  } else {
    final String refId = _pick(j, const <String>['animeId', 'anime_id', 'id']);
    if (refId.isNotEmpty && byId.containsKey(refId)) anime = byId[refId];
  }
  if (anime == null) return null;
  return Notice(anime, episode, when);
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

class AuthUser {
  const AuthUser({this.name = '', this.email = '', this.avatar = ''});
  final String name;
  final String email;
  final String avatar;
}

AuthUser authUserFromJson(Map<String, dynamic> j) {
  String name = _pick(j, const <String>[
    'name', 'username', 'userName', 'user_name', 'nickname', 'displayName',
    'display_name', 'fullName', 'full_name',
  ]);
  final String email = _pick(j, const <String>['email', 'mail', 'emailAddress']);
  if (name.isEmpty && email.isNotEmpty) name = email.split('@').first;
  final String? avatar = _imageUrl(j, const <String>[
    'avatar', 'photo', 'image', 'profileImage', 'profile_image', 'picture',
  ], '');
  return AuthUser(name: name, email: email, avatar: avatar ?? '');
}

/// Extracts a bearer token from a login/register response body.
String? tokenFromResponse(dynamic body) {
  if (body is! Map) return null;
  final Map<String, dynamic> j = Map<String, dynamic>.from(body);
  final Map<String, dynamic> inner = j['data'] is Map
      ? Map<String, dynamic>.from(j['data'] as Map)
      : (j['user'] is Map ? Map<String, dynamic>.from(j['user'] as Map) : j);
  for (final Map<String, dynamic> src in <Map<String, dynamic>>[j, inner]) {
    for (final String k in const <String>[
      'token', 'accessToken', 'access_token', 'jwt', 'authToken', 'auth_token', 'api_token',
    ]) {
      final dynamic v = src[k];
      if (v is String && v.isNotEmpty) return v;
    }
  }
  return null;
}

/// Extracts the user object from a login/register response body.
Map<String, dynamic>? userFromResponse(dynamic body) {
  if (body is! Map) return null;
  final Map<String, dynamic> j = Map<String, dynamic>.from(body);
  if (j['user'] is Map) return Map<String, dynamic>.from(j['user'] as Map);
  if (j['data'] is Map) {
    final Map<String, dynamic> d = Map<String, dynamic>.from(j['data'] as Map);
    if (d['user'] is Map) return Map<String, dynamic>.from(d['user'] as Map);
    if (d.containsKey('email') || d.containsKey('username')) return d;
  }
  if (j.containsKey('email') || j.containsKey('username')) return j;
  return null;
}
