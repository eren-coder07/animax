import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Pure HLS playlist parsing + AES-128 helpers used by the downloader.
///
/// Kept free of I/O so it can be unit-tested against captured playlists.

/// One `#EXT-X-STREAM-INF` entry of a master playlist.
class HlsStreamVariant {
  const HlsStreamVariant({
    required this.uri,
    required this.bandwidth,
    this.height = 0,
    this.audioGroup = '',
  });

  final Uri uri;
  final int bandwidth;
  final int height;

  /// `AUDIO="…"` group id; empty when audio is muxed into the variant.
  final String audioGroup;
}

/// One `#EXT-X-MEDIA:TYPE=AUDIO` rendition.
class HlsAudioRendition {
  const HlsAudioRendition({
    required this.groupId,
    required this.uri,
    this.isDefault = false,
    this.language = '',
  });

  final String groupId;
  final Uri uri;
  final bool isDefault;
  final String language;
}

class HlsMaster {
  const HlsMaster(this.variants, this.audio);

  final List<HlsStreamVariant> variants;
  final List<HlsAudioRendition> audio;

  /// Highest-bandwidth variant (optionally capped at [maxHeight]).
  HlsStreamVariant? best({int maxHeight = 0}) {
    final List<HlsStreamVariant> pool = maxHeight <= 0
        ? variants
        : variants
            .where((HlsStreamVariant v) => v.height == 0 || v.height <= maxHeight)
            .toList();
    final List<HlsStreamVariant> src = pool.isEmpty ? variants : pool;
    if (src.isEmpty) return null;
    return (List<HlsStreamVariant>.of(src)
          ..sort((HlsStreamVariant a, HlsStreamVariant b) =>
              b.bandwidth - a.bandwidth))
        .first;
  }

  /// The audio rendition [variant] needs (default one of its group), if any.
  HlsAudioRendition? audioFor(HlsStreamVariant variant) {
    if (variant.audioGroup.isEmpty) return null;
    final List<HlsAudioRendition> group = audio
        .where((HlsAudioRendition a) => a.groupId == variant.audioGroup)
        .toList();
    if (group.isEmpty) return null;
    return group.firstWhere((HlsAudioRendition a) => a.isDefault,
        orElse: () => group.first);
  }
}

/// `#EXT-X-KEY` state applying to a segment.
class HlsKey {
  const HlsKey({required this.method, this.uri, this.iv});

  /// `NONE`, `AES-128` or `SAMPLE-AES`.
  final String method;
  final Uri? uri;

  /// Explicit IV (16 bytes) or null → derive from the media sequence number.
  final Uint8List? iv;

  bool get isEncrypted => method != 'NONE';
}

class HlsByteRange {
  const HlsByteRange(this.length, this.offset);
  final int length;
  final int offset;

  String get header => 'bytes=$offset-${offset + length - 1}';
}

class HlsSegment {
  const HlsSegment({
    required this.uri,
    required this.sequence,
    this.duration = 0,
    this.key,
    this.range,
  });

  final Uri uri;
  final int sequence;
  final double duration;
  final HlsKey? key;
  final HlsByteRange? range;
}

class HlsMediaPlaylist {
  const HlsMediaPlaylist({
    required this.segments,
    this.initUri,
    this.initRange,
    this.initKey,
  });

  final List<HlsSegment> segments;

  /// `#EXT-X-MAP` init section (fMP4 streams).
  final Uri? initUri;
  final HlsByteRange? initRange;
  final HlsKey? initKey;

  bool get isFragmentedMp4 => initUri != null;

  double get totalSeconds =>
      segments.fold<double>(0, (double s, HlsSegment x) => s + x.duration);
}

class HlsParser {
  HlsParser._();

  static bool isMaster(String body) => body.contains('#EXT-X-STREAM-INF');

  /// Attribute list → map (quote-aware, keys upper-cased).
  static Map<String, String> attrs(String raw) {
    final Map<String, String> out = <String, String>{};
    final StringBuffer cur = StringBuffer();
    bool inQuote = false;
    void flush() {
      final String chunk = cur.toString();
      cur.clear();
      final int eq = chunk.indexOf('=');
      if (eq <= 0) return;
      String v = chunk.substring(eq + 1).trim();
      if (v.length > 1 && v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1);
      }
      out[chunk.substring(0, eq).trim().toUpperCase()] = v;
    }

    for (int i = 0; i < raw.length; i++) {
      final String ch = raw[i];
      if (ch == '"') inQuote = !inQuote;
      if (ch == ',' && !inQuote) {
        flush();
      } else {
        cur.write(ch);
      }
    }
    flush();
    return out;
  }

  static List<String> _lines(String body) => body
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();

  static HlsMaster parseMaster(String body, Uri base) {
    final List<HlsStreamVariant> variants = <HlsStreamVariant>[];
    final List<HlsAudioRendition> audio = <HlsAudioRendition>[];
    final List<String> lines = _lines(body);
    for (int i = 0; i < lines.length; i++) {
      final String l = lines[i];
      if (l.startsWith('#EXT-X-MEDIA:')) {
        final Map<String, String> a = attrs(l.substring(13));
        if ((a['TYPE'] ?? '').toUpperCase() != 'AUDIO') continue;
        final String? u = a['URI'];
        if (u == null || u.isEmpty) continue; // muxed into the variant
        audio.add(HlsAudioRendition(
          groupId: a['GROUP-ID'] ?? '',
          uri: base.resolve(u),
          isDefault: (a['DEFAULT'] ?? '').toUpperCase() == 'YES',
          language: a['LANGUAGE'] ?? '',
        ));
      } else if (l.startsWith('#EXT-X-STREAM-INF:')) {
        final Map<String, String> a = attrs(l.substring(18));
        String? next;
        for (int j = i + 1; j < lines.length; j++) {
          if (!lines[j].startsWith('#')) {
            next = lines[j];
            i = j;
            break;
          }
        }
        if (next == null) continue;
        int h = 0;
        final RegExpMatch? m =
            RegExp(r'^(\d+)x(\d+)$').firstMatch(a['RESOLUTION'] ?? '');
        if (m != null) h = int.tryParse(m.group(2)!) ?? 0;
        variants.add(HlsStreamVariant(
          uri: base.resolve(next),
          bandwidth: int.tryParse(a['BANDWIDTH'] ?? '') ?? 0,
          height: h,
          audioGroup: a['AUDIO'] ?? '',
        ));
      }
    }
    return HlsMaster(variants, audio);
  }

  static HlsByteRange? _range(String spec, int fallbackOffset) {
    final List<String> p = spec.split('@');
    final int? len = int.tryParse(p[0].trim());
    if (len == null) return null;
    final int off = p.length > 1
        ? (int.tryParse(p[1].trim()) ?? fallbackOffset)
        : fallbackOffset;
    return HlsByteRange(len, off);
  }

  static Uint8List? _hexIv(String? raw) {
    if (raw == null) return null;
    String h = raw.trim();
    if (h.startsWith('0x') || h.startsWith('0X')) h = h.substring(2);
    if (h.isEmpty) return null;
    h = h.padLeft(32, '0');
    final Uint8List out = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static HlsMediaPlaylist parseMedia(String body, Uri base) {
    final List<HlsSegment> segs = <HlsSegment>[];
    Uri? initUri;
    HlsByteRange? initRange;
    HlsKey? initKey;
    HlsKey? key;
    int seq = 0;
    double dur = 0;
    HlsByteRange? pendingRange;
    int nextOffset = 0;
    for (final String l in _lines(body)) {
      if (l.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        seq = int.tryParse(l.substring(22).trim()) ?? 0;
      } else if (l.startsWith('#EXT-X-KEY:')) {
        final Map<String, String> a = attrs(l.substring(11));
        final String method = (a['METHOD'] ?? 'NONE').toUpperCase();
        key = method == 'NONE'
            ? null
            : HlsKey(
                method: method,
                uri: a['URI'] == null ? null : base.resolve(a['URI']!),
                iv: _hexIv(a['IV']),
              );
      } else if (l.startsWith('#EXT-X-MAP:')) {
        final Map<String, String> a = attrs(l.substring(11));
        final String? u = a['URI'];
        if (u != null) initUri = base.resolve(u);
        if (a['BYTERANGE'] != null) initRange = _range(a['BYTERANGE']!, 0);
        initKey = key;
      } else if (l.startsWith('#EXTINF:')) {
        final String v = l.substring(8).split(',').first.trim();
        dur = double.tryParse(v) ?? 0;
      } else if (l.startsWith('#EXT-X-BYTERANGE:')) {
        pendingRange = _range(l.substring(17), nextOffset);
      } else if (!l.startsWith('#')) {
        segs.add(HlsSegment(
          uri: base.resolve(l),
          sequence: seq,
          duration: dur,
          key: key,
          range: pendingRange,
        ));
        if (pendingRange != null) {
          nextOffset = pendingRange.offset + pendingRange.length;
        }
        pendingRange = null;
        dur = 0;
        seq++;
      }
    }
    return HlsMediaPlaylist(
        segments: segs, initUri: initUri, initRange: initRange, initKey: initKey);
  }

  /// IV per RFC 8216 §5.2: explicit IV, else the sequence number as a
  /// 128-bit big-endian integer.
  static Uint8List ivFor(HlsKey key, int sequence) {
    if (key.iv != null) return key.iv!;
    final Uint8List iv = Uint8List(16);
    int s = sequence;
    for (int i = 15; i >= 8 && s > 0; i--) {
      iv[i] = s & 0xff;
      s >>= 8;
    }
    return iv;
  }

  /// AES-128-CBC + PKCS7 decrypt of one segment.
  static Uint8List decryptAes128(Uint8List data, Uint8List key, Uint8List iv) {
    final PaddedBlockCipherImpl cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    )..init(
        false,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
          null,
        ),
      );
    return cipher.process(data);
  }
}
