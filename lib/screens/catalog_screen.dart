import 'package:flutter/material.dart';

import '../core/app_data.dart';
import '../core/app_theme.dart';
import '../widgets/cards.dart';

/// Full-title grid behind every "See all" button.
///
/// Arguments: a `(String title, List<Anime> items)` record.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Object? args = ModalRoute.of(context)!.settings.arguments;
    final String title;
    final List<Anime> items;
    if (args is (String, List<Anime>)) {
      title = args.$1;
      items = args.$2;
    } else if (args is String) {
      title = args;
      items = const <Anime>[];
    } else {
      title = 'تصفّح';
      items = const <Anime>[];
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.text),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.h3.copyWith(fontSize: 16)),
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.movie_filter_rounded,
                        color: AppColors.muted, size: 40),
                    const SizedBox(height: 12),
                    Text('لا شيء هنا بعد',
                        style: AppText.bodyBold.copyWith(fontSize: 14)),
                    const SizedBox(height: 6),
                    Text('هذه القائمة فارغة حاليًا.',
                        textAlign: TextAlign.center,
                        style: AppText.label.copyWith(fontSize: 11.5)),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.52,
                ),
                itemCount: items.length,
                itemBuilder: (BuildContext context, int i) =>
                    PosterCard(anime: items[i]),
              ),
            ),
    );
  }
}
