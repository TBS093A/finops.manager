import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/calendar.dart';
import '../domain/models.dart';
import 'categories_screen.dart';
import 'expense_form.dart';
import 'widgets.dart';

/// This participant's planned expenses: what a month holds, everything
/// recurring, and the wish list.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  YearMonth _month = YearMonth.now();

  void _open({Expense? e, bool wish = false}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ExpenseForm(expense: e, initialMonth: _month, wish: wish),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final me = StoreScope.of(context).me;
    return DefaultTabController(
      length: 3,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Wydatki'),
            actions: [
              IconButton(
                tooltip: 'Kategorie',
                icon: const Icon(Icons.category_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CategoriesScreen(),
                  ),
                ),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Miesiąc'),
                Tab(text: 'Wszystkie'),
                Tab(text: 'Lista życzeń'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            key: const Key('expense-add'),
            tooltip: 'Dodaj wydatek',
            onPressed: () =>
                _open(wish: DefaultTabController.of(context).index == 2),
            child: const Icon(Icons.add),
          ),
          body: TabBarView(
            children: [_monthTab(me), _allTab(me), _wishTab(me)],
          ),
        ),
      ),
    );
  }

  Widget _monthTab(MemberData me) {
    final items = [
      for (final e in me.expenses)
        if (e.activeIn(_month)) (e: e, amount: e.amountIn(_month)),
    ];
    final byCat = <String, List<({Expense e, double amount})>>{};
    for (final x in items) {
      byCat.putIfAbsent(x.e.categoryId, () => []).add(x);
    }
    final total = items.fold(0.0, (a, x) => a + x.amount);
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Center(
          child: MonthSwitcher(
            month: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AmountRow('Razem w miesiącu', total, bold: true),
        ),
        for (final entry in byCat.entries) ...[
          _catHeader(
            me.category(entry.key),
            entry.value.fold<double>(0, (a, x) => a + x.amount),
          ),
          for (final x
              in entry.value..sort(
                (a, b) =>
                    (a.e.dayOfMonth ?? 99).compareTo(b.e.dayOfMonth ?? 99),
              ))
            _tile(x.e, amount: x.amount),
        ],
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Brak wydatków w tym miesiącu. Dodaj pierwszy przyciskiem +.',
            ),
          ),
      ],
    );
  }

  Widget _allTab(MemberData me) {
    final planned = me.expenses.where((e) => !e.isWish).toList();
    final byCat = <String, List<Expense>>{};
    for (final e in planned) {
      byCat.putIfAbsent(e.categoryId, () => []).add(e);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final c in me.categories)
          if (byCat[c.id] != null) ...[
            _catHeader(c, null),
            for (final e
                in byCat[c.id]!..sort((a, b) => a.name.compareTo(b.name)))
              _tile(e),
          ],
        if (planned.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Brak zaplanowanych wydatków.'),
          ),
      ],
    );
  }

  Widget _wishTab(MemberData me) {
    final wishes = me.expenses.where((e) => e.isWish).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final total = wishes.fold(0.0, (a, e) => a + e.amount);
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: AmountRow('Wszystko razem', total, bold: true),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Rzeczy „kiedyś”. Kliknij kalendarz, żeby wpisać je w konkretny '
            'miesiąc — wtedy pojawią się w planie i prognozie.',
          ),
        ),
        for (final e in wishes)
          ListTile(
            title: Text(e.name),
            subtitle: e.note.isEmpty ? null : Text(e.note),
            leading: Text(e.amount == 0 ? '—' : zl(e.amount)),
            leadingAndTrailingTextStyle: Theme.of(context).textTheme.bodyMedium,
            trailing: IconButton(
              tooltip: 'Zaplanuj na miesiąc',
              icon: const Icon(Icons.event_available),
              onPressed: () => _schedule(e),
            ),
            onTap: () => _open(e: e),
          ),
      ],
    );
  }

  Future<void> _schedule(Expense e) async {
    final m = await pickMonth(
      context,
      initial: YearMonth.now().add(1),
      title: 'Kiedy kupujemy „${e.name}”?',
    );
    if (m == null || !mounted) return;
    StoreScope.of(context).update((me) {
      final i = me.expenses.indexWhere((x) => x.id == e.id);
      if (i >= 0) me.expenses[i] = e.copyWith(start: () => m);
    });
  }

  Widget _catHeader(Category c, double? total) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      children: [
        Container(width: 12, height: 12, color: Color(c.color)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(c.name, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (total != null)
          Text(zl(total), style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );

  Widget _tile(Expense e, {double? amount}) {
    final parts = <String>[
      switch (e.repeat) {
        Repeat.monthly =>
          e.end == null
              ? 'co miesiąc od ${e.start?.shortLabel}'
              : 'co miesiąc ${e.start?.shortLabel} – ${e.end!.shortLabel}',
        Repeat.yearly =>
          'co rok, ${monthNames[e.start!.month - 1].toLowerCase()}',
        Repeat.once =>
          e.spreadMonths > 1
              ? '${e.start?.label}, odkładane przez ${e.spreadMonths} mies.'
              : '${e.start?.label}',
      },
      if (e.dayOfMonth != null) '${e.dayOfMonth}. dnia',
      if (e.budget) 'budżet',
      if (e.remainingFrom(_month) case final n? when n > 0) 'zostało $n rat',
    ];
    return ListTile(
      dense: true,
      title: Text(e.name),
      subtitle: Text(parts.join(' · ')),
      trailing: e.amount == 0
          ? Text(
              'uzupełnij kwotę',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          : Text(zl(amount ?? e.amount)),
      onTap: () => _open(e: e),
    );
  }
}
