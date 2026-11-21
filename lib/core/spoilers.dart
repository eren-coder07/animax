import 'api_html.dart' show watchIdOf;
import 'app_prefs.dart';
import 'cloud.dart';
import 'library_store.dart';
import 'social.dart';

/// Spoiler shield ("درع الحرق"): a clip from episode N of a series is
/// hidden behind a blur until you reveal it when your own furthest started
/// episode of that series is below N - 1 (watching the next episode is
/// fine). Your own clips and movie clips are never blurred.
class Spoilers {
  Spoilers._();

  static final Set<String> _revealed = <String>{};

  static void reveal(String clipId) => _revealed.add(clipId);

  static bool hides(VideoClip c) {
    if (!AppPrefs.I.spoilerShield || _revealed.contains(c.id)) return false;
    if (c.uid.isNotEmpty && c.uid == CloudAuth.I.user?.uid) return false;
    final int ep = c.episode;
    if (ep <= 1) return false;
    return ep > furthestEpisode(c) + 1;
  }

  /// Highest episode of the clip's series you started or finished (0 = none).
  static int furthestEpisode(VideoClip c) {
    final bool Function(String key) same = _matcher(c);
    int best = 0;
    for (final ProgressEntry p in LibraryStore.I.allProgress) {
      if (!same(p.key)) continue;
      if (p.positionSec <= 0 && !p.watched) continue;
      final int n = int.tryParse(p.sub) ?? 0;
      if (n > best) best = n;
    }
    return best;
  }

  /// Does a progress key (`akwam:/series/…`, `anime:{id}`, `hh:{slug}`)
  /// belong to the clip's series?
  static bool Function(String key) _matcher(VideoClip c) {
    switch (c.source) {
      case 'akwam':
        final String item = c.ref['item'] ?? '';
        if (item.isNotEmpty) return (String k) => k == 'akwam:$item';
        // Old clips: /watch/{file}/{id}/{series-slug}/{episode-slug}.
        final RegExpMatch? m = RegExp(r'^/watch/\d+/\d+/([^/?#]+)/')
            .firstMatch(c.ref['path'] ?? '');
        if (m == null) return (String _) => false;
        final String slug = _dec(m.group(1)!);
        return (String k) {
          if (!k.startsWith('akwam:')) return false;
          final List<String> seg = k.substring(6).split('/');
          return seg.length >= 4 &&
              (seg[1] == 'series' || seg[1] == 'show') &&
              _dec(seg[3]) == slug;
        };
      case 'anime':
        final String wid = c.ref['watchId'] ?? '';
        return (String k) =>
            k.startsWith('anime:') && watchIdOf(k.substring(6)) == wid;
      case 'hh':
        final String slug = c.ref['slug'] ?? '';
        return (String k) => k == 'hh:$slug';
    }
    return (String _) => false;
  }

  static String _dec(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }
}
