import 'package:flutter/material.dart';

import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/akwam_api.dart';
import '../core/app_theme.dart';
import '../core/episode_alerts.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[state, EpisodeAlerts.I]),
          builder: (BuildContext context, _) {
            final DateTime today = DateTime.now();
            final List<EpisodeAlert> alerts = EpisodeAlerts.I.alerts;
            return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  IconBubble(Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  const Text('الإشعارات', style: AppText.h3),
                  const Spacer(),
                  Text(
                      '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}',
                      style: AppText.label.copyWith(fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: () {
                  EpisodeAlerts.I.clear();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('تم تعليم كل الإشعارات كمقروءة')));
                },
                child: Text('تعليم الكل كمقروء',
                    style: AppText.bodyBold
                        .copyWith(color: AppColors.accent, fontSize: 12)),
              ),
            ),
            if (alerts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('حلقات جديدة من قائمتي',
                        style: AppText.bodyBold.copyWith(fontSize: 14)),
                    const SizedBox(height: 8),
                    for (final EpisodeAlert a in alerts.take(6))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            key: ValueKey<String>('alert:${a.key}'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              final AkwamItem? it = AkwamApi.itemFromPath(a.path,
                                  title: a.title, poster: a.poster);
                              EpisodeAlerts.I.dismiss(a);
                              if (it != null) {
                                Navigator.pushNamed(context, '/akwam-details',
                                    arguments: it);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: <Widget>[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 50,
                                      height: 70,
                                      child: a.poster.isEmpty
                                          ? const ColoredBox(color: Colors.black26)
                                          : Image.network(a.poster,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const ColoredBox(color: Colors.black26)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(a.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppText.bodyBold.copyWith(fontSize: 13)),
                                        const SizedBox(height: 4),
                                        Text('🆕 الحلقة ${a.episode} متاحة الآن',
                                            style: AppText.label.copyWith(
                                                fontSize: 12, color: AppColors.accent)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'إخفاء',
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18, color: AppColors.muted),
                                    onPressed: () => EpisodeAlerts.I.dismiss(a),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: state.notices.isEmpty && alerts.isEmpty
                  ? const EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'لا توجد إشعارات',
                      message: 'ستظهر تنبيهات الحلقات الجديدة هنا.',
                    )
                  : state.notices.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                      itemCount: state.notices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (BuildContext context, int i) {
                        final Notice n = state.notices[i];
                  return GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/details',
                        arguments: n.anime),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 86,
                            height: 60,
                            child: PosterImage(anime: n.anime, radius: 10),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.anime.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.bodyBold.copyWith(fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(
                                  n.anime.isMovie
                                      ? 'يُعرض الآن'
                                      : 'الحلقة ${n.episode}',
                                  style: AppText.label.copyWith(fontSize: 11),
                                ),
                                const SizedBox(height: 5),
                                Text(n.when,
                                    style: AppText.label.copyWith(fontSize: 10)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text('التحديثات',
                                style: TextStyle(
                                    fontFamily: 'Plex',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent)),
                          ),
                        ],
                      ),
                    ),
                  );
                      },
                    ),
            ),
          ],
            );
          },
        ),
      ),
    );
  }
}
