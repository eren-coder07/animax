import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'akwam_api.dart';
import 'api_service.dart';
import 'app_http.dart';
import 'hh_api.dart';
import 'hls_download.dart';
import 'manga_api.dart';
import 'stream_resolver.dart';

/// What a download produces.
enum DownloadKind { video, comic }

enum DownloadStatus { queued, running, paused, done, failed }

/// One entry in the Downloads list (persisted as JSON).
class DownloadItem {
  DownloadItem({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.poster = '',
    this.url = '',
    this.headers = const <String, String>{},
    this.isHls = false,
    this.chapterId = '',
    this.source = 'url',
    this.ref = const <String, String>{},
    String key = '',
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.received = 0,
    this.total = 0,
    this.error = '',
    this.resultUri = '',
    this.resultLocation = '',
    this.mime = '',
    this.extraUri = '',
    Map<String, List<int>>? resume,
    DateTime? createdAt,
  })  : resume = resume ?? <String, List<int>>{},
        createdAt = createdAt ?? DateTime.now(),
        key = key.isNotEmpty ? key : (url.isNotEmpty ? url : chapterId);

  final String id;
  final DownloadKind kind;
  final String title;
  final String subtitle;
  final String poster;

  /// Video: direct MP4 or HLS playlist URL. Empty until resolved for
  /// downloads queued from a details page ([source] != `url`).
  String url;
  Map<String, String> headers;
  bool isHls;

  /// Where [url] comes from: `url` (given directly), `akwam` (watch/item
  /// page), `anime` (Aniwaves episode) or `hh` (18+ episode). Resolved
  /// right before the download starts, so stream links never go stale.
  final String source;
  final Map<String, String> ref;

  /// Stable identity used to avoid duplicate downloads.
  final String key;

  /// Comic: MangaDex chapter id (page URLs expire, so they are fetched when
  /// the download actually runs).
  final String chapterId;

  DownloadStatus status;
  double progress;
  int received;
  int total;
  String error;

  /// `content://` URI (or file path) of the finished file.
  String resultUri;

  /// Human-readable location, e.g. `Download/Animax/Videos/x.mp4`.
  String resultLocation;
  String mime;

  /// Separate audio file when muxing was impossible (rare).
  String extraUri;

  /// HLS resume state: track → [segments done, bytes written].
  final Map<String, List<int>> resume;
  final DateTime createdAt;

  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.running;

  String get fileBase => sanitizeFileName(
      subtitle.isEmpty ? title : '$title - $subtitle');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'title': title,
        'subtitle': subtitle,
        'poster': poster,
        'url': url,
        'headers': headers,
        'isHls': isHls,
        'chapterId': chapterId,
        'source': source,
        'ref': ref,
        'key': key,
        'status': status.name,
        'progress': progress,
        'received': received,
        'total': total,
        'error': error,
        'resultUri': resultUri,
        'resultLocation': resultLocation,
        'mime': mime,
        'extraUri': extraUri,
        'resume': resume,
        'createdAt': createdAt.toIso8601String(),
      };

  static DownloadItem fromJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> values, String? name, T fallback) {
      for (final T v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    final Map<String, List<int>> resume = <String, List<int>>{};
    final dynamic r = j['resume'];
    if (r is Map) {
      r.forEach((dynamic k, dynamic v) {
        if (v is List) {
          resume[k.toString()] =
              v.map((dynamic e) => (e as num).toInt()).toList();
        }
      });
    }
    return DownloadItem(
      id: (j['id'] ?? '').toString(),
      kind: pick(DownloadKind.values, j['kind'] as String?, DownloadKind.video),
      title: (j['title'] ?? '').toString(),
      subtitle: (j['subtitle'] ?? '').toString(),
      poster: (j['poster'] ?? '').toString(),
      url: (j['url'] ?? '').toString(),
      headers: (j['headers'] is Map)
          ? Map<String, String>.from((j['headers'] as Map).map(
              (dynamic k, dynamic v) => MapEntry(k.toString(), v.toString())))
          : const <String, String>{},
      isHls: j['isHls'] == true,
      chapterId: (j['chapterId'] ?? '').toString(),
      source: (j['source'] ?? 'url').toString(),
      ref: (j['ref'] is Map)
          ? Map<String, String>.from((j['ref'] as Map).map(
              (dynamic k, dynamic v) => MapEntry(k.toString(), v.toString())))
          : const <String, String>{},
      key: (j['key'] ?? '').toString(),
      status: pick(DownloadStatus.values, j['status'] as String?,
          DownloadStatus.queued),
      progress: (j['progress'] as num?)?.toDouble() ?? 0,
      received: (j['received'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      error: (j['error'] ?? '').toString(),
      resultUri: (j['resultUri'] ?? '').toString(),
      resultLocation: (j['resultLocation'] ?? '').toString(),
      mime: (j['mime'] ?? '').toString(),
      extraUri: (j['extraUri'] ?? '').toString(),
      resume: resume,
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()),
    );
  }
}

/// Windows/Android-safe file name (no path separators or reserved chars).
String sanitizeFileName(String raw) {
  String s = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > 110) s = s.substring(0, 110).trim();
  return s.isEmpty ? 'animax' : s;
}

class _Cancelled implements Exception {}

class DownloadException implements Exception {
  DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// App-wide download queue.
///
/// * Videos: progressive files are streamed with HTTP Range resume; HLS
///   streams are fetched segment by segment (AES-128 decrypted, separate
///   audio renditions included) and remuxed into a single MP4 on-device.
/// * Comics: chapter pages are bundled into one PDF.
///
/// Finished files are published to the public `Download/Animax/…` folder
/// (MediaStore), so they show up in the Files app and any player/reader.
/// One download runs at a time; queued/paused items survive app restarts.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager I = DownloadManager._();

  static const MethodChannel _channel = MethodChannel('animax/app');

  final List<DownloadItem> _items = <DownloadItem>[];
  List<DownloadItem> get items => List<DownloadItem>.unmodifiable(_items);

  int get activeCount => _items.where((DownloadItem d) => d.isActive).length;

  /// Test hook: replaces the list without touching storage or the network.
  @visibleForTesting
  void debugSeed(List<DownloadItem> items) {
    _loaded = true;
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  http.Client? _client;
  http.Client get _http => _client ??= createHttpClient();

  DownloadItem? _running;
  bool _cancelRunning = false;
  bool _loaded = false;
  Timer? _saveDebounce;

  // ---------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------

  Future<File> _stateFile() async {
    final Directory d = await getApplicationSupportDirectory();
    return File('${d.path}/downloads.json');
  }

  Future<Directory> _workDir(String id) async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationSupportDirectory();
    final Directory d = Directory('${base.path}/animax_dl/$id');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final File f = await _stateFile();
      if (f.existsSync()) {
        final dynamic raw = jsonDecode(await f.readAsString());
        if (raw is List) {
          for (final dynamic e in raw) {
            if (e is Map) {
              final DownloadItem it =
                  DownloadItem.fromJson(Map<String, dynamic>.from(e));
              // A download interrupted by the app closing resumes queued.
              if (it.status == DownloadStatus.running) {
                it.status = DownloadStatus.queued;
              }
              _items.add(it);
            }
          }
        }
      }
    } catch (_) {
      // Corrupt state file — start clean.
    }
    notifyListeners();
    unawaited(_pump());
  }

  void _save({bool now = false}) {
    _saveDebounce?.cancel();
    if (now) {
      unawaited(_writeState());
    } else {
      _saveDebounce = Timer(const Duration(seconds: 2), _writeState);
    }
  }

  Future<void> _writeState() async {
    try {
      final File f = await _stateFile();
      await f.writeAsString(jsonEncode(
          _items.map((DownloadItem d) => d.toJson()).toList()));
    } catch (_) {}
  }

  void _changed({bool persist = false}) {
    notifyListeners();
    if (persist) _save(now: true);
  }

  // ---------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------

  /// Existing (non-failed) download of the same source, if any.
  DownloadItem? find({String url = '', String chapterId = '', String key = ''}) {
    for (final DownloadItem d in _items) {
      if (key.isNotEmpty && d.key == key) return d;
      if (d.status == DownloadStatus.failed) continue;
      if (url.isNotEmpty && d.url == url) return d;
      if (chapterId.isNotEmpty && d.chapterId == chapterId) return d;
    }
    return null;
  }

  /// Queues a video whose stream is resolved when the download starts.
  /// [source]: `akwam` (ref: path = watch/movie/episode page), `anime`
  /// (ref: watchId, ep) or `hh` (ref: slug, ep).
  Future<DownloadItem> addResolvable({
    required String source,
    required Map<String, String> ref,
    required String title,
    String subtitle = '',
    String poster = '',
  }) async {
    await load();
    final String key = '$source:${ref.values.join('|')}';
    final DownloadItem? dup = find(key: key);
    if (dup != null) {
      if (dup.status == DownloadStatus.failed) resume(dup);
      return dup;
    }
    final DownloadItem it = DownloadItem(
      id: _newId(),
      kind: DownloadKind.video,
      title: title,
      subtitle: subtitle,
      poster: poster,
      source: source,
      ref: ref,
      key: key,
    );
    return _enqueue(it);
  }

  /// Turns a details-page download into a concrete stream URL + headers.
  Future<void> _resolve(DownloadItem it) async {
    switch (it.source) {
      case 'akwam':
        final String page = it.ref['path'] ?? '';
        String watch = page;
        if (!page.contains('/watch/')) {
          // Movie / episode page → pick the best quality's watch page.
          final List<AkwamSource> sources =
              await AkwamApi.I.sourcesForPath(page);
          if (sources.isEmpty) {
            throw DownloadException('لا توجد جودة قابلة للتحميل لهذا العنوان.');
          }
          watch = bestAkwamSource(sources).watchPath;
        }
        it.url = await AkwamApi.I.resolveStream(watch);
        it.headers = <String, String>{
          'User-Agent': AkwamApi.ua,
          'Referer': '${AkwamApi.base}/',
        };
        it.isHls = it.url.toLowerCase().contains('.m3u8');
        return;
      case 'anime':
        final String wid = it.ref['watchId'] ?? '';
        final String ep = it.ref['ep'] ?? '1';
        final List<EpisodeServer> servers =
            await ApiService.I.fetchServers(wid, ep);
        // Soft/hard subs first, dub last.
        servers.sort((EpisodeServer a, EpisodeServer b) =>
            (a.kind == 'dub' ? 1 : 0) - (b.kind == 'dub' ? 1 : 0));
        for (final EpisodeServer s in servers) {
          _checkCancel();
          final ResolvedStream? rs = await StreamResolver.I.resolve(s);
          if (rs == null) continue;
          it.url = rs.url;
          it.isHls = rs.isHls;
          it.headers = <String, String>{
            if (rs.referer.isNotEmpty) 'Referer': rs.referer,
          };
          return;
        }
        throw DownloadException('لا يوجد سيرفر متاح لتحميل هذه الحلقة حاليًا.');
      case 'hh':
        final HhStream st = await HentaiApi.I.resolveStream(
            it.ref['slug'] ?? '', int.tryParse(it.ref['ep'] ?? '1') ?? 1);
        it.url = st.url;
        it.isHls = st.isHls;
        it.headers = <String, String>{'Referer': '${HentaiApi.frontBase}/'};
        return;
    }
  }

  /// Queues a video. [url] may be a direct file or an HLS playlist.
  Future<DownloadItem> addVideo({
    required String title,
    String subtitle = '',
    String poster = '',
    required String url,
    Map<String, String> headers = const <String, String>{},
    bool? isHls,
  }) async {
    await load();
    final DownloadItem? dup = find(url: url);
    if (dup != null) return dup;
    final DownloadItem it = DownloadItem(
      id: _newId(),
      kind: DownloadKind.video,
      title: title,
      subtitle: subtitle,
      poster: poster,
      url: url,
      headers: headers,
      isHls: isHls ?? url.toLowerCase().contains('.m3u8'),
    );
    return _enqueue(it);
  }

  /// Queues a comic chapter → PDF.
  Future<DownloadItem> addComicChapter({
    required String title,
    required String chapterLabel,
    required String chapterId,
    String poster = '',
  }) async {
    await load();
    final DownloadItem? dup = find(chapterId: chapterId);
    if (dup != null) return dup;
    final DownloadItem it = DownloadItem(
      id: _newId(),
      kind: DownloadKind.comic,
      title: title,
      subtitle: chapterLabel,
      poster: poster,
      chapterId: chapterId,
    );
    return _enqueue(it);
  }

  Future<DownloadItem> _enqueue(DownloadItem it) async {
    await _ensureStorage();
    _items.insert(0, it);
    _changed(persist: true);
    unawaited(_pump());
    return it;
  }

  void pause(DownloadItem it) {
    if (it.status == DownloadStatus.queued) {
      it.status = DownloadStatus.paused;
      _changed(persist: true);
    } else if (it.status == DownloadStatus.running) {
      it.status = DownloadStatus.paused;
      _cancelRunning = true;
      _changed(persist: true);
    }
  }

  void resume(DownloadItem it) {
    if (it.status == DownloadStatus.paused ||
        it.status == DownloadStatus.failed) {
      it.status = DownloadStatus.queued;
      if (it.source != 'url' && it.resume.isEmpty && it.received == 0) {
        it.url = ''; // resolve again
      }
      it.error = '';
      _changed(persist: true);
      unawaited(_pump());
    }
  }

  /// Cancels (if needed) and removes the entry. [deleteFile] also deletes
  /// the finished file from the device.
  Future<void> remove(DownloadItem it, {bool deleteFile = false}) async {
    if (identical(_running, it)) _cancelRunning = true;
    _items.remove(it);
    _changed(persist: true);
    try {
      final Directory d = await _workDir(it.id);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
    if (deleteFile) {
      for (final String u in <String>[it.resultUri, it.extraUri]) {
        if (u.isEmpty) continue;
        try {
          if (u.startsWith('content://')) {
            // Android MediaStore entry.
            await _channel.invokeMethod<bool>('dlDelete', <String, String>{'uri': u});
          } else {
            final File f = File(u);
            if (f.existsSync()) f.deleteSync();
          }
        } catch (_) {}
      }
    }
  }

  /// Free bytes on shared storage (-1 when unknown).
  Future<int> freeSpace() async {
    try {
      return await _channel.invokeMethod<int>('dlFreeSpace') ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// Opens the finished file with the system viewer/player chooser.
  Future<bool> open(DownloadItem it) async {
    if (it.resultUri.isEmpty) return false;
    if (Platform.isWindows) {
      try {
        // Default app for the file type (Movies & TV, VLC, Edge for PDF…).
        await Process.start('cmd', <String>['/c', 'start', '', it.resultUri],
            runInShell: false);
        return true;
      } catch (_) {
        return false;
      }
    }
    try {
      return await _channel.invokeMethod<bool>('dlOpen', <String, String>{
            'uri': it.resultUri,
            'mime': it.mime,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // Worker
  // ---------------------------------------------------------------------

  int _seq = 0;
  String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

  Future<void> _pump() async {
    if (_running != null) return;
    DownloadItem? next;
    for (final DownloadItem d in _items.reversed) {
      // Oldest queued first (list is newest-first).
      if (d.status == DownloadStatus.queued) {
        next = d;
        break;
      }
    }
    if (next == null) return;
    _running = next;
    _cancelRunning = false;
    next.status = DownloadStatus.running;
    next.error = '';
    _changed(persist: true);
    _keepAwake(true);
    try {
      if (next.kind == DownloadKind.video && next.source != 'url' &&
          next.url.isEmpty) {
        // Source pages can be slow or briefly fail: retry with backoff
        // before reporting an error to the user.
        Object? lastErr;
        for (int attempt = 0; attempt < 4; attempt++) {
          _checkCancel();
          try {
            await _resolve(next);
            lastErr = null;
            break;
          } on _Cancelled {
            rethrow;
          } catch (e) {
            lastErr = e;
            await Future<void>.delayed(Duration(seconds: 2 + attempt * 3));
          }
        }
        if (lastErr != null) {
          throw lastErr is DownloadException
              ? lastErr
              : DownloadException(lastErr.toString().isEmpty
                  ? 'تعذّر تجهيز رابط التحميل — حاول لاحقًا.'
                  : 'تعذّر تجهيز رابط التحميل: $lastErr');
        }
        _changed(persist: true);
      }
      if (next.kind == DownloadKind.comic) {
        await _runComic(next);
      } else if (next.isHls) {
        await _runHls(next);
      } else {
        await _runProgressive(next);
      }
      next.status = DownloadStatus.done;
      next.progress = 1;
      try {
        final Directory d = await _workDir(next.id);
        if (d.existsSync()) d.deleteSync(recursive: true);
      } catch (_) {}
    } on _Cancelled {
      // Paused or removed — status already set by the caller.
    } catch (e) {
      if (next.status == DownloadStatus.running) {
        next.status = DownloadStatus.failed;
        next.error = e is DownloadException
            ? e.message
            : 'فشل التحميل — تحقّق من اتصالك وأعد المحاولة.';
      }
    } finally {
      _running = null;
      _changed(persist: true);
      _keepAwake(false);
      unawaited(_pump());
    }
  }

  void _checkCancel() {
    if (_cancelRunning) throw _Cancelled();
  }

  void _keepAwake(bool on) {
    try {
      _channel.invokeMethod<bool>('dlKeepAlive', <String, bool>{'on': on});
    } catch (_) {}
  }

  Map<String, String> _headers(DownloadItem it, [Map<String, String>? extra]) =>
      <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
        ...it.headers,
        ...?extra,
      };

  /// GET with retries for small resources (playlists, keys, segments).
  Future<Uint8List> _getBytes(DownloadItem it, Uri uri,
      {Map<String, String>? extra, int attempts = 4}) async {
    Object? last;
    for (int a = 0; a < attempts; a++) {
      _checkCancel();
      try {
        final http.Response r = await _http
            .get(uri, headers: _headers(it, extra))
            .timeout(const Duration(seconds: 40));
        if (r.statusCode == 200 || r.statusCode == 206) return r.bodyBytes;
        if (r.statusCode == 403 || r.statusCode == 404 || r.statusCode == 410) {
          throw DownloadException(
              'رفض المصدر التحميل (HTTP ${r.statusCode}). '
              'افتح الحلقة مرة أخرى وأعد المحاولة.');
        }
        last = DownloadException('HTTP ${r.statusCode}');
      } on DownloadException {
        rethrow;
      } catch (e) {
        if (e is _Cancelled) rethrow;
        last = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 600 * (a + 1)));
    }
    throw last is DownloadException
        ? last
        : DownloadException('خطأ في الشبكة أثناء التحميل.');
  }

  // ----- progressive (MP4 & co.) -----

  /// Android: the file is fetched by the platform's HTTP stack (the one
  /// ExoPlayer uses), which honours network_security_config — required for
  /// CDNs with incomplete TLS chains such as Akwam's. Dart only polls.
  Future<void> _runProgressiveNative(DownloadItem it, File part) async {
    final String fid = it.id;
    await _channel.invokeMethod<bool>('dlFetch', <String, dynamic>{
      'id': fid,
      'url': it.url,
      'headers': _headers(it),
      'path': part.path,
    });
    String contentType = '';
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_cancelRunning) {
        await _channel.invokeMethod<bool>(
            'dlFetchCancel', <String, String>{'id': fid});
        throw _Cancelled();
      }
      final Map<dynamic, dynamic>? st = await _channel
          .invokeMethod<Map<dynamic, dynamic>>(
              'dlFetchStatus', <String, String>{'id': fid});
      if (st == null) {
        throw DownloadException('توقف التحميل — أعد المحاولة.');
      }
      it.received = (st['received'] as num?)?.toInt() ?? 0;
      it.total = (st['total'] as num?)?.toInt() ?? 0;
      it.progress = it.total > 0 ? it.received / it.total : 0;
      notifyListeners();
      _save();
      final Object? err = st['error'];
      if (err != null) {
        final String e = err.toString();
        if (e.startsWith('HTTP 4')) {
          throw DownloadException(
              'رفض المصدر التحميل ($e) — افتح الصفحة مجددًا وأعد المحاولة.');
        }
        throw DownloadException('تعذّر تحميل الملف — تحقّق من اتصالك وأعد المحاولة.');
      }
      if (st['done'] == true) {
        contentType = (st['contentType'] ?? '').toString();
        break;
      }
    }
    final String ext = _extFor(contentType, it.url);
    await _publish(it, part, '${it.fileBase}.$ext', _mimeFor(ext), 'Videos');
  }

  Future<void> _runProgressive(DownloadItem it) async {
    final Directory dir = await _workDir(it.id);
    final File part = File('${dir.path}/file.part');
    if (Platform.isAndroid) {
      await _runProgressiveNative(it, part);
      return;
    }
    int have = part.existsSync() ? part.lengthSync() : 0;
    String contentType = '';
    int attempt = 0;
    while (true) {
      _checkCancel();
      final http.Request req = http.Request('GET', Uri.parse(it.url))
        ..headers.addAll(_headers(it, have > 0
            ? <String, String>{'Range': 'bytes=$have-'}
            : null));
      http.StreamedResponse res;
      try {
        res = await _http.send(req).timeout(const Duration(seconds: 40));
      } catch (e) {
        if (++attempt > 4) {
          throw DownloadException('خطأ في الشبكة أثناء التحميل.');
        }
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      if (res.statusCode == 416 && have > 0) break; // already complete
      if (res.statusCode != 200 && res.statusCode != 206) {
        await res.stream.drain<void>().catchError((_) {});
        throw DownloadException(
            'رفض المصدر التحميل (HTTP ${res.statusCode}).');
      }
      contentType = res.headers['content-type'] ?? '';
      if (res.statusCode == 200 && have > 0) {
        // Server ignored the Range — restart from scratch.
        have = 0;
        part.writeAsBytesSync(const <int>[]);
      }
      final int len = res.contentLength ?? 0;
      it.total = len > 0 ? have + len : 0;
      final RandomAccessFile raf =
          await part.open(mode: have > 0 ? FileMode.append : FileMode.write);
      int lastTick = 0;
      bool dropped = false;
      try {
        await for (final List<int> chunk in res.stream) {
          if (_cancelRunning) throw _Cancelled();
          await raf.writeFrom(chunk);
          have += chunk.length;
          it.received = have;
          it.progress = it.total > 0 ? have / it.total : 0;
          final int now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastTick > 400) {
            lastTick = now;
            notifyListeners();
            _save();
          }
        }
      } on _Cancelled {
        rethrow;
      } catch (_) {
        dropped = true;
      } finally {
        await raf.close();
      }
      if (!dropped && (it.total == 0 || have >= it.total)) break;
      if (++attempt > 6) {
        throw DownloadException('الاتصال ينقطع باستمرار — أعد المحاولة لاحقًا.');
      }
      await Future<void>.delayed(Duration(seconds: attempt));
    }
    final String ext = _extFor(contentType, it.url);
    final String mime = _mimeFor(ext);
    await _publish(it, part, '${it.fileBase}.$ext', mime, 'Videos');
  }

  static String _extFor(String contentType, String url) {
    final String ct = contentType.toLowerCase();
    if (ct.contains('matroska')) return 'mkv';
    if (ct.contains('webm')) return 'webm';
    if (ct.contains('mp2t')) return 'ts';
    final String path = (Uri.tryParse(url)?.path ?? '').toLowerCase();
    for (final String e in <String>['mkv', 'webm', 'avi', 'mov', 'ts', 'm4v']) {
      if (path.endsWith('.$e')) return e;
    }
    return 'mp4';
  }

  static String _mimeFor(String ext) {
    switch (ext) {
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'ts':
        return 'video/mp2t';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case 'm4a':
        return 'audio/mp4';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'video/mp4';
    }
  }

  // ----- HLS -----

  Future<void> _runHls(DownloadItem it) async {
    final Uri src = Uri.parse(it.url);
    final String top = utf8.decode(await _getBytes(it, src), allowMalformed: true);
    Uri videoUri = src;
    Uri? audioUri;
    String videoBody = top;
    if (HlsParser.isMaster(top)) {
      final HlsMaster m = HlsParser.parseMaster(top, src);
      final HlsStreamVariant? v = m.best();
      if (v == null) throw DownloadException('لا توجد جودة قابلة للتشغيل في هذا البث.');
      videoUri = v.uri;
      audioUri = m.audioFor(v)?.uri;
      videoBody =
          utf8.decode(await _getBytes(it, videoUri), allowMalformed: true);
    }
    final HlsMediaPlaylist vp = HlsParser.parseMedia(videoBody, videoUri);
    HlsMediaPlaylist? ap;
    if (audioUri != null) {
      ap = HlsParser.parseMedia(
          utf8.decode(await _getBytes(it, audioUri), allowMalformed: true),
          audioUri);
    }
    for (final HlsMediaPlaylist p in <HlsMediaPlaylist>[vp, ?ap]) {
      if (p.segments.isEmpty) {
        throw DownloadException('قائمة البث فارغة.');
      }
      if (p.segments.any((HlsSegment s) =>
          s.key != null && s.key!.method != 'AES-128')) {
        throw DownloadException(
            'هذا البث محمي بنظام DRM ولا يمكن حفظه.');
      }
    }
    final int totalSegs = vp.segments.length + (ap?.segments.length ?? 0);
    final Directory dir = await _workDir(it.id);
    final File vFile = File('${dir.path}/video.part');
    final File? aFile = ap == null ? null : File('${dir.path}/audio.part');
    final Map<String, Uint8List> keys = <String, Uint8List>{};

    int doneOther = 0;
    await _hlsTrack(it, 'v', vp, vFile, keys, (int done) {
      it.progress = done / totalSegs;
    });
    doneOther = vp.segments.length;
    if (ap != null) {
      await _hlsTrack(it, 'a', ap, aFile!, keys, (int done) {
        it.progress = (doneOther + done) / totalSegs;
      });
    }
    _checkCancel();

    // Remux into one MP4 (video + separate audio, or MPEG-TS → MP4).
    final File out = File('${dir.path}/out.mp4');
    final bool muxed = await _mux(
        <String>[vFile.path, if (aFile != null) aFile.path], out.path);
    if (muxed) {
      await _publish(it, out, '${it.fileBase}.mp4', 'video/mp4', 'Videos');
      return;
    }
    // Fallback: raw files (fMP4 concatenation is itself a valid MP4).
    final String vExt = vp.isFragmentedMp4 ? 'mp4' : 'ts';
    await _publish(it, vFile, '${it.fileBase}.$vExt', _mimeFor(vExt), 'Videos');
    if (aFile != null) {
      final String main = it.resultUri;
      final String loc = it.resultLocation;
      await _publish(it, aFile, '${it.fileBase} (audio).m4a', 'audio/mp4', 'Videos');
      it.extraUri = it.resultUri;
      it.resultUri = main;
      it.resultLocation = loc;
      it.mime = _mimeFor(vExt);
    }
  }

  Future<void> _hlsTrack(
    DownloadItem it,
    String track,
    HlsMediaPlaylist pl,
    File file,
    Map<String, Uint8List> keys,
    void Function(int done) onProgress,
  ) async {
    final List<int> state = it.resume[track] ?? <int>[0, 0];
    int done = state[0];
    int written = state[1];
    // Drop any bytes written after the last checkpoint.
    if (file.existsSync() && file.lengthSync() != written) {
      final RandomAccessFile t = await file.open(mode: FileMode.append);
      await t.truncate(written);
      await t.close();
    } else if (!file.existsSync()) {
      done = 0;
      written = 0;
      file.createSync(recursive: true);
    }

    Future<Uint8List> fetch(Uri uri, HlsByteRange? range, HlsKey? key,
        int sequence) async {
      Uint8List data = await _getBytes(it, uri,
          extra: range == null ? null : <String, String>{'Range': range.header});
      if (range != null && data.length > range.length) {
        // Server ignored Range: slice locally.
        data = Uint8List.sublistView(
            data, range.offset, range.offset + range.length);
      }
      if (key != null && key.isEncrypted) {
        final String ku = key.uri.toString();
        final Uint8List k = keys[ku] ??= await _getBytes(it, key.uri!);
        if (k.length != 16) {
          throw DownloadException('هذا البث يستخدم تشفيرًا غير مدعوم.');
        }
        data = HlsParser.decryptAes128(data, k, HlsParser.ivFor(key, sequence));
      }
      return data;
    }

    final RandomAccessFile raf = await file.open(mode: FileMode.append);
    try {
      if (written == 0 && done == 0 && pl.initUri != null) {
        final Uint8List init =
            await fetch(pl.initUri!, pl.initRange, pl.initKey, 0);
        await raf.writeFrom(init);
        written += init.length;
        it.resume[track] = <int>[0, written];
      }
      // Small sliding window: fetch ahead in parallel, write in order.
      const int window = 4;
      final List<Future<Uint8List>> inflight = <Future<Uint8List>>[];
      int nextIdx = done;
      void fill() {
        while (inflight.length < window && nextIdx < pl.segments.length) {
          final HlsSegment s = pl.segments[nextIdx++];
          final Future<Uint8List> f = fetch(s.uri, s.range, s.key, s.sequence);
          f.ignore(); // errors surface when awaited below
          inflight.add(f);
        }
      }

      fill();
      int lastTick = 0;
      while (inflight.isNotEmpty) {
        _checkCancel();
        final Uint8List bytes = await inflight.removeAt(0);
        _checkCancel();
        await raf.writeFrom(bytes);
        written += bytes.length;
        done++;
        it.resume[track] = <int>[done, written];
        it.received += bytes.length;
        onProgress(done);
        final int now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastTick > 400) {
          lastTick = now;
          notifyListeners();
          _save();
        }
        fill();
      }
    } finally {
      await raf.close();
    }
  }

  Future<bool> _mux(List<String> inputs, String output) async {
    try {
      return await _channel.invokeMethod<bool>('dlMux', <String, dynamic>{
            'inputs': inputs,
            'output': output,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ----- Comics → PDF -----

  Future<void> _runComic(DownloadItem it) async {
    List<String> pages;
    try {
      pages = await MangaApi.I.pages(it.chapterId);
    } catch (_) {
      throw DownloadException('تعذّر تحميل صفحات الفصل.');
    }
    if (pages.isEmpty) throw DownloadException('هذا الفصل لا يحتوي على صفحات.');
    final pw.Document doc = pw.Document(
      title: '${it.title} — ${it.subtitle}',
      creator: 'Animax',
    );
    for (int i = 0; i < pages.length; i++) {
      _checkCancel();
      Uint8List bytes;
      try {
        bytes = await _getBytes(it, Uri.parse(pages[i]));
      } catch (e) {
        if (e is _Cancelled) rethrow;
        // MangaDex at-home URLs can expire: refresh the list once.
        pages = await MangaApi.I.pages(it.chapterId);
        bytes = await _getBytes(it, Uri.parse(pages[i]));
      }
      final pw.MemoryImage image = await _pdfImage(bytes);
      final double w = (image.width ?? 800).toDouble();
      final double h = (image.height ?? 1200).toDouble();
      const double pageW = 595; // A4 width in points
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(pageW, pageW * h / w, marginAll: 0),
        build: (_) => pw.Image(image, fit: pw.BoxFit.contain),
      ));
      it.received += bytes.length;
      it.progress = (i + 1) / (pages.length + 1);
      notifyListeners();
      _save();
    }
    _checkCancel();
    final Directory dir = await _workDir(it.id);
    final File out = File('${dir.path}/out.pdf');
    await out.writeAsBytes(await doc.save());
    await _publish(it, out, '${it.fileBase}.pdf', 'application/pdf', 'Comics');
  }

  /// JPEG/PNG go straight in; anything else (WebP, GIF) is re-encoded.
  static Future<pw.MemoryImage> _pdfImage(Uint8List bytes) async {
    final bool jpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    final bool png = bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    if (jpeg || png) return pw.MemoryImage(bytes);
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw DownloadException('تعذّرت قراءة صورة إحدى الصفحات.');
    }
    return pw.MemoryImage(Uint8List.fromList(img.encodeJpg(decoded, quality: 90)));
  }

  // ----- Publishing -----

  Future<bool> _ensureStorage() async {
    try {
      return await _channel.invokeMethod<bool>('dlEnsureStorage') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Moves [file] into the public `Download/Animax/[folder]` collection.
  /// Falls back to keeping it in app storage when that is not possible.
  Future<void> _publish(DownloadItem it, File file, String name, String mime,
      String folder) async {
    it.mime = mime;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      Directory? dl;
      try {
        dl = await getDownloadsDirectory();
      } catch (_) {}
      if (dl != null) {
        final Directory dir = Directory('${dl.path}/Animax/$folder');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        File dest = File('${dir.path}/$name');
        int n = 1;
        while (dest.existsSync()) {
          final int dot = name.lastIndexOf('.');
          final String stem = dot > 0 ? name.substring(0, dot) : name;
          final String ext = dot > 0 ? name.substring(dot) : '';
          dest = File('${dir.path}/$stem ($n)$ext');
          n++;
        }
        try {
          await file.rename(dest.path);
        } catch (_) {
          await file.copy(dest.path); // different volume
        }
        it.resultUri = dest.path;
        it.resultLocation = dest.path;
        return;
      }
    }
    try {
      final Map<dynamic, dynamic>? r =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('dlPublish',
              <String, String>{
            'path': file.path,
            'name': name,
            'mime': mime,
            'folder': folder,
          });
      final String uri = (r?['uri'] ?? '').toString();
      if (uri.isNotEmpty) {
        it.resultUri = uri;
        it.resultLocation = (r?['location'] ?? 'Download/Animax/$folder/$name').toString();
        return;
      }
    } catch (_) {}
    // Fallback (tests / no MediaStore): keep a private copy.
    final Directory keep =
        Directory('${(await getApplicationSupportDirectory()).path}/downloads/$folder');
    if (!keep.existsSync()) keep.createSync(recursive: true);
    final File dest = File('${keep.path}/$name');
    await file.copy(dest.path);
    it.resultUri = dest.path;
    it.resultLocation = dest.path;
  }
}
