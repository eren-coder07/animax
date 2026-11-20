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
    'أكشن', 'مغامرة', 'كوميديا', 'دراما', 'فانتازيا', 'سحر',
    'ميكا', 'موسيقى', 'غموض', 'رومانسي', 'خيال علمي', 'شونين',
    'شريحة من الحياة', 'رياضة', 'خارق للطبيعة', 'تلفزيون',
  ];

  static const List<Map<String, String>> faqs = [
    {
      'q': 'كيف أشغّل حلقة؟',
      'a': 'افتح أي عنوان، اضغط على حلقة واختر سيرفرًا من مترجم / مترجم-S / مدبلج. التشغيل يتم داخل التطبيق بالمشغّل الأصلي — بدون متصفح.',
    },
    {
      'q': 'سيرفر لا يعمل — ماذا أفعل؟',
      'a': 'قد تتوقف سيرفرات البث أحيانًا. انتقل إلى سيرفر آخر من المشغّل أو جرّب مسارًا صوتيًا مختلفًا (مترجم أو مدبلج). ينتقل المشغّل تلقائيًا إلى سيرفر بديل.',
    },
    {
      'q': 'من أين تأتي مواعيد العرض؟',
      'a': 'يُحمَّل تقويم العرض من الجدول الرسمي ويعرض المواعيد الدقيقة لكل حلقة، فتظهر الحلقات الجديدة فور صدورها.',
    },
    {
      'q': 'ما هو قسم أكوام؟',
      'a': 'قسم أكوام هو الصفحة الرئيسية: أفلام ومسلسلات وبرامج عربية وأجنبية من akwam.ss. التشغيل مباشر داخل التطبيق — اختر الجودة واضغط تشغيل، ويمكنك تحميل أي حلقة أو فيلم.',
    },
  ];
}
