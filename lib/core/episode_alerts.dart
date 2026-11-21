import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'akwam_api.dart';
import 'library_store.dart';

/// "New episode" of an Akwam series you keep in My List.
class EpisodeAlert {
  const EpisodeAlert({
    required this.key,
    required this.title,
    required this.poster,
    required this.episode,
    required this.at,
  });
  final String key; // akwam:/series/…
  final String title;
  final String poster;
  final int episode;
  final DateTime at;

  String get path => key.startsWith('akwam:') ? key.substring(6) : key;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'title': title,
    'poster': poster,
    'ep': episode,
    'at': at.millisecondsSinceEpoch,
  };

  static EpisodeAlert fromJson(Map<String, dynamic> j) => EpisodeAlert(
    key: (j['key'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    poster: (j['poster'] ?? '').toString(),
    episode: (j['ep'] as num?)?.toInt() ?? 0,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );
}

/// Checks the Akwam series in My List for new episodes (at launch, then
/// every 6 hours while the app is open) and lists them in Notifications.
class EpisodeAlerts extends ChangeNotifier {
  EpisodeAlerts._();
  static final EpisodeAlerts I = EpisodeAlerts._();

  static const String _prefKey = 'alerts.akwam';
  static const int maxSeries = 12;

  List<EpisodeAlert> alerts = <EpisodeAlert>[];
  final Map<String, int> _counts = <String, int>{};
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loaded = false;
  bool checking = false;
  Timer? _timer;

  Future<void> start() async {
    await _load();
    unawaited(Future<void>.delayed(const Duration(seconds: 20), check));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check());
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? raw = sp.getString(_prefKey);
      if (raw == null) return;
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      (j['counts'] as Map<String, dynamic>? ?? <String, dynamic>{}).forEach(
        (String k, dynamic v) => _counts[k] = (v as num).toInt(),
      );
      alerts = <EpisodeAlert>[
        for (final dynamic a in (j['alerts'] as List<dynamic>? ?? <dynamic>[]))
          if (a is Map) EpisodeAlert.fromJson(Map<String, dynamic>.from(a)),
      ];
      _lastCheck = DateTime.fromMillisecondsSinceEpoch(
        (j['last'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(
        _prefKey,
        jsonEncode(<String, dynamic>{
          'counts': _counts,
          'alerts': alerts.map((EpisodeAlert a) => a.toJson()).toList(),
          'last': _lastCheck.millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  /// Series keys in My List worth checking (Akwam series / shows).
  static List<LibEntry> watched(Iterable<LibEntry> entries) => entries
      .where(
        (LibEntry e) =>
            e.inList &&
            e.key.startsWith('akwam:') &&
            (e.key.contains('/series/') || e.key.contains('/show/')),
      )
      .take(maxSeries)
      .toList();

  /// Pure step (unit-tested): the newest episode seen now vs. the stored
  /// count. Returns the new count and the alert to add (if any). The first
  /// sighting only records a baseline.
  static ({int count, EpisodeAlert? alert}) compare(
    LibEntry e,
    int? previous,
    int latest,
    DateTime now,
  ) {
    if (latest <= 0) return (count: previous ?? 0, alert: null);
    if (previous == null || latest <= previous) {
      return (count: previous == null ? latest : previous, alert: null);
    }
    return (
      count: latest,
      alert: EpisodeAlert(
        key: e.key,
        title: e.title,
        poster: e.poster,
        episode: latest,
        at: now,
      ),
    );
  }

  Future<void> check({bool force = false}) async {
    await _load();
    if (checking) return;
    if (!force && DateTime.now().difference(_lastCheck).inHours < 6) return;
    checking = true;
    notifyListeners();
    try {
      await LibraryStore.I.ready;
      for (final LibEntry e in watched(LibraryStore.I.allEntries)) {
        final AkwamItem? item = AkwamApi.itemFromPath(
          e.key.substring(6),
          title: e.title,
          poster: e.poster,
        );
        if (item == null) continue;
        int latest = 0;
        try {
          final AkwamItem rich = await AkwamApi.I.details(item);
          for (final AkwamEpisode ep in rich.episodes) {
            if (ep.number > latest) latest = ep.number;
          }
        } catch (_) {
          continue; // try again next round
        }
        final ({int count, EpisodeAlert? alert}) r = compare(
          e,
          _counts[e.key],
          latest,
          DateTime.now(),
        );
        _counts[e.key] = r.count;
        if (r.alert != null) {
          alerts = <EpisodeAlert>[
            r.alert!,
            ...alerts.where((EpisodeAlert a) => a.key != e.key),
          ];
        }
      }
      _lastCheck = DateTime.now();
      await _save();
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  void dismiss(EpisodeAlert a) {
    alerts = alerts.where((EpisodeAlert x) => x.key != a.key).toList();
    notifyListeners();
    unawaited(_save());
  }

  void clear() {
    alerts = <EpisodeAlert>[];
    notifyListeners();
    unawaited(_save());
  }
}
