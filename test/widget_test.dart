import 'package:finops_manager/app.dart';
import 'package:finops_manager/data/store.dart';
import 'package:finops_manager/domain/calendar.dart';
import 'package:finops_manager/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Store> pumpApp(WidgetTester t, {MemberData? me}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final store = Store.memory(me ?? MemberData(memberId: 'me'));
    store.selected.add(store.me.memberId);
    await t.pumpWidget(FinOpsApp(store: store));
    await t.pumpAndSettle();
    return store;
  }

  testWidgets('first run: setup with the starter template', (t) async {
    final store = await pumpApp(t);
    expect(find.text('Zaczynamy'), findsOneWidget);
    await t.enterText(find.byKey(const Key('setup-name')), 'Anna');
    await t.tap(find.byKey(const Key('setup-done')));
    await t.pumpAndSettle();

    expect(store.me.name, 'Anna');
    expect(store.me.expenses.every((e) => e.amount == 0), isTrue);
    expect(store.me.expenses, isNotEmpty);
    expect(find.text('Bilans miesiąca'), findsOneWidget);
    expect(find.text('Przychód netto (faktura)'), findsOneWidget);
    expect(find.textContaining('ZUS'), findsWidgets);
  });

  testWidgets('add a one-off expense from the Wydatki tab', (t) async {
    final store = await pumpApp(
      t,
      me: MemberData(memberId: 'me', name: 'A'),
    );
    await t.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Wydatki'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('expense-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('expense-name')), 'rower');
    await t.enterText(find.byKey(const Key('expense-amount')), '1399,50');
    await t.tap(find.text('Raz'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('expense-save')));
    await t.pumpAndSettle();

    final e = store.me.expenses.single;
    expect(e.name, 'rower');
    expect(e.amount, 1399.5);
    expect(e.repeat, Repeat.once);
    expect(e.start, isNotNull);
    expect(find.text('rower'), findsOneWidget);
  });

  testWidgets('spending log entry, then a new expense (two FABs)', (t) async {
    final store = await pumpApp(
      t,
      me: MemberData(
        memberId: 'me',
        name: 'A',
        expenses: [
          Expense(
            id: 'food',
            name: 'jedzenie',
            amount: 2000,
            categoryId: 'codzienne',
            start: YearMonth.now(),
            budget: true,
          ),
        ],
      ),
    );
    Finder nav(String s) =>
        find.descendant(of: find.byType(NavigationBar), matching: find.text(s));
    await t.tap(nav('Dziennik'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('spend-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('spend-amount')), '123,45');
    await t.enterText(find.byKey(const Key('spend-name')), 'sklep');
    await t.tap(find.byKey(const Key('spend-save')));
    await t.pumpAndSettle();
    expect(store.me.spendings.single.amount, 123.45);

    await t.tap(nav('Wydatki'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('expense-add')));
    await t.pumpAndSettle();
    expect(find.text('Nowy wydatek'), findsOneWidget);
  });

  testWidgets('Plan, Wydatki and Dziennik share the selected month', (t) async {
    final store = await pumpApp(
      t,
      me: MemberData(
        memberId: 'me',
        name: 'A',
        expenses: [
          Expense(
            id: 'food',
            name: 'jedzenie',
            amount: 2000,
            categoryId: 'codzienne',
            start: YearMonth.now(),
            budget: true,
          ),
        ],
      ),
    );
    Finder nav(String s) =>
        find.descendant(of: find.byType(NavigationBar), matching: find.text(s));
    final now = YearMonth.now();

    // Forward twice on Plan.
    await t.tap(find.byTooltip('Następny miesiąc'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Następny miesiąc'));
    await t.pumpAndSettle();
    expect(store.month, now.add(2));

    await t.tap(nav('Wydatki'));
    await t.pumpAndSettle();
    expect(find.text(now.add(2).label), findsOneWidget);

    // Back once on Wydatki: Dziennik and Plan follow.
    await t.tap(find.byTooltip('Poprzedni miesiąc'));
    await t.pumpAndSettle();
    await t.tap(nav('Dziennik'));
    await t.pumpAndSettle();
    expect(find.text(now.add(1).label), findsOneWidget);
    await t.tap(nav('Plan'));
    await t.pumpAndSettle();
    expect(find.text(now.add(1).label), findsOneWidget);
  });

  testWidgets('income and household screens render', (t) async {
    await pumpApp(
      t,
      me: MemberData(memberId: 'me', name: 'A'),
    );
    Finder nav(String s) =>
        find.descendant(of: find.byType(NavigationBar), matching: find.text(s));
    await t.tap(nav('Dochód'));
    await t.pumpAndSettle();
    expect(find.text('Mój dochód'), findsOneWidget);
    await t.drag(
      find.text('Działalność (B2B, ryczałt)'),
      const Offset(0, -1200),
    );
    await t.pumpAndSettle();
    expect(find.text('Dni robocze i korekty'), findsOneWidget);
    await t.tap(nav('Wspólne'));
    await t.pumpAndSettle();
    expect(find.text('Załóż gospodarstwo'), findsOneWidget);
  });
}
