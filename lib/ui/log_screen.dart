import 'package:flutter/material.dart';

import '../app.dart';
import '../data/store.dart';
import '../domain/calendar.dart';
import '../domain/models.dart';
import '../domain/planner.dart';
import 'widgets.dart';

/// Day-to-day spending, drawn from budgets.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  YearMonth get _month => StoreScope.read(context).month;

  @override
  Widget build(BuildContext context) {
    final me = StoreScope.of(context).me;
    final budgets = me.expenses
        .where((e) => e.budget && e.activeIn(_month))
        .toList();
    final planner = Planner(me);
    final entries = me.spendings.where((s) => s.month == _month).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - now.weekday + 1);

    return Scaffold(
      appBar: AppBar(
        title: MonthSwitcher(
          month: _month,
          onChanged: (m) => StoreScope.read(context).setMonth(m),
        ),
        centerTitle: true,
      ),
      floatingActionButton: budgets.isEmpty
          ? null
          : FloatingActionButton(
              heroTag: null,
              key: const Key('spend-add'),
              tooltip: 'Dodaj wydatek do dziennika',
              onPressed: () => _edit(budgets),
              child: const Icon(Icons.add_shopping_cart),
            ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          if (budgets.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nie masz budżetów w tym miesiącu. Dodaj wydatek „Co miesiąc” '
                'z włączoną opcją „Budżet” (np. jedzenie), a tutaj '
                'będziesz zapisywać bieżące zakupy.',
              ),
            ),
          for (final b in budgets)
            _budgetCard(
              b,
              planner.spentIn(b.id, _month),
              entries
                  .where(
                    (s) => s.budgetId == b.id && !s.date.isBefore(weekStart),
                  )
                  .fold(0.0, (a, s) => a + s.amount),
            ),
          for (final s in entries)
            ListTile(
              dense: true,
              title: Text(s.name),
              subtitle: Text(
                '${s.date.day}.${s.date.month.toString().padLeft(2, '0')} · '
                '${budgets.where((b) => b.id == s.budgetId).firstOrNull?.name ?? '—'}',
              ),
              trailing: Text(zl(s.amount)),
              onTap: () => _edit(budgets, existing: s),
            ),
        ],
      ),
    );
  }

  Widget _budgetCard(Expense b, double spent, double week) {
    final isNow = _month == YearMonth.now();
    // Weekly allowance: the monthly limit prorated to seven days.
    final weekly = b.amount * 7 / _month.daysInMonth;
    final left = b.amount - spent;
    return SectionCard(
      peek: Peek.topRight,
      seed: b.id.hashCode,
      title: b.name,
      trailing: Text('${zl(spent)} / ${zl(b.amount)}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: b.amount > 0 ? (spent / b.amount).clamp(0, 1) : 0,
            color: left < 0 ? Theme.of(context).colorScheme.error : null,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 6),
          Text(
            left >= 0
                ? 'Zostało ${zl(left)} w miesiącu'
                : 'Przekroczono o ${zl(-left)}',
          ),
          if (isNow)
            Text(
              'Ten tydzień: ${zl(week)} z ok. ${zl(weekly)} '
              '(zostało ${zl(weekly - week)})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Future<void> _edit(List<Expense> budgets, {Spending? existing}) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: existing?.name);
    final amount = TextEditingController(
      text: amountText(existing?.amount ?? 0),
    );
    var budgetId = existing?.budgetId ?? budgets.first.id;
    if (!budgets.any((b) => b.id == budgetId)) budgetId = budgets.first.id;
    final today = DateTime.now();
    var date =
        existing?.date ??
        (_month == YearMonth.of(today)
            ? today
            : DateTime(_month.year, _month.month, 1));

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('spend-amount'),
                controller: amount,
                autofocus: existing == null,
                decoration: const InputDecoration(
                  labelText: 'Kwota',
                  suffixText: 'zł',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('spend-name'),
                controller: name,
                decoration: const InputDecoration(labelText: 'Co (np. sklep)'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final b in budgets)
                    ChoiceChip(
                      label: Text(b.name),
                      selected: budgetId == b.id,
                      onSelected: (_) => set(() => budgetId = b.id),
                    ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.today),
                title: Text('${date.day}.${date.month}.${date.year}'),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) set(() => date = d);
                },
              ),
              Row(
                children: [
                  if (existing != null)
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop('delete'),
                      child: const Text('Usuń'),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('spend-save'),
                    onPressed: () => Navigator.of(ctx).pop('save'),
                    child: const Text('Zapisz'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final value = parseAmount(amount.text);
    final label = name.text.trim();
    disposeAfterClose([name, amount]);
    if (result == 'delete' && existing != null) {
      store.update(
        (me) => me.spendings.removeWhere((s) => s.id == existing.id),
      );
      return;
    }
    if (result != 'save' || value == null || value == 0) return;
    final s = Spending(
      id: existing?.id ?? uuid.v4(),
      date: date,
      amount: value,
      name: label.isEmpty ? '—' : label,
      budgetId: budgetId,
    );
    store.update((me) {
      final i = me.spendings.indexWhere((x) => x.id == s.id);
      if (i >= 0) {
        me.spendings[i] = s;
      } else {
        me.spendings.add(s);
      }
    });
  }
}
