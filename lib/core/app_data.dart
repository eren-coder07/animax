/// Core data models shared by every screen.
///
/// The app is API-pure: there is no built-in sample catalog. All anime,
/// episodes, calendar rows and notifications come from the backend
/// (see [AppState]).
library;

class Anime {
  const Anime({
    required this.id,
    required this.title,
    required this.poster,
    required this.score,
    required this.year,
    required this.genres,
    required this.synopsis,
    this.episodeCount = 0,
    this.ageRating = '',
    this.isMovie = false,
    this.duration = '',
    this.slug,
    this.isRemote = true,
    this.type = 'TV',
    this.status = '',
    this.studio = '',
  });

  final String id;
  final String title;
  final String poster;
  final double score;
  final String year;
  final List<String> genres;
  final String synopsis;
  final int episodeCount;
  final String ageRating;
  final bool isMovie;
  final String duration;

  /// Watch-path slug from the backend, e.g. `one-piece-81553`.
  final String? slug;

  /// True when this entry came from the API backend (always true — the app
  /// no longer carries any bundled sample content).
  final bool isRemote;

  /// TV / Movie / OVA / ONA / Special.
  final String type;

  /// Airing status from the backend, e.g. `Airing`.
  final String status;

  /// Production studio from the backend.
  final String studio;

  bool get isNetworkPoster => poster.startsWith('http');

  String get genreLine => genres.join('. ');
}

class Episode {
  const Episode(
    this.number,
    this.title,
    this.duration,
    this.thumb, {
    this.aired,
    this.hasSub = true,
    this.hasDub = false,
  });
  final int number;
  final String title;
  final String duration;
  final String thumb;

  /// ISO air date from the backend, e.g. `2026-10-07T00:00:00+09:00`.
  final String? aired;
  final bool hasSub;
  final bool hasDub;
}

class CalendarEntry {
  const CalendarEntry(this.time, this.anime, this.episode);
  final String time; // e.g. '12:00'
  final Anime anime;
  final int episode;
}

class Notice {
  const Notice(this.anime, this.episode, this.when);
  final Anime anime;
  final int episode;
  final String when;
}

/// Static UI content only (no anime data): onboarding genre suggestions and
/// help-center FAQs.
class AnimaxData {
  AnimaxData._();

  /// Genre chips shown during onboarding.
  static const List<String> genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Magic',
    'Mecha', 'Music', 'Mystery', 'Romance', 'Sci-Fi', 'Shounen',
    'Slice of Life', 'Sports', 'Supernatural', 'Television',
  ];

  static const List<Map<String, String>> faqs = [
    {
      'q': 'How do I play an episode?',
      'a': 'Open any title, tap an episode and pick a server under SUB / S-SUB / DUB. Playback runs inside the app on the native player — no browser needed.',
    },
    {
      'q': 'A server is not loading — what now?',
      'a': 'Streaming servers occasionally go down. Switch to another server chip in the player, or try a different audio track (SUB or DUB). The player falls back automatically and reports which server it is using.',
    },
    {
      'q': 'Where do the release times come from?',
      'a': 'The Release Calendar is loaded from the schedule and shows the exact airing times for each episode, so new simulcast episodes appear the moment they drop.',
    },
    {
      'q': 'What is the Akwam section?',
      'a': 'The Akwam tab lists Arabic movies, series and shows from akwam.ss. Playback is a direct MP4 stream inside the app — pick a quality, tap play, and switch servers or qualities from the player.',
    },
  ];
}
