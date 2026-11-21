import 'package:animax/core/app_prefs.dart';
import 'package:animax/core/app_state.dart';
import 'package:animax/screens/comic_tab.dart';
import 'package:animax/screens/hentai_tab.dart';
import 'package:animax/screens/home_shell.dart';
import 'package:animax/screens/home_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('category bar switches the Home section', (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppPrefs.I.set('lastSeenVersion', '2.4.1');
    AppState.I.setCategory(0);
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(const MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl, child: HomeShell())));
    await t.pump(const Duration(milliseconds: 200));

    // Only labels of the remaining sections — Cinema and Calendar are gone.
    expect(find.text('أجنبي'), findsNothing);
    expect(find.text('التقويم'), findsNothing);

    Future<void> tapCategory(String label) async {
      final Finder bar = find.descendant(
          of: find.byKey(const Key('categoryBar')),
          matching: find.byType(Scrollable));
      await t.scrollUntilVisible(find.text(label), 80, scrollable: bar);
      await t.ensureVisible(find.text(label));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text(label));
    }

    await tapCategory('مانغا');
    await t.pump(const Duration(milliseconds: 200));
    expect(AppState.I.homeCategory, 6);
    expect(find.byType(ComicTab), findsOneWidget);

    await tapCategory('أنمي');
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(HomeTab), findsOneWidget);

    await tapCategory('+18');
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(HentaiTab), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
