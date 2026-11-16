import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
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
    final String host = ApiService.I.config.cleanBase;
    return SafeArea(
      child: ListenableBuilder(
        listenable: state,
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
                    border: Border.all(color: AppColors.green, width: 2),
                  ),
                  child: const Center(child: AnimaxLogo(size: 46)),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                  child: Text('Animax Viewer',
                      style: AppText.h3.copyWith(fontSize: 18))),
              const SizedBox(height: 4),
              Center(
                child: Text(host.isEmpty
                    ? 'No backend configured'
                    : 'Watching via $host',
                    style: AppText.label),
              ),
              const SizedBox(height: 22),
              _StatusCard(state: state),
              const SizedBox(height: 22),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    MenuRow(
                      icon: Icons.notifications_none_rounded,
                      label: 'Notifications',
                      trailing: state.notices.isEmpty
                          ? null
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${state.notices.length}',
                                  style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.green)),
                            ),
                      onTap: () => Navigator.pushNamed(context, '/notifications'),
                    ),
                    const Divider(indent: 54),
                    MenuRow(
                      icon: Icons.dns_rounded,
                      label: 'API Backend',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: state.isConnected
                              ? AppColors.green.withValues(alpha: 0.15)
                              : AppColors.surfaceHi,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(state.backendChip,
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: state.isConnected
                                    ? AppColors.green
                                    : AppColors.sub)),
                      ),
                      onTap: () => Navigator.pushNamed(context, '/backend'),
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
                  'This build uses only the features the backend API provides — '
                  'browsing, episode playback and the release schedule.',
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
                ? AppColors.green.withValues(alpha: 0.5)
                : bad
                    ? Colors.red.withValues(alpha: 0.4)
                    : AppColors.stroke),
      ),
      child: Row(
        children: [
          if (syncing)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  color: AppColors.green, strokeWidth: 2.4),
            )
          else
            Icon(
              live
                  ? Icons.verified_rounded
                  : bad
                      ? Icons.cloud_off_rounded
                      : Icons.explore_rounded,
              color: live
                  ? AppColors.green
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
                      ? 'Connected to the backend'
                      : syncing
                          ? 'Syncing…'
                          : 'Not connected',
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
