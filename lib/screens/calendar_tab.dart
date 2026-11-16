import 'package:flutter/material.dart';

import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/animax_logo.dart';

/// Release Calendar — real airing schedule from the backend
/// (`/ajax/schedule/date`), keyed by calendar day.
class CalendarTab extends StatelessWidget {
  const CalendarTab({super.key});

  static const List<String> _weekdays = [
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
  ];

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return SafeArea(
      child: ListenableBuilder(
        listenable: state,
        builder: (BuildContext context, _) {
          final DateTime today =
              DateTime(state.selectedDate.year, state.selectedDate.month,
                  state.selectedDate.day);
          final List<DateTime> week = <DateTime>[
            for (int i = 0; i < 7; i++) today.add(Duration(days: i)),
          ];
          final List<CalendarEntry> entries = state.entriesFor(today);
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const AnimaxLogo(size: 34, withWordmark: true),
                    const Spacer(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Center(child: Text('Release Calendar', style: AppText.h2)),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  state.scheduleLive
                      ? 'Airing schedule from the backend'
                      : 'Derived from episode air dates',
                  style: AppText.label.copyWith(fontSize: 11),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: List<Widget>.generate(week.length, (int i) {
                    final DateTime day = week[i];
                    final bool selected =
                        state.selectedDate.year == day.year &&
                            state.selectedDate.month == day.month &&
                            state.selectedDate.day == day.day;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => state.selectDate(day),
                        child: Column(
                          children: [
                            Text(_weekdays[day.weekday % 7],
                                style: AppText.label.copyWith(
                                    color: selected
                                        ? AppColors.green
                                        : AppColors.muted,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Container(
                              width: 40,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.green
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? AppColors.ink
                                      : AppColors.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 26),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: EmptyState(
                    icon: Icons.event_busy_rounded,
                    title: 'Nothing airs today',
                    message:
                        'Pick another day to see upcoming simulcast episodes.',
                  ),
                )
              else
                ...List<Widget>.generate(entries.length, (int i) {
                  final CalendarEntry e = entries[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 46,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(e.time,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.text)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                    left: BorderSide(
                                        color: AppColors.green, width: 2)),
                              ),
                              padding: const EdgeInsets.only(left: 16),
                              margin: const EdgeInsets.only(left: 2),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    left: -7,
                                    top: 18,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: AppColors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: AppColors.bg, width: 2.5),
                                      ),
                                    ),
                                  ),
                                  _CalendarCard(entry: e),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.entry});

  final CalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/details', arguments: entry.anime),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 64,
              child: PosterImage(anime: entry.anime, radius: 10),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.anime.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyBold.copyWith(fontSize: 13)),
                  const SizedBox(height: 3),
                  Text('Episode ${entry.episode}',
                      style: AppText.label.copyWith(fontSize: 11)),
                  const SizedBox(height: 8),
                  GhostChip(
                    label: 'Watch',
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    onTap: () => Navigator.pushNamed(
                        context, '/details', arguments: entry.anime),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
