// Dynamic test of the real app on an Android emulator: first run with the
// starter template, an hourly rate, the plan with taxes, adding an expense
// and a purchase, and
// creating a household on the live Veilid network (QR invite). Also produces
// the README screenshots.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//                 --target=integration_test/app_test.dart
import 'package:finops_manager/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(
    WidgetTester t,
    Finder finder, {
    Duration timeout = const Duration(minutes: 4),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump();
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final onScreen = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .join(' | ');
    try {
      await binding.takeScreenshot('zz_failure');
    } on Object {
      // Best effort only.
    }
    throw TestFailure(
      'Timed out after $timeout waiting for $finder\nOn screen: $onScreen',
    );
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Finder nav(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('plan, expenses and a P2P household', (t) async {
    await app.main();
    await binding.convertFlutterSurfaceToImage();
    await pumpUntil(t, find.byKey(const Key('setup-name')));
    await binding.takeScreenshot('01_setup');

    await t.enterText(find.byKey(const Key('setup-name')), 'Anna');
    await settle(t);
    await t.tap(find.byKey(const Key('setup-done')));
    await pumpUntil(t, find.text('Przychód netto (faktura)'));
    await settle(t);

    // Hourly rate: the month's income, VAT, ryczałt and ZUS follow.
    await t.tap(nav('Dochód'));
    await settle(t);
    await t.enterText(find.byKey(const Key('income-rate')), '150');
    await settle(t);
    await binding.takeScreenshot('07_income');
    await t.tap(nav('Plan'));
    await settle(t);
    await binding.takeScreenshot('02_plan');

    await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await settle(t);
    await binding.takeScreenshot('03_plan_charts');

    // A one-off purchase planned for a later month.
    await t.tap(nav('Wydatki'));
    await settle(t);
    await t.tap(find.byKey(const Key('expense-add')));
    await settle(t);
    await t.enterText(find.byKey(const Key('expense-name')), 'wakacje');
    await t.enterText(find.byKey(const Key('expense-amount')), '6000');
    await t.tap(find.text('Raz'));
    await settle(t);
    await binding.takeScreenshot('04_expense_form');
    await t.tap(find.byKey(const Key('expense-save')));
    await settle(t);
    await binding.takeScreenshot('05_expenses');

    // A purchase in the spending log.
    await t.tap(nav('Dziennik'));
    await settle(t);
    await t.tap(find.byKey(const Key('spend-add')));
    await settle(t);
    await t.enterText(find.byKey(const Key('spend-amount')), '123,45');
    await t.enterText(find.byKey(const Key('spend-name')), 'sklep');
    await t.tap(find.byKey(const Key('spend-save')));
    await settle(t);
    await binding.takeScreenshot('06_log');

    // Household on the live Veilid network.
    await t.tap(nav('Wspólne'));
    final create = find.byKey(const Key('household-create'));
    await pumpUntil(t, create);
    final end = DateTime.now().add(const Duration(minutes: 4));
    while (t.widget<FilledButton>(create).onPressed == null &&
        DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 250));
    }
    await t.tap(create);
    await settle(t);
    await t.tap(find.text('Załóż'));
    await pumpUntil(t, find.text('Zaproś uczestnika'));
    await binding.takeScreenshot('08_household');
    await t.tap(find.text('Zaproś uczestnika'));
    await settle(t);
    await binding.takeScreenshot('09_invite_qr');

    // The optional bunny theme.
    await t.tap(find.byType(BackButton));
    await settle(t);
    await t.tap(nav('Dochód'));
    await settle(t);
    await t.tap(find.byKey(const Key('bunny-theme')));
    await settle(t);
    await t.tap(nav('Plan'));
    await settle(t);
    await binding.takeScreenshot('10_bunny');
  });
}
