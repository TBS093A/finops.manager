import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/calendar.dart';
import '../domain/models.dart';
import '../domain/planner.dart';
import '../domain/tax.dart';
import 'widgets.dart';

/// This participant's own form: who they are, how they earn, taxes and ZUS,
/// and per-month corrections (leave, extra days, bonuses).
class IncomeScreen extends StatelessWidget {
  const IncomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final me = store.me;
    final inc = me.income;
    final tax = me.tax;
    void income(IncomeSettings Function(IncomeSettings) f) =>
        store.update((m) => m.income = f(m.income));
    void taxes(TaxSettings Function(TaxSettings) f) =>
        store.update((m) => m.tax = f(m.tax));

    return Scaffold(
      appBar: AppBar(title: const Text('Mój dochód')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionCard(
            title: 'Uczestnik',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TextField(
                  label: 'Imię',
                  value: me.name,
                  onChanged: (v) {
                    if (v.trim().isNotEmpty) {
                      store.update((m) => m.name = v.trim());
                    }
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in memberColors)
                      GestureDetector(
                        onTap: () => store.update((m) => m.color = c),
                        child: CircleAvatar(
                          backgroundColor: Color(c),
                          radius: 14,
                          child: me.color == c
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Działalność (B2B, ryczałt)',
            trailing: Switch(
              value: inc.b2b,
              onChanged: (v) => income((i) => i.copyWith(b2b: v)),
            ),
            child: !inc.b2b
                ? const Text('Wyłączone — liczy się tylko dochód poniżej.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<RateType>(
                        segments: const [
                          ButtonSegment(
                            value: RateType.hourly,
                            label: Text('Godzinowa'),
                          ),
                          ButtonSegment(
                            value: RateType.daily,
                            label: Text('Dzienna'),
                          ),
                          ButtonSegment(
                            value: RateType.monthly,
                            label: Text('Miesięczna'),
                          ),
                        ],
                        selected: {inc.rateType},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            income((i) => i.copyWith(rateType: s.first)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _NumField(
                              key: const Key('income-rate'),
                              label: 'Stawka netto',
                              suffix: switch (inc.rateType) {
                                RateType.hourly => 'zł/h',
                                RateType.daily => 'zł/dzień',
                                RateType.monthly => 'zł/mies.',
                              },
                              value: inc.rate,
                              onChanged: (v) =>
                                  income((i) => i.copyWith(rate: v)),
                            ),
                          ),
                          if (inc.rateType == RateType.hourly) ...[
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 110,
                              child: _NumField(
                                label: 'Godzin/dzień',
                                value: inc.hoursPerDay,
                                onChanged: (v) =>
                                    income((i) => i.copyWith(hoursPerDay: v)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
          ),
          SectionCard(
            title: 'Inny stały dochód netto',
            child: Row(
              children: [
                Expanded(
                  child: _TextField(
                    label: 'Opis',
                    value: inc.otherLabel,
                    onChanged: (v) => income((i) => i.copyWith(otherLabel: v)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: _NumField(
                    label: 'Kwota/mies.',
                    suffix: 'zł',
                    value: inc.otherNetMonthly,
                    onChanged: (v) =>
                        income((i) => i.copyWith(otherNetMonthly: v)),
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Stan konta',
            child: Row(
              children: [
                Expanded(
                  child: _NumField(
                    label: 'Saldo na początek miesiąca',
                    suffix: 'zł',
                    value: me.startingBalance,
                    onChanged: (v) => store.update((m) {
                      m.startingBalance = v;
                      m.balanceMonth ??= YearMonth.now();
                    }),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final ym = await pickMonth(
                      context,
                      initial: me.balanceMonth ?? YearMonth.now(),
                    );
                    if (ym != null) store.update((m) => m.balanceMonth = ym);
                  },
                  child: Text((me.balanceMonth ?? YearMonth.now()).label),
                ),
              ],
            ),
          ),
          if (inc.b2b) const _MonthsCard(),
          if (inc.b2b) _taxCard(context, tax, taxes),
        ],
      ),
    );
  }

  Widget _taxCard(
    BuildContext context,
    TaxSettings tax,
    void Function(TaxSettings Function(TaxSettings)) taxes,
  ) {
    const rates = [0.12, 0.085, 0.15, 0.17, 0.14, 0.10, 0.055, 0.03];
    return SectionCard(
      title: 'Podatki i ZUS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<double>(
            isExpanded: true,
            initialValue: rates.contains(tax.ryczaltRate)
                ? tax.ryczaltRate
                : 0.12,
            decoration: const InputDecoration(labelText: 'Stawka ryczałtu'),
            items: [
              for (final r in rates)
                DropdownMenuItem(
                  value: r,
                  child: Text(
                    '${(r * 100).toStringAsFixed(1).replaceAll('.0', '')}%'
                    '${r == 0.12 ? ' (usługi IT)' : ''}',
                  ),
                ),
            ],
            onChanged: (v) => taxes((t) => t.copyWith(ryczaltRate: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Płatnik VAT (23%)'),
            value: tax.vatPayer,
            onChanged: (v) => taxes((t) => t.copyWith(vatPayer: v)),
          ),
          DropdownButtonFormField<ZusMode>(
            isExpanded: true,
            initialValue: tax.zusMode,
            decoration: const InputDecoration(labelText: 'ZUS'),
            items: [
              for (final m in ZusMode.values)
                DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (v) => taxes((t) => t.copyWith(zusMode: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dobrowolne chorobowe'),
            value: tax.sickness,
            onChanged: (v) => taxes((t) => t.copyWith(sickness: v)),
          ),
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: tax.healthTier,
            decoration: const InputDecoration(
              labelText: 'Próg składki zdrowotnej',
            ),
            items: [
              const DropdownMenuItem(
                value: 0,
                child: Text('Automatycznie z prognozy roku'),
              ),
              DropdownMenuItem(
                value: 1,
                child: Text('do 60 tys. — ${zl(tax.healthFor(1))}'),
              ),
              DropdownMenuItem(
                value: 2,
                child: Text('60–300 tys. — ${zl(tax.healthFor(2))}'),
              ),
              DropdownMenuItem(
                value: 3,
                child: Text('pow. 300 tys. — ${zl(tax.healthFor(3))}'),
              ),
            ],
            onChanged: (v) => taxes((t) => t.copyWith(healthTier: v)),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Parametry na dany rok'),
            subtitle: const Text('Zmieniają się co styczeń'),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              _NumField(
                label:
                    'Podstawa pełnego ZUS (60% prognozowanego wynagrodzenia)',
                suffix: 'zł',
                value: tax.fullBase,
                onChanged: (v) => taxes((t) => t.copyWith(fullBase: v)),
              ),
              const SizedBox(height: 8),
              _NumField(
                label: 'Podstawa preferencyjna (30% płacy minimalnej)',
                suffix: 'zł',
                value: tax.preferentialBase,
                onChanged: (v) => taxes((t) => t.copyWith(preferentialBase: v)),
              ),
              const SizedBox(height: 8),
              _NumField(
                label: 'Przeciętne wynagrodzenie IV kw. (zdrowotna)',
                suffix: 'zł',
                value: tax.avgWage,
                onChanged: (v) => taxes((t) => t.copyWith(avgWage: v)),
              ),
              const SizedBox(height: 8),
              _NumField(
                label: 'Składka wypadkowa',
                suffix: '%',
                value: tax.accidentRate * 100,
                onChanged: (v) =>
                    taxes((t) => t.copyWith(accidentRate: v / 100)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Odliczaj składki społeczne od przychodu'),
                value: tax.deductSocial,
                onChanged: (v) => taxes((t) => t.copyWith(deductSocial: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Odliczaj 50% składki zdrowotnej'),
                value: tax.deductHalfHealth,
                onChanged: (v) => taxes((t) => t.copyWith(deductHalfHealth: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Working days of the coming months, with per-month corrections.
class _MonthsCard extends StatelessWidget {
  const _MonthsCard();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final me = store.me;
    final planner = Planner(me);
    final from = YearMonth.now();
    return SectionCard(
      title: 'Dni robocze i korekty',
      child: Column(
        children: [
          for (var i = 0; i < 12; i++)
            Builder(
              builder: (context) {
                final ym = from.add(i);
                final o = me.overrideFor(ym);
                final days = planner.workDays(ym);
                final info = [
                  '$days dni',
                  if (o.workDays != null) 'ręcznie',
                  if (o.daysOff > 0) 'urlop ${o.daysOff}',
                  if (o.extraNet != 0) '+${zl(o.extraNet)}',
                  if (o.inputVat != 0) 'VAT naliczony ${zl(o.inputVat)}',
                  if (o.note.isNotEmpty) o.note,
                ].join(' · ');
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(ym.label),
                  subtitle: Text(info),
                  trailing: Text(zl(planner.month(ym).income)),
                  onTap: () => _edit(context, ym),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, YearMonth ym) async {
    final store = StoreScope.of(context);
    final o = store.me.overrideFor(ym);
    final auto = workingDaysIn(ym);
    final days = TextEditingController(text: o.workDays?.toString() ?? '');
    final off = TextEditingController(
      text: o.daysOff == 0 ? '' : '${o.daysOff}',
    );
    final extra = TextEditingController(text: amountText(o.extraNet));
    final inVat = TextEditingController(text: amountText(o.inputVat));
    final note = TextEditingController(text: o.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ym.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: days,
              decoration: InputDecoration(
                labelText: 'Dni robocze',
                hintText: '$auto (z kalendarza)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: off,
              decoration: const InputDecoration(labelText: 'Dni urlopu'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: extra,
              decoration: const InputDecoration(
                labelText: 'Dodatkowa faktura netto',
                suffixText: 'zł',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('month-input-vat'),
              controller: inVat,
              decoration: const InputDecoration(
                labelText: 'Dodatkowy VAT naliczony',
                helperText: 'faktury kosztowe spoza listy wydatków',
                suffixText: 'zł',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Notatka'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    final value = MonthOverride(
      workDays: int.tryParse(days.text),
      daysOff: int.tryParse(off.text) ?? 0,
      extraNet: parseAmount(extra.text) ?? 0,
      inputVat: parseAmount(inVat.text) ?? 0,
      note: note.text.trim(),
    );
    disposeAfterClose([days, off, extra, inVat, note]);
    if (ok != true) return;
    store.update((m) {
      if (value.isEmpty) {
        m.overrides.remove(ym.key);
      } else {
        m.overrides[ym.key] = value;
      }
    });
  }
}

class _NumField extends StatelessWidget {
  const _NumField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: amountText(value),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (s) => onChanged(parseAmount(s) ?? 0),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    );
  }
}
