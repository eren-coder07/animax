import 'package:flutter/material.dart';

import '../core/app_prefs.dart';
import '../core/app_theme.dart';
import '../core/data_budget.dart';
import 'mb_ui.dart' show kFont;

/// Settings card: monthly mobile-data budget picker + this month's usage.
class DataBudgetCard extends StatelessWidget {
  const DataBudgetCard({super.key});

  static const Map<int, String> options = <int, String>{
    0: 'بدون حد',
    500: '500 م.ب',
    1024: '1 ج.ب',
    2048: '2 ج.ب',
    5120: '5 ج.ب',
    10240: '10 ج.ب',
    20480: '20 ج.ب',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[DataBudget.I, AppPrefs.I]),
      builder: (BuildContext context, _) {
        final DataBudget b = DataBudget.I;
        final double f = b.fraction.clamp(0.0, 1.0);
        final Color barColor = b.over
            ? const Color(0xFFFF4D4D)
            : b.nearLimit
            ? const Color(0xFFFFB020)
            : AppColors.brandGreen;
        return Container(
          key: const Key('dataBudgetCard'),
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.data_usage_rounded,
                    color: AppColors.brandGreen,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'ميزانية بيانات الجوال الشهرية',
                      style: TextStyle(
                        fontFamily: kFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  DropdownButton<int>(
                    key: const Key('dataBudgetPicker'),
                    value: options.containsKey(b.budgetMb) ? b.budgetMb : 0,
                    dropdownColor: AppColors.surface,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(
                      fontFamily: kFont,
                      color: Colors.white,
                    ),
                    items: <DropdownMenuItem<int>>[
                      for (final MapEntry<int, String> e in options.entries)
                        DropdownMenuItem<int>(
                          value: e.key,
                          child: Text(e.value),
                        ),
                    ],
                    onChanged: (int? v) {
                      if (v == null) return;
                      AppPrefs.I.set('dataBudgetMb', v);
                      b.overrideThisSession = false;
                      b.sample();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                b.enabled
                    ? 'استهلكت ${DataBudget.fmtMb(b.usedMb)} من ${DataBudget.fmtMb(b.budgetMb.toDouble())} هذا الشهر'
                    : 'استهلاك التطبيق على بيانات الجوال هذا الشهر: ${DataBudget.fmtMb(b.usedMb)}',
                style: const TextStyle(
                  fontFamily: kFont,
                  fontSize: 13,
                  color: AppColors.sub,
                ),
              ),
              if (b.enabled) ...<Widget>[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: f,
                    minHeight: 8,
                    color: barColor,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  b.over
                      ? 'تجاوزت الحد: التحميلات تنتظر Wi-Fi والمشغّل يسألك قبل استخدام البيانات.'
                      : b.nearLimit
                      ? 'اقتربت من الحد: تم تفعيل وضع البيانات المنخفضة تلقائيًا (أقل جودة).'
                      : 'عند 80% يُفعَّل وضع البيانات المنخفضة، وعند 100% يتوقف الاستهلاك حتى تسمح به.',
                  style: TextStyle(
                    fontFamily: kFont,
                    fontSize: 12,
                    height: 1.5,
                    color: b.nearLimit ? barColor : AppColors.muted,
                  ),
                ),
              ],
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: b.resetMonth,
                  child: const Text(
                    'تصفير العدّاد',
                    style: TextStyle(fontFamily: kFont, color: AppColors.sub),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
