import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_html.dart' show scheduleTime24h, watchIdOf;
import 'api_service.dart';
import 'app_data.dart';

/// Where the app's content currently comes from.
enum BackendMode {
  /// Fetching from the configured backend right now.
  loading,

  /// Content fetched from the configured backend.
  connected,

  /// A backend was configured but the last fetch failed.
  offline,
}

/// Tiny observable app state (setState-friendly, no state-management package).
/// Screens rebuild via [ListenableBuilder] on [AppState.I].
///
/// [AppState] is also the data repository: screens read the catalog /
/// calendar / notices / episodes from here — never straight from static data.
/// The app is API-pure: everything shown comes from the backend, and there is
/// no built-in sample content of any kind.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  // =========================================================================
  // Backend / repository
  // =========================================================================

  BackendMode backendMode = BackendMode.loading;

  /// Neutral, user-facing status line (no URLs, no raw errors — diagnostics
  /// stay out of the UI on purpose).
  String backendMessage = 'جارٍ التحميل…';

  /// Human-readable reason of the last failed sync (splash / home banner).
  String? syncError;

  DateTime? lastSyncAt;

  List<Anime> _catalog = const <Anime>[];
  Map<String, List<CalendarEntry>> _calendar = <String, List<CalendarEntry>>{};
  List<Notice> _notices = const <Notice>[];

  /// True once the real `/ajax/schedule/date` calendar has been loaded.
  bool _scheduleLive = false;

  /// Episode lists fetched from the backend, keyed by anime id.
  final Map<String, List<Episode>> _episodes = <String, List<Episode>>{};

  /// "More like this" lists, keyed by anime id.
  final Map<String, List<Anime>> _recommendations = <String, List<Anime>>{};

  /// Watch-page details already merged, keyed by anime id.
  final Set<String> _detailed = <String>{};

  /// Full catalog from the backend (empty until the first successful sync).
  List<Anime> get catalog => _catalog;

  /// Release calendar keyed by `yyyy-MM-dd` (from `/ajax/schedule/date`).
  Map<String, List<CalendarEntry>> get calendar => _calendar;

  /// Calendar rows for one date.
  List<CalendarEntry> entriesFor(DateTime date) =>
      calendar[_dayKey(date)] ?? const <CalendarEntry>[];

  /// True when the calendar comes from the backend's own schedule endpoint.
  bool get scheduleLive => _scheduleLive;

  /// Notification rows.
  List<Notice> get notices => _notices;

  bool get isConnected => backendMode == BackendMode.connected;
  bool get isLoading => backendMode == BackendMode.loading;

  /// True when the in-app base URL is set (may still be unreachable).
  bool get backendConfigured => ApiService.I.config.isConfigured;

  /// Short chip label for Home / Profile ("LIVE", "SYNC…", "OFFLINE").
  String get backendChip {
    switch (backendMode) {
      case BackendMode.loading:
        return 'مزامنة…';
      case BackendMode.connected:
        return 'مباشر';
      case BackendMode.offline:
        return 'غير متصل';
    }
  }

  /// Home — Top Hits ranked cards (trending ranks first).
  List<Anime> get topHits => _catalog.take(3).toList();

  /// Home — New Episode Releases.
  List<Anime> get newEpisodes =>
      _catalog.length > 3 ? _catalog.skip(3).take(7).toList() : const <Anime>[];

  Anime byId(String id) => _catalog.firstWhere(
      (Anime a) => a.id == id,
      orElse: () => _catalog.isNotEmpty
          ? _catalog.first
          : const Anime(
              id: '',
              title: '',
              poster: '',
              score: 0,
              year: '',
              genres: <String>[],
              synopsis: ''));

  /// Details — "More Like This" (synchronous fallback from the catalog).
  List<Anime> moreLike(String id) =>
      _catalog.where((Anime a) => a.id != id).take(6).toList();

  /// Details — "More Like This" with backend recommendations when available.
  Future<List<Anime>> moreLikeAsync(Anime anime) async {
    final String key = anime.id;
    if (_recommendations.containsKey(key)) return _recommendations[key]!;
    if (!anime.isRemote) return moreLike(anime.id);
    final String? wid = anime.watchId;
    if (wid == null) return moreLike(anime.id);
    try {
      final List<Anime> recs = await ApiService.I.fetchRecommendations(wid);
      _recommendations[key] =
          recs.isNotEmpty ? recs.take(8).toList() : moreLike(anime.id);
    } on ApiException {
      _recommendations[key] = moreLike(anime.id);
    } catch (_) {
      _recommendations[key] = moreLike(anime.id);
    }
    notifyListeners();
    return _recommendations[key]!;
  }

  // =========================================================================
  // Bootstrap / refresh
  // =========================================================================

  /// Loads persisted config, then syncs everything the app needs from the
  /// backend: catalog first, then the release schedule + notifications.
  ///
  /// Called by the splash screen, which waits for it and shows progress.
  /// Returns true when the backend was reached (catalog loaded). Never throws.
  Future<bool> bootstrap() async {
    await ApiService.I.loadConfig();
    return refreshFromApi(withSchedule: true);
  }

  /// Fetches the catalog from the backend. When [withSchedule] is set, the
  /// release calendar and notifications are loaded before this returns, so
  /// every screen has its data ready right after the splash sync.
  /// Never throws — check [backendMode] / [syncError] for the outcome.
  Future<bool> refreshFromApi({bool withSchedule = false}) async {
    if (!ApiService.I.config.isConfigured) {
      backendMode = BackendMode.offline;
      backendMessage = 'المحتوى غير متاح';
      syncError = null;
      notifyListeners();
      return false;
    }
    backendMode = BackendMode.loading;
    backendMessage = 'جارٍ تحميل المحتوى…';
    syncError = null;
    notifyListeners();

    bool ok = false;
    try {
      final List<Anime> remote = await ApiService.I.fetchCatalog();
      _catalog = remote;
      backendMode = BackendMode.connected;
      backendMessage = 'مكتبة المحتوى محدّثة';
      syncError = null;
      lastSyncAt = DateTime.now();
      ok = true;
      notifyListeners();
    } catch (_) {
      backendMode = BackendMode.offline;
      backendMessage = 'المحتوى غير متاح — تحقّق من اتصالك';
      syncError = null;
      notifyListeners();
      return false;
    }

    if (withSchedule) {
      // Splash sync: also wait for the schedule so Calendar/Notifications are
      // populated before the first frame of the shell.
      try {
        await loadSchedule().timeout(const Duration(seconds: 25));
      } catch (_) {
        // Calendar is best-effort; the catalog is already usable.
      }
    } else {
      unawaited(loadSchedule());
    }
    return ok;
  }

  static String _dayKey(DateTime d) {
    final String mm = d.month.toString().padLeft(2, '0');
    final String dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Loads the release calendar from the backend's own schedule endpoint
  /// (`/ajax/schedule/date`) for the window today‑3 … today+7.
  /// Falls back to deriving air dates from episode lists when the endpoint
  /// is unavailable. Best-effort: never throws.
  Future<void> loadSchedule() async {
    final DateTime now = DateTime.now();
    final Map<String, List<CalendarEntry>> cal = <String, List<CalendarEntry>>{};
    final List<Notice> fresh = <Notice>[];
    bool any = false;

    Future<void> one(DateTime day) async {
      try {
        final List<ScheduleItem> items = await ApiService.I.fetchSchedule(day);
        if (items.isEmpty) return;
        any = true;
        final List<CalendarEntry> rows = <CalendarEntry>[];
        for (final ScheduleItem it in items) {
          final Anime a = _scheduleAnime(it);
          rows.add(CalendarEntry(scheduleTime24h(it.time), a, it.episode));
          // Notifications: episodes that dropped within the last 3 days.
          final int dayDiff = DateTime(day.year, day.month, day.day)
              .difference(DateTime(now.year, now.month, now.day))
              .inDays;
          if (dayDiff <= 0 && dayDiff >= -3) {
            fresh.add(Notice(
                a,
                it.episode,
                dayDiff == 0
                    ? 'اليوم'
                    : 'منذ ${-dayDiff} ${dayDiff == -1 ? 'يوم' : 'أيام'}'));
          }
        }
        rows.sort((CalendarEntry x, CalendarEntry y) => x.time.compareTo(y.time));
        cal[_dayKey(day)] = rows;
      } on ApiException {
        // Single-day failure is skipped.
      } catch (_) {
        // Never break bootstrap over the calendar.
      }
    }

    await Future.wait(<Future<void>>[
      for (int i = -3; i <= 7; i++)
        one(DateTime(now.year, now.month, now.day + i)),
    ]);

    if (any && cal.isNotEmpty) {
      _calendar = cal;
      _scheduleLive = true;
      if (fresh.isNotEmpty) {
        _notices = fresh;
      }
      notifyListeners();
      return;
    }
    // Schedule endpoint unavailable → derive from episode air dates.
    await _deriveCalendarFallback();
  }

  /// Builds/looks up an [Anime] for a schedule row: poster and metadata come
  /// from the loaded catalog when the title is already known.
  Anime _scheduleAnime(ScheduleItem it) {
    final String? wid = watchIdOf(it.slug);
    for (final Anime a in _catalog) {
      if (a.watchId == wid) return a;
    }
    return Anime(
      id: it.slug,
      title: it.title,
      poster: '',
      score: 0,
      year: '',
      genres: const <String>[],
      synopsis: '',
      slug: it.slug,
      isRemote: true,
    );
  }

  /// Fetches episode lists for the top titles and derives:
  ///  * the release calendar from real air dates,
  ///  * notifications for episodes released in the last 3 days.
  /// Best-effort fallback used when `/ajax/schedule/date` is unavailable.
  Future<void> _deriveCalendarFallback({int limit = 8}) async {
    final List<Anime> targets = _catalog.take(limit).toList();
    final Map<String, List<CalendarEntry>> cal = <String, List<CalendarEntry>>{};
    final List<Notice> fresh = <Notice>[];
    final DateTime now = DateTime.now();

    for (final Anime a in targets) {
      final List<Episode>? eps = await _fetchEpisodesFor(a);
      if (eps == null) continue;
      for (final Episode ep in eps) {
        final DateTime? aired = _parseAired(ep.aired);
        if (aired == null) continue;
        final int dayDiff =
            DateTime(aired.year, aired.month, aired.day)
                .difference(DateTime(now.year, now.month, now.day))
                .inDays;
        // Calendar: today … +12 days.
        if (dayDiff >= 0 && dayDiff <= 12) {
          final String key =
              _dayKey(DateTime(aired.year, aired.month, aired.day));
          (cal[key] ??= <CalendarEntry>[]).add(CalendarEntry(
              _hhmm(aired), a, ep.number));
        }
        // Notifications: released within the last 3 days.
        if (dayDiff <= 0 && dayDiff >= -3) {
          fresh.add(Notice(a, ep.number, _relativeAgo(now, aired)));
        }
      }
    }

    if (cal.isNotEmpty) {
      for (final List<CalendarEntry> l in cal.values) {
        l.sort((CalendarEntry x, CalendarEntry y) => x.time.compareTo(y.time));
      }
      _calendar = cal;
      _scheduleLive = false;
    }
    if (fresh.isNotEmpty) {
      fresh.sort((Notice x, Notice y) => x.when.compareTo(y.when));
      _notices = fresh;
    }
    notifyListeners();
  }

  /// Fetches and merges watch-page details (synopsis, genres, score) for an
  /// anime. Returns the enriched anime (or the original on failure).
  Future<Anime> loadDetails(Anime anime) async {
    if (!anime.isRemote || _detailed.contains(anime.id)) {
      return anime;
    }
    try {
      final Anime rich = await ApiService.I.fetchDetails(anime);
      _detailed.add(anime.id);
      final int i = _catalog.indexWhere((Anime x) => x.id == anime.id);
      if (i >= 0) _catalog[i] = rich;
      notifyListeners();
      return rich;
    } catch (_) {
      return anime;
    }
  }

  /// Episodes for the details screen — cached after the first fetch.
  /// Returns an empty list when the backend is unreachable.
  Future<List<Episode>> episodesFor(Anime anime) async {
    if (!anime.isRemote) return const <Episode>[];
    final List<Episode>? cached = _episodes[anime.id];
    if (cached != null) return cached;
    final List<Episode>? fresh = await _fetchEpisodesFor(anime);
    return fresh ?? const <Episode>[];
  }

  Future<List<Episode>?> _fetchEpisodesFor(Anime anime) async {
    if (_episodes.containsKey(anime.id)) return _episodes[anime.id];
    final String? wid = anime.watchId;
    if (wid == null) return null;
    try {
      final List<Episode> eps = await ApiService.I.fetchEpisodes(wid);
      _episodes[anime.id] = eps;
      // Keep episodeCount fresh for the details header.
      if (eps.length > anime.episodeCount) {
        final int i = _catalog.indexWhere((Anime x) => x.id == anime.id);
        if (i >= 0) {
          _catalog[i] = _withEpisodeCount(_catalog[i], eps.length);
        }
      }
      return eps;
    } on ApiException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Anime _withEpisodeCount(Anime a, int n) => Anime(
        id: a.id,
        title: a.title,
        poster: a.poster,
        score: a.score,
        year: a.year,
        genres: a.genres,
        synopsis: a.synopsis,
        episodeCount: n,
        ageRating: a.ageRating,
        isMovie: a.isMovie,
        duration: a.duration,
        slug: a.slug,
        isRemote: a.isRemote,
        type: a.type,
        status: a.status,
        studio: a.studio,
      );

  static DateTime? _parseAired(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    DateTime? dt = DateTime.tryParse(raw);
    if (dt != null) return dt.toLocal();
    // "2026-10-06 15:00:00"
    final RegExpMatch? m = RegExp(
      r'(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})',
    ).firstMatch(raw);
    if (m != null) {
      return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
          int.parse(m.group(3)!), int.parse(m.group(4)!), int.parse(m.group(5)!));
    }
    return null;
  }

  static String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  static String _relativeAgo(DateTime now, DateTime aired) {
    final Duration diff = now.difference(aired);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays == 1) return 'أمس';
    if (diff.inDays < 30) return 'منذ ${diff.inDays} يوم';
    return _hhmm(aired);
  }

  // =========================================================================
  // Shell
  // =========================================================================

  /// Bottom tabs: 0 الرئيسية · 1 التحميلات · 2 حسابي.
  static const int homeTab = 0;

  int navIndex = homeTab;

  /// Selected category on Home (0 = Akwam feed).
  int homeCategory = 0;

  void setCategory(int index) {
    homeCategory = index;
    navIndex = homeTab;
    notifyListeners();
  }

  void setTab(int index) {
    navIndex = index;
    notifyListeners();
  }

  // =========================================================================
  // Calendar selection
  // =========================================================================

  DateTime selectedDate = DateTime.now();

  void selectDate(DateTime d) {
    selectedDate = d;
    notifyListeners();
  }

  // =========================================================================
  // Onboarding genres
  // =========================================================================

  final Set<String> pickedGenres = <String>{'أكشن', 'شونين'};

  void toggleGenre(String g) {
    pickedGenres.contains(g) ? pickedGenres.remove(g) : pickedGenres.add(g);
    notifyListeners();
  }
}
