import 'cinema_api.dart';

/// Cartoon catalog — Cinemeta filtered to the `Animation` genre.
///
/// Cinemeta's catalogs cover all of IMDb, and `genre=Animation` gives the
/// western-cartoon catalogue (plus anime crossover titles that share the
/// genre). Rows are the same endpoint shapes verified in [CinemaApi]; the
/// only additions are the `imdbRating` catalogs and a client-side genre
/// filter for searches (Cinemeta ignores `genre` extras on `search=`).
class CartoonApi {
  CartoonApi._();
  static final CartoonApi I = CartoonApi._();

  final CinemaApi _api = CinemaApi.I;

  /// Trending animated movies.
  Future<List<CinemaItem>> trending({int skip = 0}) =>
      _api.byGenre('movie', 'Animation', skip: skip);

  /// Popular animated series.
  Future<List<CinemaItem>> popularSeries({int skip = 0}) =>
      _api.byGenre('series', 'Animation', skip: skip);

  /// Top-rated animated movies (IMDb rank catalog).
  Future<List<CinemaItem>> topMovies({int skip = 0}) =>
      _api.byGenre('movie', 'Animation', skip: skip);

  /// Top-rated animated series.
  Future<List<CinemaItem>> topSeries({int skip = 0}) =>
      _api.byGenre('series', 'Animation', skip: skip);

  /// Best-rated animation, movies and series merged and interleaved.
  Future<List<CinemaItem>> bestRated({int skip = 0}) async {
    final List<List<CinemaItem>> lists = await Future.wait(<Future<List<CinemaItem>>>[
      _api.ratingByGenre('movie', 'Animation', skip: skip),
      _api.ratingByGenre('series', 'Animation', skip: skip),
    ]);
    final List<CinemaItem> out = <CinemaItem>[];
    final int maxLen = lists
        .map((List<CinemaItem> l) => l.length)
        .fold(0, (int a, int b) => a > b ? a : b);
    for (int i = 0; i < maxLen; i++) {
      for (final List<CinemaItem> l in lists) {
        if (i < l.length) out.add(l[i]);
      }
    }
    return out;
  }

  /// Keyword search restricted to animated titles (client-side genre filter;
  /// Cinemeta ignores the genre extra on searches). Falls back to unfiltered
  /// results when the filter empties the page entirely.
  Future<List<CinemaItem>> search(String query) async {
    final List<CinemaItem> raw = await _api.search(query);
    final List<CinemaItem> animated = raw
        .where((CinemaItem it) =>
            it.genres.any((String g) => g.toLowerCase() == 'animation'))
        .toList();
    return animated.length >= 3 || raw.isEmpty ? animated : raw;
  }
}
