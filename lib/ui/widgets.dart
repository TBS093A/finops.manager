import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/calendar.dart';

final _money = NumberFormat.currency(
  locale: 'pl_PL',
  symbol: 'zł',
  decimalDigits: 2,
);
final _moneyShort = NumberFormat.compactCurrency(
  locale: 'pl_PL',
  symbol: '',
  decimalDigits: 1,
);

/// Disposes the controllers of a dialog or bottom sheet once its closing
/// animation is over: the route still rebuilds its fields while it animates
/// out, after `showDialog` has already returned.
void disposeAfterClose(List<ChangeNotifier> controllers) {
  Future<void>.delayed(const Duration(seconds: 1), () {
    for (final c in controllers) {
      c.dispose();
    }
  });
}

String zl(double v) => _money.format(v);
String zlShort(double v) => _moneyShort.format(v).trim();
String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// Parses "1 234,56" as well as "1234.56".
double? parseAmount(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));

String amountText(double v) {
  if (v == 0) return '';
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
  });
  final YearMonth month;
  final ValueChanged<YearMonth> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Poprzedni miesiąc',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(month.add(-1)),
        ),
        GestureDetector(
          onTap: () => onChanged(YearMonth.now()),
          child: Text(
            month.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Następny miesiąc',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(month.add(1)),
        ),
      ],
    );
  }
}

/// "label ........ amount" line used in summaries.
class AmountRow extends StatelessWidget {
  const AmountRow(
    this.label,
    this.amount, {
    super.key,
    this.bold = false,
    this.color,
    this.sub,
    this.negative = false,
  });

  final String label;
  final double amount;
  final bool bold;
  final Color? color;
  final String? sub;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style),
                if (sub != null)
                  Text(sub!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(zl(negative && amount != 0 ? -amount : amount), style: style),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

const memberColors = <int>[
  0xFF1E88E5,
  0xFFD81B60,
  0xFF43A047,
  0xFFFB8C00,
  0xFF8E24AA,
  0xFF00ACC1,
  0xFF6D4C41,
  0xFF546E7A,
];

Future<YearMonth?> pickMonth(
  BuildContext context, {
  YearMonth? initial,
  String title = 'Wybierz miesiąc',
}) {
  var year = (initial ?? YearMonth.now()).year;
  return showDialog<YearMonth>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => set(() => year--),
                  ),
                  Text('$year', style: Theme.of(ctx).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => set(() => year++),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var m = 1; m <= 12; m++)
                    ChoiceChip(
                      label: SizedBox(
                        width: 34,
                        child: Text(
                          monthShort[m - 1],
                          textAlign: TextAlign.center,
                        ),
                      ),
                      selected: initial == YearMonth(year, m),
                      onSelected: (_) =>
                          Navigator.of(ctx).pop(YearMonth(year, m)),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Anuluj'),
          ),
        ],
      ),
    ),
  );
}
