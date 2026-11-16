import 'package:flutter/material.dart';

import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
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
          listenable: state,
          builder: (BuildContext context, _) {
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
                  const Text('Notification', style: AppText.h3),
                  const Spacer(),
                  Text('09/05/2026',
                      style: AppText.label.copyWith(fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All notifications marked as read'))),
                child: Text('Mark all as read',
                    style: AppText.bodyBold
                        .copyWith(color: AppColors.accent, fontSize: 12)),
              ),
            ),
            Expanded(
              child: state.notices.isEmpty
                  ? const EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'No notifications',
                      message: 'New episode alerts will show up here.',
                    )
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
                                      ? 'Now streaming'
                                      : 'Episode ${n.episode}',
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
                            child: Text('Updates',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
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
