import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import 'calendar_tab.dart';
import 'egy_tab.dart';
import 'hentai_tab.dart';
import 'home_tab.dart';
import 'profile_tab.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const List<({IconData icon, String label})> _tabs = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.calendar_month_rounded, label: 'Calendar'),
    (icon: Icons.live_tv_rounded, label: 'EgyDead'),
    (icon: Icons.eighteen_up_rating_rounded, label: '18+'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        return Scaffold(
          body: IndexedStack(
            index: state.navIndex,
            children: const [
              HomeTab(),
              CalendarTab(),
              EgyTab(),
              HentaiTab(),
              ProfileTab(),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: AppColors.bg,
              border: Border(top: BorderSide(color: AppColors.stroke)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: List<Widget>.generate(_tabs.length, (int i) {
                    final bool active = state.navIndex == i;
                    return Expanded(
                      child: InkWell(
                        onTap: () => state.setTab(i),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_tabs[i].icon,
                                size: 23,
                                color: active
                                    ? (i == 2
                                        ? const Color(0xFFE50914)
                                        : AppColors.green)
                                    : AppColors.muted),
                            const SizedBox(height: 5),
                            Text(
                              _tabs[i].label,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10.5,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: active
                                    ? (i == 2
                                        ? const Color(0xFFE50914)
                                        : AppColors.green)
                                    : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
