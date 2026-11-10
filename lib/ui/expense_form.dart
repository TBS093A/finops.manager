import 'package:flutter/material.dart';

import '../app.dart';
import '../data/store.dart';
import '../domain/calendar.dart';
import '../domain/models.dart';
import 'widgets.dart';

/// Add or edit one planned expense of this phone's participant.
class ExpenseForm extends StatefulWidget {
  const ExpenseForm({
    super.key,
    this.expense,
    this.initialMonth,
    this.wish = false,
  });

  final Expense? expense;
  final YearMonth? initialMonth;

  /// New item goes on the wish list (no month yet).
  final bool wish;

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

enum _Kind { once, monthly, yearly, wish }

class _ExpenseFormState extends State<ExpenseForm> {
  late final _name = TextEditingController(text: widget.expense?.name);
  late final _amount = TextEditingController(
    text: amountText(widget.expense?.amount ?? 0),
  );
  late final _note = TextEditingController(text: widget.expense?.note);
  late final _day = TextEditingController(
    text: widget.expense?.dayOfMonth?.toString() ?? '',
  );
  late final _count = TextEditingController();

  late _Kind _kind;
  late String _cat;
  YearMonth? _start;
  YearMonth? _end;
  int _spread = 1;
  bool _budget = false;
  double _vatRate = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    if (e == null) {
      _kind = widget.wish ? _Kind.wish : _Kind.monthly;
      _cat = widget.wish ? 'zakupy' : 'wlasne';
      _start = widget.wish ? null : (widget.initialMonth ?? YearMonth.now());
    } else {
      _kind = e.isWish
          ? _Kind.wish
          : switch (e.repeat) {
              Repeat.once => _Kind.once,
              Repeat.monthly => _Kind.monthly,
              Repeat.yearly => _Kind.yearly,
            };
      _cat = e.categoryId;
      _start = e.start;
      _end = e.end;
      _spread = e.spreadMonths;
      _budget = e.budget;
      _vatRate = e.vatRate;
      final left = e.remainingFrom(e.start ?? YearMonth.now());
      if (left != null) _count.text = '$left';
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _note, _day, _count]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final amount = parseAmount(_amount.text) ?? 0;
    if (name.isEmpty) {
      _snack('Podaj nazwę');
      return;
    }
    if (_kind != _Kind.wish && _start == null) {
      _snack('Wybierz miesiąc');
      return;
    }
    final day = int.tryParse(_day.text);
    final e = Expense(
      id: widget.expense?.id ?? uuid.v4(),
      name: name,
      amount: amount,
      categoryId: _cat,
      repeat: switch (_kind) {
        _Kind.once || _Kind.wish => Repeat.once,
        _Kind.monthly => Repeat.monthly,
        _Kind.yearly => Repeat.yearly,
      },
      start: _kind == _Kind.wish ? null : _start,
      end: _kind == _Kind.monthly || _kind == _Kind.yearly ? _end : null,
      dayOfMonth: day != null && day >= 1 && day <= 31 ? day : null,
      spreadMonths: _kind == _Kind.once ? _spread : 1,
      budget: _kind == _Kind.monthly && _budget,
      vatRate: _budget ? 0 : _vatRate,
      note: _note.text.trim(),
    );
    StoreScope.of(context).update((me) {
      final i = me.expenses.indexWhere((x) => x.id == e.id);
      if (i >= 0) {
        me.expenses[i] = e;
      } else {
        me.expenses.add(e);
      }
    });
    Navigator.of(context).pop();
  }

  void _delete() {
    final id = widget.expense!.id;
    StoreScope.of(context).update((me) {
      me.expenses.removeWhere((x) => x.id == id);
      me.spendings.removeWhere((s) => s.budgetId == id);
    });
    Navigator.of(context).pop();
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  void _countChanged(String v) {
    final n = int.tryParse(v);
    if (n == null || n < 1 || _start == null) return;
    setState(() => _end = _start!.add(n - 1));
  }

  @override
  Widget build(BuildContext context) {
    final me = StoreScope.of(context).me;
    final cats = me.categories;
    if (!cats.any((c) => c.id == _cat)) _cat = cats.first.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expense == null ? 'Nowy wydatek' : 'Edycja'),
        actions: [
          if (widget.expense != null)
            IconButton(
              tooltip: 'Usuń',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          IconButton(
            key: const Key('expense-save'),
            tooltip: 'Zapisz',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('expense-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nazwa'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('expense-amount'),
            controller: _amount,
            decoration: InputDecoration(
              labelText: _budget ? 'Limit miesięczny' : 'Kwota',
              suffixText: 'zł',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _cat,
            decoration: const InputDecoration(labelText: 'Kategoria'),
            items: [
              for (final c in cats)
                DropdownMenuItem(
                  value: c.id,
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, color: Color(c.color)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _cat = v ?? _cat),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (k, label) in const [
                (_Kind.monthly, 'Co miesiąc'),
                (_Kind.once, 'Raz'),
                (_Kind.yearly, 'Co rok'),
                (_Kind.wish, 'Kiedyś'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _kind == k,
                  onSelected: (_) => setState(() {
                    _kind = k;
                    if (_kind != _Kind.wish) _start ??= YearMonth.now();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ..._kindFields(),
          const SizedBox(height: 12),
          if (_kind != _Kind.wish)
            TextField(
              controller: _day,
              decoration: const InputDecoration(
                labelText: 'Dzień miesiąca (opcjonalnie)',
              ),
              keyboardType: TextInputType.number,
            ),
          if (me.tax.vatPayer && me.income.b2b && !_budget) ..._vatFields(),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Notatka'),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  /// Business cost on a VAT invoice: its VAT is deducted from the VAT to pay.
  List<Widget> _vatFields() {
    final gross = parseAmount(_amount.text) ?? 0;
    return [
      SwitchListTile(
        key: const Key('expense-vat'),
        contentPadding: EdgeInsets.zero,
        value: _vatRate > 0,
        onChanged: (v) => setState(() => _vatRate = v ? 0.23 : 0),
        title: const Text('Koszt firmowy z fakturą VAT'),
        subtitle: const Text(
          'Kwota brutto; VAT z faktury odejmie się od VAT do zapłaty '
          '(w miesiącu zakupu).',
        ),
      ),
      if (_vatRate > 0) ...[
        Wrap(
          spacing: 8,
          children: [
            for (final r in const [0.23, 0.08, 0.05])
              ChoiceChip(
                label: Text('${(r * 100).round()}%'),
                selected: _vatRate == r,
                onSelected: (_) => setState(() => _vatRate = r),
              ),
          ],
        ),
        Text(
          'VAT do odliczenia: ${zl(gross * _vatRate / (1 + _vatRate))}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ];
  }

  List<Widget> _kindFields() {
    Widget monthTile(
      String label,
      YearMonth? v,
      ValueChanged<YearMonth?> set, {
      bool clearable = false,
    }) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(v?.label ?? 'bez końca'),
        trailing: clearable && v != null
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() => set(null)),
              )
            : const Icon(Icons.calendar_month),
        onTap: () async {
          final m = await pickMonth(context, initial: v ?? _start);
          if (m != null) setState(() => set(m));
        },
      );
    }

    switch (_kind) {
      case _Kind.wish:
        return const [
          Text(
            'Pozycja trafi na listę życzeń i nie liczy się do planu, '
            'dopóki nie wybierzesz jej miesiąca.',
          ),
        ];
      case _Kind.once:
        return [
          monthTile('W miesiącu', _start, (m) => _start = m),
          Row(
            children: [
              const Expanded(child: Text('Odkładaj na to przez')),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _spread > 1 ? () => setState(() => _spread--) : null,
              ),
              Text('$_spread mies.'),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _spread < 36
                    ? () => setState(() => _spread++)
                    : null,
              ),
            ],
          ),
          if (_spread > 1 && _start != null)
            Text(
              '${zl((parseAmount(_amount.text) ?? 0) / _spread)} miesięcznie, '
              'od ${_start!.add(-(_spread - 1)).label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ];
      case _Kind.monthly:
        return [
          monthTile('Od', _start, (m) {
            _start = m;
            _countChanged(_count.text);
          }),
          monthTile('Do', _end, (m) {
            _end = m;
            _count.text = m == null || _start == null
                ? ''
                : '${_start!.monthsUntil(m) + 1}';
          }, clearable: true),
          TextField(
            controller: _count,
            decoration: const InputDecoration(
              labelText: 'Liczba rat (opcjonalnie)',
              helperText: 'wylicza miesiąc „Do”',
            ),
            keyboardType: TextInputType.number,
            onChanged: _countChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _budget,
            onChanged: (v) => setState(() => _budget = v),
            title: const Text('Budżet (np. jedzenie)'),
            subtitle: const Text(
              'Wydatki z dziennika odejmują się od limitu; '
              'w minionych miesiącach liczy się to, co faktycznie wydano.',
            ),
          ),
        ];
      case _Kind.yearly:
        return [
          monthTile('Pierwszy raz', _start, (m) => _start = m),
          monthTile('Ostatni raz', _end, (m) => _end = m, clearable: true),
        ];
    }
  }
}
