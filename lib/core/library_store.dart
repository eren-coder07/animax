import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Library status buckets ("My List").
enum LibStatus { plan, watching, done, hold, drop }

extension LibStatusX on LibStatus {
  String get key => switch (this) {
        LibStatus.plan => 'plan',
        LibStatus.watching => 'watching',
        LibStatus.done => 'done',
        LibStatus.hold => 'hold',
        LibStatus.drop => 'drop',
      };
  String get label => switch (this) {
        LibStatus.plan => 'سأشاهده',
        LibStatus.watching => 'أشاهده',
        LibStatus.done => 'مكتمل',
        LibStatus.hold => 'مؤجّل',
        LibStatus.drop => 'متوقف',
      };
}

/// One tracked item: an anime, a cinema title or a manga.
class LibEntry {
  LibEntry({
    required this.key,
    required this.title,
    required this.poster,
    required this.kind,
    this.status,
    this.rating = 0,
    DateTime? addedAt,
    DateTime? updatedAt,
    this.meta = '',
  })  : addedAt = addedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Stable id: `anime:{id}` · `cinema:{imdb}` · `manga:{uuid}`.
  final String key;
  String title;
  String poster;

  /// `anime` | `cinema` | `cartoon` | `manga`.
  final String kind;
  LibStatus? status;
  int rating; // 0–10, 0 = unrated
  DateTime addedAt;
  DateTime updatedAt;
  String meta; // e.g. "2026 · TV" line under the title

  bool get inList => status != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'title': title,
        'poster': poster,
        'kind': kind,
        'status': status?.key,
        'rating': rating,
        'addedAt': addedAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'meta': meta,
      };

  static LibEntry fromJson(Map<String, dynamic> j) => LibEntry(
        key: (j['key'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        poster: (j['poster'] ?? '').toString(),
        kind: (j['kind'] ?? 'anime').toString(),
        status: _statusOf((j['status'] ?? '').toString()),
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        addedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['addedAt'] as num?)?.toInt() ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['updatedAt'] as num?)?.toInt() ?? 0),
        meta: (j['meta'] ?? '').toString(),
      );

  static LibStatus? _statusOf(String s) {
    for (final LibStatus v in LibStatus.values) {
      if (v.key == s) return v;
    }
    return null;
  }
}

/// Playback / reading progress for one item (anime episode, cinema episode,
/// manga chapter).
class ProgressEntry {
  ProgressEntry({
    required this.key,
    required this.sub,
    this.positionSec = 0,
    this.durationSec = 0,
    this.watched = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String key;
  final String sub; // episode number / chapter id
  int positionSec;
  int durationSec;
  bool watched;
  DateTime updatedAt;

  double get fraction =>
      durationSec > 0 ? (positionSec / durationSec).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'sub': sub,
        'pos': positionSec,
        'dur': durationSec,
        'w': watched,
        'at': updatedAt.millisecondsSinceEpoch,
      };

  static ProgressEntry fromJson(Map<String, dynamic> j) => ProgressEntry(
        key: (j['key'] ?? '').toString(),
        sub: (j['sub'] ?? '').toString(),
        positionSec: (j['pos'] as num?)?.toInt() ?? 0,
        durationSec: (j['dur'] as num?)?.toInt() ?? 0,
        watched: j['w'] == true,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['at'] as num?)?.toInt() ?? 0),
      );
}

/// One "recently watched" history row.
class HistoryRow {
  HistoryRow({
    required this.key,
    required this.title,
    required this.poster,
    required this.kind,
    required this.sub,
    required this.label,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String key;
  final String title;
  final String poster;
  final String kind;
  final String sub;
  final String label; // "Episode 5" / "Ch. 123" / "Movie"
  DateTime at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'title': title,
        'poster': poster,
        'kind': kind,
        'sub': sub,
        'label': label,
        'at': at.millisecondsSinceEpoch,
      };

  static HistoryRow fromJson(Map<String, dynamic> j) => HistoryRow(
        key: (j['key'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        poster: (j['poster'] ?? '').toString(),
        kind: (j['kind'] ?? 'anime').toString(),
        sub: (j['sub'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        at: DateTime.fromMillisecondsSinceEpoch(
            (j['at'] as num?)?.toInt() ?? 0),
      );
}

/// The personal data layer: My List, ratings, watch/reading progress and
/// history. Everything persists to SharedPreferences as JSON and notifies
/// listeners so open screens refresh instantly.
class LibraryStore extends ChangeNotifier {
  LibraryStore._();
  static final LibraryStore I = LibraryStore._();

  /// A separate instance reading the same storage (tests: "app restart").
  @visibleForTesting
  static LibraryStore debugFresh() => LibraryStore._();

  final Map<String, LibEntry> _entries = <String, LibEntry>{};
  final Map<String, ProgressEntry> _progress = <String, ProgressEntry>{};
  final List<HistoryRow> _history = <HistoryRow>[];

  /// Removed list entries (key → epoch ms) so a removal syncs too.
  final Map<String, int> _removed = <String, int>{};
  SharedPreferences? _sp;
  bool _loaded = false;
  final Completer<void> _completer = Completer<void>();
  Future<void> get ready => _completer.future;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      _sp = sp;
      // Each section loads on its own: one bad section never wipes the rest.
      try {
        final List<dynamic> list =
            jsonDecode(sp.getString('lib.entries') ?? '[]') as List<dynamic>;
        for (final dynamic e in list) {
          if (e is Map) {
            final LibEntry entry =
                LibEntry.fromJson(Map<String, dynamic>.from(e));
            if (entry.key.isNotEmpty) _entries[entry.key] = entry;
          }
        }
      } catch (_) {}
      try {
        // Saved as a list of rows (older builds read it as a map, which
        // threw and silently dropped progress *and* history on restart).
        final dynamic prog = jsonDecode(sp.getString('lib.progress') ?? '[]');
        final Iterable<dynamic> rows =
            prog is Map ? prog.values : (prog is List ? prog : const <dynamic>[]);
        for (final dynamic v in rows) {
          if (v is Map) {
            final ProgressEntry p = ProgressEntry.fromJson(Map<String, dynamic>.from(v));
            if (p.key.isNotEmpty) _progress['${p.key}@${p.sub}'] = p;
          }
        }
      } catch (_) {}
      try {
        final List<dynamic> hist =
            jsonDecode(sp.getString('lib.history') ?? '[]') as List<dynamic>;
        for (final dynamic h in hist) {
          if (h is Map) {
            _history.add(HistoryRow.fromJson(Map<String, dynamic>.from(h)));
          }
        }
      } catch (_) {}
      try {
        final dynamic rm = jsonDecode(sp.getString('lib.removed') ?? '{}');
        if (rm is Map) {
          rm.forEach((dynamic k, dynamic v) {
            if (v is num) _removed[k.toString()] = v.toInt();
          });
        }
      } catch (_) {}
    } catch (_) {
      // Corrupt storage → start fresh rather than crash.
    }
    _completer.complete();
    notifyListeners();
  }

  // ------------------------------------------------------------------ list

  List<LibEntry> get allEntries => _entries.values.toList()
    ..sort((LibEntry a, LibEntry b) => b.updatedAt.compareTo(a.updatedAt));

  List<LibEntry> byStatus(LibStatus s) =>
      allEntries.where((LibEntry e) => e.status == s).toList();

  LibEntry? entryOf(String key) => _entries[key];

  bool isListed(String key) => _entries[key]?.inList ?? false;

  /// Adds/updates the list entry for [key] with [status]. Returns the entry.
  LibEntry setListStatus({
    required String key,
    required String title,
    required String poster,
    required String kind,
    required LibStatus status,
    String meta = '',
  }) {
    final LibEntry e = _entries[key] ??
        LibEntry(key: key, title: title, poster: poster, kind: kind);
    e.status = status;
    e.title = title;
    e.poster = poster;
    e.updatedAt = DateTime.now();
    if (meta.isNotEmpty) e.meta = meta;
    _entries[key] = e;
    _removed.remove(key);
    _persist();
    return e;
  }

  void removeListEntry(String key) {
    final LibEntry? e = _entries.remove(key);
    _removed[key] = DateTime.now().millisecondsSinceEpoch;
    if (e != null) {
      e.status = null;
      _persist();
    }
  }

  void rate(String key, int rating) {
    final LibEntry? e = _entries[key];
    if (e == null) return;
    e.rating = rating.clamp(0, 10);
    e.updatedAt = DateTime.now();
    _persist();
  }

  int ratingOf(String key) => _entries[key]?.rating ?? 0;

  // -------------------------------------------------------------- progress

  ProgressEntry? progressOf(String key, String sub) => _progress['$key@$sub'];

  /// Every stored progress row (spoiler shield).
  Iterable<ProgressEntry> get allProgress => _progress.values;

  ProgressEntry progressForItem(String key) {
    // Latest progress row of any sub for this item.
    ProgressEntry? best;
    _progress.forEach((String k, ProgressEntry p) {
      if (p.key == key && (best == null || p.updatedAt.isAfter(best!.updatedAt))) {
        best = p;
      }
    });
    return best ?? ProgressEntry(key: key, sub: '');
  }

  void saveProgress({
    required String key,
    required String sub,
    required int positionSec,
    int durationSec = 0,
    bool watched = false,
  }) {
    _progress['$key@$sub'] = ProgressEntry(
      key: key,
      sub: sub,
      positionSec: positionSec,
      durationSec: durationSec,
      watched: watched,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void markWatched(String key, String sub, {required bool watched}) {
    final ProgressEntry p =
        _progress['$key@$sub'] ?? ProgressEntry(key: key, sub: sub);
    p.watched = watched;
    p.updatedAt = DateTime.now();
    _progress['$key@$sub'] = p;
    _persist();
  }

  bool isWatched(String key, String sub) =>
      _progress['$key@$sub']?.watched ?? false;

  // --------------------------------------------------------------- history

  List<HistoryRow> get history => List<HistoryRow>.unmodifiable(_history);

  void pushHistory({
    required String key,
    required String title,
    required String poster,
    required String kind,
    required String sub,
    required String label,
  }) {
    _history.removeWhere((HistoryRow r) => r.key == key && r.sub == sub);
    _history.insert(
        0,
        HistoryRow(
            key: key,
            title: title,
            poster: poster,
            kind: kind,
            sub: sub,
            label: label));
    if (_history.length > 60) _history.removeRange(60, _history.length);
    _persist();
  }

  void clearHistory() {
    _history.clear();
    _persist();
  }

  // ----------------------------------------------------------------- stats

  /// Simple profile statistics derived from stored data.
  ({
    int episodesWatched,
    int chaptersRead,
    int titlesTracked,
    double hoursWatched,
    int activeDays,
  }) stats() {
    int eps = 0;
    int chapters = 0;
    final Set<String> days = <String>{};
    double seconds = 0;
    _progress.forEach((String _, ProgressEntry p) {
      if (p.watched || p.fraction > 0.9) {
        if (p.key.startsWith('manga:')) {
          chapters++;
        } else {
          eps++;
        }
      }
      seconds += p.positionSec;
      final DateTime d = p.updatedAt;
      days.add('${d.year}-${d.month}-${d.day}');
    });
    for (final HistoryRow r in _history) {
      final DateTime d = r.at;
      days.add('${d.year}-${d.month}-${d.day}');
    }
    return (
      episodesWatched: eps,
      chaptersRead: chapters,
      titlesTracked: _entries.values.where((LibEntry e) => e.inList).length,
      hoursWatched: seconds / 3600.0,
      activeDays: days.length,
    );
  }

  // -------------------------------------------------------------- storage

  /// Export snapshot (used by Settings → Export library).
  Map<String, dynamic> exportJson() => <String, dynamic>{
        'entries': _entries.values
            .map((LibEntry e) => e.toJson())
            .toList(growable: false),
        'progress': _progress.values
            .map((ProgressEntry p) => p.toJson())
            .toList(growable: false),
        'history':
            _history.map((HistoryRow h) => h.toJson()).toList(growable: false),
        'removed': Map<String, int>.of(_removed),
      };

  /// Merges a snapshot from another device (cloud sync): the newest change
  /// of each item wins; removals propagate. Returns true when anything
  /// changed locally.
  bool mergeJson(Map<String, dynamic> data) {
    bool changed = false;
    final Map<dynamic, dynamic> rm =
        (data['removed'] as Map<dynamic, dynamic>?) ?? const <dynamic, dynamic>{};
    rm.forEach((dynamic k, dynamic v) {
      final String key = k.toString();
      final int t = (v as num?)?.toInt() ?? 0;
      final LibEntry? local = _entries[key];
      if (t > (_removed[key] ?? 0) &&
          (local == null || t > local.updatedAt.millisecondsSinceEpoch)) {
        _removed[key] = t;
        if (_entries.remove(key) != null) changed = true;
      }
    });
    for (final dynamic e in (data['entries'] as List<dynamic>?) ?? const <dynamic>[]) {
      if (e is! Map) continue;
      final LibEntry r = LibEntry.fromJson(Map<String, dynamic>.from(e));
      if (r.key.isEmpty) continue;
      if ((_removed[r.key] ?? 0) >= r.updatedAt.millisecondsSinceEpoch) continue;
      final LibEntry? l = _entries[r.key];
      if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
        _entries[r.key] = r;
        changed = true;
      }
    }
    for (final dynamic p in (data['progress'] as List<dynamic>?) ?? const <dynamic>[]) {
      if (p is! Map) continue;
      final ProgressEntry r = ProgressEntry.fromJson(Map<String, dynamic>.from(p));
      if (r.key.isEmpty) continue;
      final String k = '${r.key}@${r.sub}';
      final ProgressEntry? l = _progress[k];
      if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
        _progress[k] = r;
        changed = true;
      }
    }
    for (final dynamic h in (data['history'] as List<dynamic>?) ?? const <dynamic>[]) {
      if (h is! Map) continue;
      final HistoryRow r = HistoryRow.fromJson(Map<String, dynamic>.from(h));
      if (r.key.isEmpty) continue;
      final int i = _history.indexWhere((HistoryRow x) => x.key == r.key && x.sub == r.sub);
      if (i < 0) {
        _history.add(r);
        changed = true;
      } else if (r.at.isAfter(_history[i].at)) {
        _history[i] = r;
        changed = true;
      }
    }
    if (changed) {
      _history.sort((HistoryRow a, HistoryRow b) => b.at.compareTo(a.at));
      if (_history.length > 60) _history.removeRange(60, _history.length);
      _persist();
    }
    return changed;
  }

  /// Import a snapshot produced by [exportJson]. Merges by key.
  void importJson(Map<String, dynamic> data) {
    final List<dynamic> list = (data['entries'] as List<dynamic>?) ?? const <dynamic>[];
    for (final dynamic e in list) {
      if (e is Map) {
        final LibEntry entry = LibEntry.fromJson(Map<String, dynamic>.from(e));
        if (entry.key.isNotEmpty) _entries[entry.key] = entry;
      }
    }
    final List<dynamic> prog = (data['progress'] as List<dynamic>?) ?? const <dynamic>[];
    for (final dynamic p in prog) {
      if (p is Map) {
        final ProgressEntry pe =
            ProgressEntry.fromJson(Map<String, dynamic>.from(p));
        if (pe.key.isNotEmpty) _progress['${pe.key}@${pe.sub}'] = pe;
      }
    }
    final List<dynamic> hist = (data['history'] as List<dynamic>?) ?? const <dynamic>[];
    for (final dynamic h in hist) {
      if (h is Map) _history.add(HistoryRow.fromJson(Map<String, dynamic>.from(h)));
    }
    _persist();
  }

  void _persist() {
    final SharedPreferences? sp = _sp;
    if (sp == null) return;
    sp.setString(
        'lib.entries',
        jsonEncode(
            _entries.values.map((LibEntry e) => e.toJson()).toList()));
    sp.setString(
        'lib.progress',
        jsonEncode(_progress.values
            .map((ProgressEntry p) => p.toJson())
            .toList()));
    sp.setString('lib.history',
        jsonEncode(_history.map((HistoryRow h) => h.toJson()).toList()));
    sp.setString('lib.removed', jsonEncode(_removed));
    notifyListeners();
  }
}
