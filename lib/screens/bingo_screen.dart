import 'package:flutter/material.dart';

import '../core/app_prefs.dart';
import '../core/app_theme.dart';
import '../core/cloud.dart';
import '../core/social.dart';
import '../widgets/mb_ui.dart';
import 'auth_screen.dart';

/// Watch Bingo: a 3×3 card of goals across the app. Complete a row,
/// column or diagonal for a "BINGO"; fill the card to win a round.
/// Also hosts the Binge (marathon) mode switch and the session streak.
class BingoScreen extends StatelessWidget {
  const BingoScreen({super.key});

  static const Map<String, IconData> _icons = <String, IconData>{
    'movie': Icons.movie_rounded,
    'anime': Icons.animation_rounded,
    'cartoon': Icons.child_care_rounded,
    'menu_book': Icons.menu_book_rounded,
    'favorite': Icons.favorite_rounded,
    'chat': Icons.chat_bubble_rounded,
    'content_cut': Icons.content_cut_rounded,
    'person_add': Icons.person_add_alt_1_rounded,
    'bolt': Icons.bolt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(backgroundColor: AppColors.bg, title: const Text('بينغو المشاهدة')),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          BingoStore.I,
          BingeStore.I,
          CloudAuth.I,
          AppPrefs.I,
        ]),
        builder: (BuildContext context, _) {
          final BingoStore b = BingoStore.I;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
            children: <Widget>[
              if (!CloudAuth.I.signedIn)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: <Widget>[
                      const Text('سجّل الدخول لحفظ تقدمك في البينغو',
                          style: TextStyle(
                              fontFamily: kFont, fontSize: 15, color: Colors.white)),
                      const SizedBox(height: 10),
                      GradientButton(
                          label: 'تسجيل الدخول',
                          height: 42,
                          onTap: () => requireLogin(context)),
                    ],
                  ),
                ),
              Row(
                children: <Widget>[
                  _stat('${b.done.length}/9', 'أهداف'),
                  _stat('${b.lineCount}', 'بينغو'),
                  _stat('${BingeStore.I.session}', 'ماراثون'),
                ],
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.9,
                children: <Widget>[
                  for (final BingoGoal g in BingoGoal.values)
                    _Cell(
                      goal: g,
                      icon: _icons[g.icon] ?? Icons.star_rounded,
                      done: b.done.contains(g),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (b.full)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGrad,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: <Widget>[
                      const Text('🎉 أكملت البطاقة كاملة!',
                          style: TextStyle(
                              fontFamily: kFont,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF07130D))),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => BingoStore.I.reset(),
                        child: const Text('ابدأ جولة جديدة',
                            style: TextStyle(
                                fontFamily: kFont,
                                fontSize: 15,
                                color: Color(0xFF07130D))),
                      ),
                    ],
                  ),
                )
              else
                const Text(
                    'أكمل صفًا أو عمودًا أو قطرًا لتحصل على «بينغو». تُسجَّل الأهداف تلقائيًا أثناء استخدامك للتطبيق.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: kFont, fontSize: 13.5, height: 1.6, color: AppColors.sub)),
              const SizedBox(height: 22),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  value: AppPrefs.I.bingeMode,
                  onChanged: (bool v) => AppPrefs.I.set('bingeMode', v),
                  secondary: const Icon(Icons.bolt_rounded,
                      color: AppColors.star, size: 30),
                  title: const Text('وضع الماراثون',
                      style: TextStyle(
                          fontFamily: kFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  subtitle: const Text(
                      'تشغيل الحلقة التالية تلقائيًا بعد 5 ثوانٍ وتخطي المقدمات وعدّ الحلقات المتتالية',
                      style: TextStyle(
                          fontFamily: kFont, fontSize: 12.5, color: AppColors.sub)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String n, String label) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: <Widget>[
              Text(n,
                  style: const TextStyle(
                      fontFamily: kFont,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandGreen)),
              Text(label,
                  style: const TextStyle(
                      fontFamily: kFont, fontSize: 13, color: AppColors.sub)),
            ],
          ),
        ),
      );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.goal, required this.icon, required this.done});
  final BingoGoal goal;
  final IconData icon;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: done ? AppColors.brandGrad : null,
        color: done ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: done ? Colors.transparent : AppColors.stroke),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(done ? Icons.check_circle_rounded : icon,
              size: 30, color: done ? const Color(0xFF07130D) : Colors.white),
          const SizedBox(height: 6),
          Text(goal.label,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: kFont,
                  fontSize: 12,
                  height: 1.3,
                  color: done ? const Color(0xFF07130D) : AppColors.sub)),
        ],
      ),
    );
  }
}
