import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/library_store.dart';
import '../widgets/common.dart';
import '../widgets/animax_logo.dart';

/// Profile tab — only what the backend actually provides: connection state,
/// release notifications and the API backend configuration. Account-gated
/// features (sign-in, downloads, premium) are not part of the API and are
/// therefore not in the app.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[state, LibraryStore.I]),
        builder: (BuildContext context, _) {
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
            children: [
              const Center(child: Text('Profile', style: AppText.h2)),
              const SizedBox(height: 22),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.accent, width: 2),
                  ),
                  child: const Center(child: AnimaxLogo(size: 46)),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                  child: Text('Animax Viewer',
                      style: AppText.h3.copyWith(fontSize: 18))),
              const SizedBox(height: 4),
              const Center(
                  child: Text('Anime · Cinema · Cartoons · Comics',
                      style: AppText.label)),
              const SizedBox(height: 22),
              _StatusCard(state: state),
              const SizedBox(height: 22),
              _StatsStrip(),
              const SizedBox(height: 22),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    MenuRow(
                      icon: Icons.video_library_rounded,
                      label: 'My Library (List · History · Stats)',
                      onTap: () => Navigator.pushNamed(context, '/library'),
                    ),
                    const Divider(indent: 54),
                    MenuRow(
                      icon: Icons.notifications_none_rounded,
                      label: 'Notifications',
                      trailing: state.notices.isEmpty
                          ? null
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${state.notices.length}',
                                  style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.accent)),
                            ),
                      onTap: () => Navigator.pushNamed(context, '/notifications'),
                    ),
                    const Divider(indent: 54),
                    MenuRow(
                      icon: Icons.settings_rounded,
                      label: 'Settings (theme · player · data)',
                      onTap: () => Navigator.pushNamed(context, '/settings'),
                    ),
                    const Divider(indent: 54),
                    MenuRow(
                      icon: Icons.help_outline_rounded,
                      label: 'Help Center',
                      onTap: () => Navigator.pushNamed(context, '/help'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'Anime, movies, series, cartoons and comics in one app — '
                  'everything streams from free, open backends.',
                  style: AppText.label.copyWith(fontSize: 10.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact stats strip (episodes watched / chapters read / hours streamed).
class _StatsStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final stats = LibraryStore.I.stats();
    Widget card(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Column(
              children: <Widget>[
                Text(value,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent)),
                const SizedBox(height: 2),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9.5,
                        color: AppColors.muted)),
              ],
            ),
          ),
        );
    return Row(
      children: <Widget>[
        card(stats.episodesWatched.toString(), 'Episodes\nwatched'),
        const SizedBox(width: 10),
        card(stats.chaptersRead.toString(), 'Chapters\nread'),
        const SizedBox(width: 10),
        card(stats.hoursWatched.toStringAsFixed(0), 'Hours\nstreamed'),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final bool live = state.isConnected;
    final bool syncing = state.isLoading;
    final bool bad = state.backendMode == BackendMode.offline;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: live
                ? AppColors.accent.withValues(alpha: 0.5)
                : bad
                    ? Colors.red.withValues(alpha: 0.4)
                    : AppColors.stroke),
      ),
      child: Row(
        children: [
          if (syncing)
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2.4),
            )
          else
            Icon(
              live
                  ? Icons.verified_rounded
                  : bad
                      ? Icons.cloud_off_rounded
                      : Icons.explore_rounded,
              color: live
                  ? AppColors.accent
                  : bad
                      ? Colors.redAccent
                      : AppColors.muted,
              size: 28,
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live
                      ? 'Content library up to date'
                      : syncing
                          ? 'Refreshing…'
                          : 'Offline — using cached content',
                  style: AppText.h3.copyWith(fontSize: 14.5),
                ),
                const SizedBox(height: 3),
                Text(
                  state.backendMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
