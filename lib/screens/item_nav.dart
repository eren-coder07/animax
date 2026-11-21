import 'package:flutter/material.dart';

import '../core/akwam_api.dart';
import '../core/api_html.dart' show AnimeWatchId;
import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/manga_api.dart';

/// Opens the details page of a community item (`kind` + its key part):
/// Akwam page path, anime id or MangaDex id.
Future<void> openItem(
  BuildContext context, {
  required String kind,
  required String ref,
  String title = '',
  String poster = '',
}) async {
  final NavigatorState nav = Navigator.of(context);
  final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);
  void fail() => msg.showSnackBar(
    const SnackBar(content: Text('تعذّر فتح هذا العنوان حاليًا.')),
  );
  switch (kind) {
    case 'akwam':
      final AkwamItem? it = AkwamApi.itemFromPath(
        ref,
        title: title,
        poster: poster,
      );
      if (it == null) return fail();
      await nav.pushNamed('/akwam-details', arguments: it);
    case 'anime':
      Anime? a;
      for (final Anime x in AppState.I.catalog) {
        if (x.id == ref || x.slug == ref || x.watchId == ref) {
          a = x;
          break;
        }
      }
      await nav.pushNamed(
        '/details',
        arguments:
            a ??
            Anime(
              id: ref,
              title: title,
              poster: poster,
              score: 0,
              year: '',
              genres: const <String>[],
              synopsis: '',
              slug: ref,
            ),
      );
    case 'manga':
      try {
        final MangaItem m = await MangaApi.I.details(ref);
        await nav.pushNamed('/comic-details', arguments: m);
      } catch (_) {
        fail();
      }
    default:
      fail();
  }
}
