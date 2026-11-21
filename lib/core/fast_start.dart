// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'app_http.dart';
import 'net_quality.dart';

/// Fast start for progressive MP4 (Akwam) on slow connections.
///
/// A regular MP4 keeps one index (`moov`) for the whole file: every frame's
/// size, position and timestamp. A 1h45 movie carries ~4 MB of it, and a
/// player must download all of it before showing the first frame — ~45 s at
/// 100 KB/s. HLS (the +18 section) has no such cost, which is why it starts
/// fast.
///
/// FastStart reads only the *slices* of the index that cover the part being
/// watched (via HTTP range requests), writes a small standalone MP4 index
/// for that window, and serves a virtual file from a local HTTP server:
///
/// ```
/// [ftyp][mini moov][mdat header][original media bytes of the window]
/// ```
///
/// The media bytes stream straight from the CDN (range requests), so the
/// player starts after a few dozen KB instead of megabytes. Windows are
/// keyframe-aligned so the player can chain them seamlessly.
class FastStart {
  FastStart._();

  static final Map<String, Mp4Index> _indexes = <String, Mp4Index>{};
  static final List<String> _lru = <String>[];

  /// Parsed index header for [url] (cached for the last few files).
  static Future<Mp4Index> index(String url, Map<String, String> headers) async {
    final Mp4Index? hit = _indexes[url];
    if (hit != null) {
      _lru
        ..remove(url)
        ..add(url);
      return hit;
    }
    final Mp4Index ix = await Mp4Index.open(RangeReader(url, headers));
    _indexes[url] = ix;
    _lru.add(url);
    while (_lru.length > 4) {
      _indexes.remove(_lru.removeAt(0));
    }
    return ix;
  }

  /// Builds a window starting at the keyframe at/before [from] seconds and
  /// serves it locally. With [to] the window ends there (clips); otherwise
  /// it spans about [length] seconds and ends on a keyframe so the next
  /// window continues seamlessly.
  static Future<FastWindow> open(
    String url,
    Map<String, String> headers, {
    required double from,
    double? to,
    double length = 120,
  }) async {
    final Mp4Index ix = await index(url, headers);
    final WindowPlan plan = await ix.plan(from: from, to: to, length: length);
    final Uint8List head = ix.buildHead(plan);
    final Uri uri = await FastStartServer.I.publish(
      VirtualMp4(
        reader: ix.reader,
        head: head,
        regionStart: plan.regionStart,
        regionEnd: plan.regionEnd,
      ),
    );
    return FastWindow(
      uri: uri,
      offset: plan.startSec,
      length: plan.endSec - plan.startSec,
      total: ix.durationSec,
      isLast: plan.isLast,
      indexBytes: head.length,
    );
  }
}

/// A playable window of a movie.
class FastWindow {
  const FastWindow({
    required this.uri,
    required this.offset,
    required this.length,
    required this.total,
    required this.isLast,
    required this.indexBytes,
  });

  /// Local URL of the virtual MP4.
  final Uri uri;

  /// Real time (s) of the window's first frame in the movie.
  final double offset;
  final double length;

  /// Real duration of the whole movie (s).
  final double total;

  /// The window reaches the end of the movie.
  final bool isLast;

  /// Size of the generated header (ftyp + moov + mdat header).
  final int indexBytes;

  double get end => offset + length;
}

// =============================================================================
// HTTP range reads
// =============================================================================

class RangeReader {
  RangeReader(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
  int totalLength = -1;
  final HttpClient _client = createIoHttpClient();

  /// Bytes fetched / requests made so far (diagnostics).
  int fetched = 0;
  int requests = 0;
  final List<String> log = <String>[];

  static const int _block = 8192;
  final Map<int, Uint8List> _blocks = <int, Uint8List>{};

  /// Exactly [len] bytes at [off] (fewer only at end of file).
  Future<Uint8List> read(int off, int len) async {
    if (len <= 0) return Uint8List(0);
    Object? last;
    requests++;
    log.add('$off+$len');
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final Stopwatch sw = Stopwatch()..start();
        final HttpClientRequest rq = await _client.getUrl(Uri.parse(url));
        headers.forEach(rq.headers.set);
        rq.headers.set(HttpHeaders.rangeHeader, 'bytes=$off-${off + len - 1}');
        final HttpClientResponse rs = await rq.close().timeout(
          const Duration(seconds: 25),
        );
        if (rs.statusCode != 206 && rs.statusCode != 200) {
          await rs.drain<void>();
          throw HttpException('HTTP ${rs.statusCode}');
        }
        final String? cr = rs.headers.value(HttpHeaders.contentRangeHeader);
        final RegExpMatch? m = cr == null
            ? null
            : RegExp(r'/(\d+)').firstMatch(cr);
        if (m != null) totalLength = int.parse(m.group(1)!);
        final BytesBuilder b = BytesBuilder(copy: false);
        int got = 0;
        await for (final List<int> chunk in rs.timeout(
          const Duration(seconds: 25),
        )) {
          // A 200 (no range support) streams the whole file: stop early.
          if (rs.statusCode == 200) {
            final int skip = math.max(0, off - got);
            got += chunk.length;
            if (skip >= chunk.length) continue;
            b.add(chunk.sublist(skip));
            if (b.length >= len) break;
          } else {
            b.add(chunk);
          }
        }
        final Uint8List out = b.takeBytes();
        fetched += out.length;
        NetQuality.record(out.length, sw.elapsedMilliseconds);
        return out.length > len ? Uint8List.sublistView(out, 0, len) : out;
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw last ?? const HttpException('range read failed');
  }

  /// Small reads (box headers) served from cached 8 KB blocks.
  Future<Uint8List> readSmall(int off, int len) async {
    final int b0 = off ~/ _block, b1 = (off + len - 1) ~/ _block;
    final BytesBuilder out = BytesBuilder(copy: false);
    for (int b = b0; b <= b1; b++) {
      Uint8List? blk = _blocks[b];
      if (blk == null) {
        blk = await read(b * _block, _block);
        _blocks[b] = blk;
      }
      final int s = b == b0 ? off - b * _block : 0;
      final int e = b == b1
          ? math.min(blk.length, off + len - b * _block)
          : blk.length;
      if (s < e) out.add(Uint8List.sublistView(blk, s, e));
    }
    return out.takeBytes();
  }

  void close() => _client.close(force: true);
}

// =============================================================================
// MP4 index model
// =============================================================================

class _Box {
  _Box(this.type, this.off, this.size, this.hdr);
  final String type;
  final int off;
  final int size;
  final int hdr;
  int get dataOff => off + hdr;
  int get end => off + size;
}

/// A table of fixed-size entries inside the file, read lazily.
class _Table {
  _Table(this.reader, this.dataOff, this.count, this.entrySize);
  final RangeReader reader;
  final int dataOff; // first entry
  final int count;
  final int entrySize;

  /// Entries [0, prefixLen) loaded so far (for prefix-scanned tables).
  Uint8List prefix = Uint8List(0);
  int get prefixLen => prefix.length ~/ entrySize;

  /// Loads entries up to [n]. With [grow] (unknown target) the read grows
  /// geometrically so a long scan costs few round trips.
  Future<void> ensurePrefix(int n, {bool grow = false}) async {
    n = math.min(n, count);
    if (prefixLen >= n) return;
    final int want = grow
        ? math.min(count, math.max(n, prefixLen * 2 + 1024))
        : math.min(count, n);
    final Uint8List more = await reader.read(
      dataOff + prefixLen * entrySize,
      (want - prefixLen) * entrySize,
    );
    final Uint8List all = Uint8List(prefix.length + more.length)
      ..setAll(0, prefix)
      ..setAll(prefix.length, more);
    prefix = all;
  }

  /// Random access to entries [i0, i0+n).
  Future<ByteData> slice(int i0, int n) async {
    if (i0 + n <= prefixLen) {
      return ByteData.sublistView(prefix, i0 * entrySize, (i0 + n) * entrySize);
    }
    final Uint8List b = await reader.read(
      dataOff + i0 * entrySize,
      n * entrySize,
    );
    return ByteData.sublistView(b);
  }
}

class _Track {
  String handler = '';
  int timescale = 1;
  late Uint8List tkhd, mdhd, hdlr, mhd, dinf, stsd;
  int tkhdVersion = 0;

  /// (count, delta) runs.
  List<List<int>> stts = <List<int>>[];
  int sampleCount = 0;

  /// 1-based sync sample numbers (null → every sample is a sync sample).
  List<int>? stss;
  _Table? ctts;
  int cttsVersion = 0;
  late _Table stsc;
  int stszUniform = 0;
  _Table? stsz;
  late _Table chunkOffsets; // stco (4 B) or co64 (8 B)
  int chunkCount = 0;
  int editMediaTime = 0;

  bool get isVideo => handler == 'vide';

  /// Decode time of 0-based [sample] (track timescale).
  int dts(int sample) {
    int t = 0, s = 0;
    for (final List<int> r in stts) {
      if (sample < s + r[0]) return t + (sample - s) * r[1];
      t += r[0] * r[1];
      s += r[0];
    }
    return t;
  }

  /// Last sample whose decode time is ≤ [time] (0-based).
  int sampleAt(int time) {
    int t = 0, s = 0;
    for (final List<int> r in stts) {
      final int span = r[0] * r[1];
      if (time < t + span) return s + ((time - t) ~/ math.max(1, r[1]));
      t += span;
      s += r[0];
    }
    return math.max(0, sampleCount - 1);
  }

  int get durationTs => dts(sampleCount);

  /// Largest 0-based sync sample ≤ [s].
  int syncAtOrBefore(int s) {
    final List<int>? ss = stss;
    if (ss == null || ss.isEmpty) return s;
    int lo = 0, hi = ss.length - 1, best = ss.first - 1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      if (ss[mid] - 1 <= s) {
        best = ss[mid] - 1;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  /// Smallest 0-based sync sample ≥ [s] (or [sampleCount]).
  int syncAtOrAfter(int s) {
    final List<int>? ss = stss;
    if (ss == null || ss.isEmpty) return math.min(s, sampleCount);
    for (final int k in ss) {
      if (k - 1 >= s) return k - 1;
    }
    return sampleCount;
  }

  /// Composition offsets of samples [s0, s1).
  Future<List<int>> compOffsets(int s0, int s1) async {
    final _Table? c = ctts;
    if (c == null) return List<int>.filled(s1 - s0, 0);
    final List<int> out = <int>[];
    int s = 0, i = 0;
    while (s < s1) {
      if (i >= c.prefixLen) {
        if (i >= c.count) break;
        // Each entry covers ≥ 1 sample: this bound never under-reads much.
        await c.ensurePrefix(i + (s1 - s) + 64);
      }
      final ByteData d = ByteData.sublistView(c.prefix);
      final int cnt = d.getUint32(i * 8);
      final int off = cttsVersion == 1
          ? d.getInt32(i * 8 + 4)
          : d.getUint32(i * 8 + 4);
      final int a = math.max(s, s0), b = math.min(s + cnt, s1);
      for (int k = a; k < b; k++) {
        out.add(off);
      }
      s += cnt;
      i++;
    }
    while (out.length < s1 - s0) {
      out.add(0);
    }
    return out;
  }

  /// Absolute file offsets and sizes of samples [s0, s1).
  Future<({List<int> offsets, List<int> sizes})> locate(int s0, int s1) async {
    // 1. stsc (firstChunk, samplesPerChunk, sdi): chunks holding s0..s1-1.
    int firstSampleOfChunk0 = 0, chunk0 = -1, chunkLast = -1, entry0 = 0;
    {
      int sample = 0, i = 0;
      while (true) {
        if (i + 1 >= stsc.prefixLen && stsc.prefixLen < stsc.count) {
          await stsc.ensurePrefix(i + 2, grow: true);
        }
        if (i >= stsc.prefixLen) break;
        final ByteData d = ByteData.sublistView(stsc.prefix);
        final int fc = d.getUint32(i * 12) - 1;
        final int per = math.max(1, d.getUint32(i * 12 + 4));
        final int nextFc = i + 1 < stsc.prefixLen
            ? d.getUint32((i + 1) * 12) - 1
            : chunkCount;
        final int runSamples = (nextFc - fc) * per;
        if (chunk0 < 0 && s0 < sample + runSamples) {
          chunk0 = fc + (s0 - sample) ~/ per;
          firstSampleOfChunk0 = sample + (chunk0 - fc) * per;
          entry0 = i;
        }
        if (s1 - 1 < sample + runSamples) {
          chunkLast = fc + (s1 - 1 - sample) ~/ per;
          break;
        }
        sample += runSamples;
        i++;
      }
    }
    if (chunk0 < 0 || chunkLast < 0) throw StateError('sample outside table');

    // Samples per chunk for chunks [chunk0, chunkLast] (single pass).
    final List<int> perChunk = <int>[];
    {
      final ByteData d = ByteData.sublistView(stsc.prefix);
      int e = entry0;
      for (int c = chunk0; c <= chunkLast; c++) {
        while (e + 1 < stsc.prefixLen && d.getUint32((e + 1) * 12) - 1 <= c) {
          e++;
        }
        perChunk.add(math.max(1, d.getUint32(e * 12 + 4)));
      }
    }

    // 2 + 3. Chunk offsets and sample sizes (fetched in parallel).
    final int n = s1 - firstSampleOfChunk0;
    final List<ByteData?> got = await Future.wait(<Future<ByteData?>>[
      chunkOffsets.slice(chunk0, chunkLast - chunk0 + 1),
      if (stszUniform == 0) stsz!.slice(firstSampleOfChunk0, n),
    ]);
    final ByteData co = got[0]!;
    final ByteData? sz = stszUniform == 0 ? got[1] : null;
    int chunkOff(int i) =>
        chunkOffsets.entrySize == 8 ? co.getUint64(i * 8) : co.getUint32(i * 4);
    int sizeOf(int i) => stszUniform != 0 ? stszUniform : sz!.getUint32(i * 4);

    final List<int> offs = <int>[], sizes = <int>[];
    int sample = firstSampleOfChunk0;
    for (int ci = 0; ci <= chunkLast - chunk0 && sample < s1; ci++) {
      int pos = chunkOff(ci);
      for (int k = 0; k < perChunk[ci] && sample < s1; k++) {
        final int size = sizeOf(sample - firstSampleOfChunk0);
        if (sample >= s0) {
          offs.add(pos);
          sizes.add(size);
        }
        pos += size;
        sample++;
      }
    }
    return (offsets: offs, sizes: sizes);
  }
}

class _TrackPlan {
  _TrackPlan(this.track, this.s0, this.s1);
  final _Track track;
  final int s0, s1;
  List<int> offsets = <int>[];
  List<int> sizes = <int>[];
  List<int> comp = <int>[];
  int mediaTime = 0;
}

class WindowPlan {
  WindowPlan(this.tracks, this.startSec, this.endSec, this.isLast);
  final List<_TrackPlan> tracks;
  final double startSec;
  final double endSec;
  final bool isLast;
  int regionStart = 0;
  int regionEnd = 0;
}

class Mp4Index {
  Mp4Index._(this.reader);
  final RangeReader reader;

  late Uint8List ftyp;
  late Uint8List mvhd;
  int movieTimescale = 1000;
  final List<_Track> tracks = <_Track>[];

  double get durationSec {
    final _Track v = _video;
    return (v.durationTs - v.editMediaTime) / v.timescale;
  }

  _Track get _video =>
      tracks.firstWhere((_Track t) => t.isVideo, orElse: () => tracks.first);

  static const Set<String> _containers = <String>{
    'moov',
    'trak',
    'mdia',
    'minf',
    'stbl',
    'edts',
  };

  static Future<Mp4Index> open(RangeReader r) async {
    final Mp4Index ix = Mp4Index._(r);
    await ix._load();
    return ix;
  }

  Future<_Box> _boxAt(int off) async {
    final ByteData h = ByteData.sublistView(await reader.readSmall(off, 16));
    int size = h.getUint32(0);
    final String type = String.fromCharCodes(<int>[
      h.getUint8(4),
      h.getUint8(5),
      h.getUint8(6),
      h.getUint8(7),
    ]);
    int hdr = 8;
    if (size == 1) {
      size = h.getUint64(8);
      hdr = 16;
    } else if (size == 0) {
      size = (reader.totalLength > 0 ? reader.totalLength : off + 8) - off;
    }
    if (size < hdr) throw StateError('bad box $type at $off');
    return _Box(type, off, size, hdr);
  }

  /// Whole box bytes; small boxes come from the cached header blocks.
  Future<Uint8List> _whole(_Box b) => b.size <= 65536
      ? reader.readSmall(b.off, b.size)
      : reader.read(b.off, b.size);

  Future<void> _load() async {
    // Top level: ftyp, then moov (fast-start files) or mdat then moov.
    _Box? moov;
    int off = 0;
    for (int guard = 0; guard < 16; guard++) {
      final _Box b = await _boxAt(off);
      if (b.type == 'ftyp') ftyp = await reader.readSmall(b.off, b.size);
      if (b.type == 'moov') {
        moov = b;
        break;
      }
      off = b.end;
      if (reader.totalLength > 0 && off >= reader.totalLength) break;
    }
    if (moov == null) throw StateError('no moov');
    // Walk moov children.
    _Track? cur;
    Future<void> walk(int from, int to) async {
      int o = from;
      while (o + 8 <= to) {
        final _Box b = await _boxAt(o);
        switch (b.type) {
          case 'mvhd':
            mvhd = await _whole(b);
            final ByteData d = ByteData.sublistView(mvhd);
            movieTimescale = d.getUint32(d.getUint8(8) == 1 ? 28 : 20);
          case 'trak':
            cur = _Track();
            tracks.add(cur!);
            await walk(b.dataOff, b.end);
          case 'tkhd':
            cur!.tkhd = await _whole(b);
            cur!.tkhdVersion = cur!.tkhd[8];
          case 'elst':
            final ByteData d = ByteData.sublistView(await _whole(b));
            final int v = d.getUint8(8);
            final int n = d.getUint32(12);
            for (int i = 0; i < n; i++) {
              final int mt = v == 1
                  ? d.getInt64(16 + i * 20 + 8)
                  : d.getInt32(16 + i * 12 + 4);
              if (mt >= 0) {
                cur!.editMediaTime = mt;
                break;
              }
            }
          case 'mdhd':
            cur!.mdhd = await _whole(b);
            final ByteData d = ByteData.sublistView(cur!.mdhd);
            cur!.timescale = d.getUint32(d.getUint8(8) == 1 ? 28 : 20);
          case 'hdlr':
            cur!.hdlr = await _whole(b);
            cur!.handler = String.fromCharCodes(cur!.hdlr.sublist(16, 20));
          case 'vmhd' || 'smhd' || 'nmhd' || 'sthd':
            cur!.mhd = await _whole(b);
          case 'dinf':
            cur!.dinf = await _whole(b);
          case 'stsd':
            cur!.stsd = await _whole(b);
          case 'stts':
            final ByteData d = ByteData.sublistView(await _whole(b));
            final int n = d.getUint32(12);
            cur!.stts = <List<int>>[
              for (int i = 0; i < n; i++)
                <int>[d.getUint32(16 + i * 8), d.getUint32(20 + i * 8)],
            ];
            cur!.sampleCount = cur!.stts.fold(
              0,
              (int a, List<int> r) => a + r[0],
            );
          case 'stss':
            final ByteData d = ByteData.sublistView(await _whole(b));
            final int n = d.getUint32(12);
            cur!.stss = <int>[
              for (int i = 0; i < n; i++) d.getUint32(16 + i * 4),
            ];
          case 'ctts':
            final ByteData h = ByteData.sublistView(
              await reader.readSmall(b.dataOff, 8),
            );
            cur!.cttsVersion = h.getUint8(0);
            cur!.ctts = _Table(reader, b.dataOff + 8, h.getUint32(4), 8);
          case 'stsc':
            final ByteData h = ByteData.sublistView(
              await reader.readSmall(b.dataOff, 8),
            );
            cur!.stsc = _Table(reader, b.dataOff + 8, h.getUint32(4), 12);
          case 'stsz':
            final ByteData h = ByteData.sublistView(
              await reader.readSmall(b.dataOff, 12),
            );
            cur!.stszUniform = h.getUint32(4);
            final int n = h.getUint32(8);
            if (cur!.stszUniform == 0) {
              cur!.stsz = _Table(reader, b.dataOff + 12, n, 4);
            }
          case 'stco' || 'co64':
            final ByteData h = ByteData.sublistView(
              await reader.readSmall(b.dataOff, 8),
            );
            cur!.chunkCount = h.getUint32(4);
            cur!.chunkOffsets = _Table(
              reader,
              b.dataOff + 8,
              cur!.chunkCount,
              b.type == 'co64' ? 8 : 4,
            );
          default:
            if (_containers.contains(b.type)) await walk(b.dataOff, b.end);
        }
        o = b.end;
      }
    }

    await walk(moov.dataOff, moov.end);
    tracks.removeWhere(
      (_Track t) =>
          (t.handler != 'vide' && t.handler != 'soun') || t.sampleCount == 0,
    );
    if (!tracks.any((_Track t) => t.isVideo)) {
      throw StateError('no video track');
    }
  }

  /// Plans a window: keyframe-aligned start at/before [from]; ends at [to]
  /// (exact, for clips) or at the first keyframe after from+[length].
  Future<WindowPlan> plan({
    required double from,
    double? to,
    double length = 120,
  }) async {
    final _Track v = _video;
    from = from.clamp(0, math.max(0, durationSec - 0.5)).toDouble();
    int k0 = v.syncAtOrBefore(
      v.sampleAt((from * v.timescale).round() + v.editMediaTime),
    );
    int k1;
    if (to != null) {
      k1 = math.min(
        v.sampleCount,
        v.sampleAt((to * v.timescale).round() + v.editMediaTime) + 1,
      );
    } else {
      final int target = v.sampleAt(
        ((from + length) * v.timescale).round() + v.editMediaTime,
      );
      k1 = v.syncAtOrAfter(target + 1);
      // Never leave a tiny tail window.
      final double tail = (v.dts(v.sampleCount) - v.dts(k1)) / v.timescale;
      if (tail < 30) k1 = v.sampleCount;
    }
    if (k1 <= k0) k1 = math.min(v.sampleCount, k0 + 1);

    final List<int> vComp = await v.compOffsets(k0, k1);
    final double startSec =
        (v.dts(k0) + vComp.first - v.editMediaTime) / v.timescale;
    final double endSec = k1 >= v.sampleCount
        ? durationSec
        : (v.dts(k1) +
                  (await v.compOffsets(k1, k1 + 1)).first -
                  v.editMediaTime) /
              v.timescale;

    Future<_TrackPlan?> planTrack(_Track t) async {
      _TrackPlan p;
      if (identical(t, v)) {
        p = _TrackPlan(t, k0, k1)
          ..comp = vComp
          ..mediaTime = vComp.first;
      } else {
        // Audio: samples presented in [startSec, endSec).
        final int a0 = t.sampleAt(
          (startSec * t.timescale).round() + t.editMediaTime,
        );
        final int a1 = k1 >= v.sampleCount
            ? t.sampleCount
            : math.min(
                t.sampleCount,
                t.sampleAt((endSec * t.timescale).round() + t.editMediaTime),
              );
        if (a1 <= a0) return null;
        p = _TrackPlan(t, a0, a1)
          ..comp = await t.compOffsets(a0, a1)
          ..mediaTime = a0 == 0 ? t.editMediaTime : 0;
      }
      final ({List<int> offsets, List<int> sizes}) loc = await t.locate(
        p.s0,
        p.s1,
      );
      return p
        ..offsets = loc.offsets
        ..sizes = loc.sizes;
    }

    final List<_TrackPlan> plans = (await Future.wait(tracks.map(planTrack)))
        .whereType<_TrackPlan>()
        .toList();
    final WindowPlan w = WindowPlan(
      plans,
      startSec,
      endSec,
      k1 >= v.sampleCount,
    );
    int lo = 1 << 62, hi = 0;
    for (final _TrackPlan p in plans) {
      for (int i = 0; i < p.offsets.length; i++) {
        lo = math.min(lo, p.offsets[i]);
        hi = math.max(hi, p.offsets[i] + p.sizes[i]);
      }
    }
    w
      ..regionStart = lo
      ..regionEnd = hi;
    return w;
  }

  // ---------------------------------------------------------------- writing

  /// ftyp + window moov + mdat header. Sample offsets point into the media
  /// region that follows (original bytes [regionStart, regionEnd)).
  Uint8List buildHead(WindowPlan w) {
    final double durSec = w.endSec - w.startSec;
    Uint8List moovFor(int base) {
      final List<Uint8List> traks = <Uint8List>[];
      for (final _TrackPlan p in w.tracks) {
        traks.add(_trak(p, base, w.regionStart, durSec));
      }
      return _box('moov', <Uint8List>[_patchMvhd(durSec), ...traks]);
    }

    // Offsets depend on the header size, which does not depend on them.
    final int probe = ftyp.length + moovFor(0).length + 16;
    final Uint8List moov = moovFor(probe);
    final int mdatLen = 16 + (w.regionEnd - w.regionStart);
    final ByteData mdat = ByteData(16)
      ..setUint32(0, 1)
      ..setUint8(4, 0x6d) // m
      ..setUint8(5, 0x64) // d
      ..setUint8(6, 0x61) // a
      ..setUint8(7, 0x74) // t
      ..setUint64(8, mdatLen);
    final BytesBuilder b = BytesBuilder(copy: false)
      ..add(ftyp)
      ..add(moov)
      ..add(mdat.buffer.asUint8List());
    return b.takeBytes();
  }

  Uint8List _patchMvhd(double durSec) {
    final Uint8List m = Uint8List.fromList(mvhd);
    final ByteData d = ByteData.sublistView(m);
    final int dur = (durSec * movieTimescale).round();
    if (m[8] == 1) {
      d.setUint64(32, dur);
    } else {
      d.setUint32(24, dur);
    }
    return m;
  }

  Uint8List _trak(_TrackPlan p, int base, int regionStart, double durSec) {
    final _Track t = p.track;
    final int movieDur = (durSec * movieTimescale).round();
    // tkhd duration.
    final Uint8List tkhd = Uint8List.fromList(t.tkhd);
    final ByteData td = ByteData.sublistView(tkhd);
    if (t.tkhdVersion == 1) {
      td.setUint64(36, movieDur);
    } else {
      td.setUint32(28, movieDur);
    }
    // Media duration = sum of sample deltas.
    final int mediaDur = t.dts(p.s1) - t.dts(p.s0);
    final Uint8List mdhd = Uint8List.fromList(t.mdhd);
    final ByteData md = ByteData.sublistView(mdhd);
    if (mdhd[8] == 1) {
      md.setUint64(32, mediaDur);
    } else {
      md.setUint32(24, mediaDur);
    }
    // elst: one edit (v1).
    final ByteData el = ByteData(4 + 4 + 20)
      ..setUint32(0, 0x01000000) // version 1, flags 0
      ..setUint32(4, 1)
      ..setUint64(8, movieDur)
      ..setInt64(16, p.mediaTime)
      ..setInt16(24, 1)
      ..setInt16(26, 0);
    final Uint8List edts = _box('edts', <Uint8List>[
      _box('elst', <Uint8List>[el.buffer.asUint8List()]),
    ]);

    final int n = p.s1 - p.s0;
    // stts runs.
    final List<List<int>> runs = <List<int>>[];
    for (int s = p.s0; s < p.s1; s++) {
      final int d = t.dts(s + 1) - t.dts(s);
      if (runs.isNotEmpty && runs.last[1] == d) {
        runs.last[0]++;
      } else {
        runs.add(<int>[1, d]);
      }
    }
    final ByteData stts = ByteData(8 + runs.length * 8)
      ..setUint32(4, runs.length);
    for (int i = 0; i < runs.length; i++) {
      stts
        ..setUint32(8 + i * 8, runs[i][0])
        ..setUint32(12 + i * 8, runs[i][1]);
    }
    final List<Uint8List> stbl = <Uint8List>[
      t.stsd,
      _box('stts', <Uint8List>[stts.buffer.asUint8List()]),
    ];
    if (t.ctts != null) {
      final List<List<int>> cr = <List<int>>[];
      for (final int c in p.comp) {
        if (cr.isNotEmpty && cr.last[1] == c) {
          cr.last[0]++;
        } else {
          cr.add(<int>[1, c]);
        }
      }
      final ByteData ct = ByteData(8 + cr.length * 8)
        ..setUint32(0, t.cttsVersion << 24)
        ..setUint32(4, cr.length);
      for (int i = 0; i < cr.length; i++) {
        ct.setUint32(8 + i * 8, cr[i][0]);
        if (t.cttsVersion == 1) {
          ct.setInt32(12 + i * 8, cr[i][1]);
        } else {
          ct.setUint32(12 + i * 8, cr[i][1]);
        }
      }
      stbl.add(_box('ctts', <Uint8List>[ct.buffer.asUint8List()]));
    }
    if (t.stss != null) {
      final List<int> ks = <int>[
        for (final int k in t.stss!)
          if (k - 1 >= p.s0 && k - 1 < p.s1) k - p.s0,
      ];
      final ByteData ss = ByteData(8 + ks.length * 4)..setUint32(4, ks.length);
      for (int i = 0; i < ks.length; i++) {
        ss.setUint32(8 + i * 4, ks[i]);
      }
      stbl.add(_box('stss', <Uint8List>[ss.buffer.asUint8List()]));
    }
    // One sample per chunk.
    final ByteData stsc = ByteData(8 + 12)
      ..setUint32(4, 1)
      ..setUint32(8, 1)
      ..setUint32(12, 1)
      ..setUint32(16, 1);
    stbl.add(_box('stsc', <Uint8List>[stsc.buffer.asUint8List()]));
    final ByteData stsz = ByteData(12 + n * 4)..setUint32(8, n);
    for (int i = 0; i < n; i++) {
      stsz.setUint32(12 + i * 4, p.sizes[i]);
    }
    stbl.add(_box('stsz', <Uint8List>[stsz.buffer.asUint8List()]));
    final ByteData co = ByteData(8 + n * 8)..setUint32(4, n);
    for (int i = 0; i < n; i++) {
      co.setUint64(8 + i * 8, base + p.offsets[i] - regionStart);
    }
    stbl.add(_box('co64', <Uint8List>[co.buffer.asUint8List()]));

    final Uint8List minf = _box('minf', <Uint8List>[
      t.mhd,
      t.dinf,
      _box('stbl', stbl),
    ]);
    final Uint8List mdia = _box('mdia', <Uint8List>[mdhd, t.hdlr, minf]);
    return _box('trak', <Uint8List>[tkhd, edts, mdia]);
  }

  static Uint8List _box(String type, List<Uint8List> children) {
    int len = 8;
    for (final Uint8List c in children) {
      len += c.length;
    }
    final Uint8List out = Uint8List(len);
    ByteData.sublistView(out).setUint32(0, len);
    out.setAll(4, type.codeUnits);
    int o = 8;
    for (final Uint8List c in children) {
      out.setAll(o, c);
      o += c.length;
    }
    return out;
  }
}

// =============================================================================
// Local server
// =============================================================================

class VirtualMp4 {
  VirtualMp4({
    required this.reader,
    required this.head,
    required this.regionStart,
    required this.regionEnd,
  });
  final RangeReader reader;
  final Uint8List head;
  final int regionStart;
  final int regionEnd;
  int get length => head.length + (regionEnd - regionStart);
}

/// Serves [VirtualMp4]s on 127.0.0.1 with HTTP range support.
class FastStartServer {
  FastStartServer._();
  static final FastStartServer I = FastStartServer._();

  HttpServer? _server;
  final Map<String, VirtualMp4> _files = <String, VirtualMp4>{};
  final List<String> _order = <String>[];
  int _seq = 0;
  final HttpClient _up = createIoHttpClient();

  /// Test hook: limits upstream reads (bytes per second, 0 = unlimited).
  static int throttleBps = 0;

  Future<Uri> publish(VirtualMp4 f) async {
    _server ??= await _start();
    final String id = 'w${++_seq}';
    _files[id] = f;
    _order.add(id);
    while (_order.length > 48) {
      _files.remove(_order.removeAt(0));
    }
    return Uri.parse('http://127.0.0.1:${_server!.port}/fs/$id.mp4');
  }

  Future<HttpServer> _start() async {
    final HttpServer s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen(_handle, onError: (Object _) {});
    return s;
  }

  Future<void> _handle(HttpRequest rq) async {
    final HttpResponse res = rq.response;
    try {
      final String id = rq.uri.pathSegments.isEmpty
          ? ''
          : rq.uri.pathSegments.last.replaceAll('.mp4', '');
      final VirtualMp4? f = _files[id];
      if (f == null) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final int total = f.length;
      int a = 0, b = total - 1;
      final String? range = rq.headers.value(HttpHeaders.rangeHeader);
      final RegExpMatch? m = range == null
          ? null
          : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m != null) {
        if (m.group(1)!.isNotEmpty) a = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) {
          b = math.min(total - 1, int.parse(m.group(2)!));
        }
        if (m.group(1)!.isEmpty && m.group(2)!.isNotEmpty) {
          a = math.max(0, total - int.parse(m.group(2)!));
          b = total - 1;
        }
      }
      if (a >= total || a > b) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await res.close();
        return;
      }
      res.statusCode = m != null ? HttpStatus.partialContent : HttpStatus.ok;
      res.headers
        ..contentType = ContentType('video', 'mp4')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = b - a + 1;
      if (m != null) {
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $a-$b/$total');
      }
      if (rq.method == 'HEAD') {
        await res.close();
        return;
      }
      // Header part (memory).
      final int hl = f.head.length;
      if (a < hl) {
        res.add(Uint8List.sublistView(f.head, a, math.min(hl, b + 1)));
      }
      // Media part (CDN).
      if (b >= hl) {
        final int from = f.regionStart + math.max(0, a - hl);
        final int to = f.regionStart + (b - hl);
        final HttpClientRequest up = await _up.getUrl(Uri.parse(f.reader.url));
        f.reader.headers.forEach(up.headers.set);
        up.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-$to');
        final HttpClientResponse ur = await up.close();
        Stream<List<int>> body = ur;
        if (throttleBps > 0) body = _throttle(ur, throttleBps);
        await res.addStream(body);
      }
      await res.close();
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  static Stream<List<int>> _throttle(Stream<List<int>> src, int bps) async* {
    final Stopwatch sw = Stopwatch()..start();
    int sent = 0;
    await for (final List<int> c in src) {
      for (int i = 0; i < c.length; i += 4096) {
        final List<int> part = c.sublist(i, math.min(c.length, i + 4096));
        sent += part.length;
        final int due = (sent * 1000 / bps).round() - sw.elapsedMilliseconds;
        if (due > 0) await Future<void>.delayed(Duration(milliseconds: due));
        yield part;
      }
    }
  }
}
