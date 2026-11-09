import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../data/store.dart';
import '../domain/calendar.dart';
import '../domain/models.dart';
import '../domain/planner.dart';
import '../domain/tax.dart';
import 'widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  YearMonth _month = YearMonth.now();
  static const _horizon = 12;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final members = store.selectedMembers;
    final months = combine(members, _month, _horizon);
    final cur = months.first;
    final balances = _runningBalances(members);

    return Scaffold(
      appBar: AppBar(
        title: MonthSwitcher(
          month: _month,
          onChanged: (m) => setState(() => _month = m),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async => store.sync?.refresh(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (store.peers.isNotEmpty) _memberChips(store, members),
            _summary(cur, balances.first, members.length > 1),
            for (final p in cur.plans)
              if (p.member.income.b2b || p.otherIncome > 0)
                _IncomeCard(plan: p, showName: cur.plans.length > 1),
            _categories(cur),
            _forecast(months, balances, members),
            _budgets(cur),
            _upcoming(members),
          ],
        ),
      ),
    );
  }

  List<double> _runningBalances(List<MemberData> members) {
    final out = List<double>.filled(_horizon, 0);
    for (final m in members) {
      final pl = Planner(m);
      final b = pl.runningBalance(pl.range(_month, _horizon));
      for (var i = 0; i < _horizon; i++) {
        out[i] += b[i];
      }
    }
    return out;
  }

  Widget _memberChips(Store store, List<MemberData> selected) {
    final ids = selected.map((m) => m.memberId).toSet();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Wrap(
        spacing: 8,
        children: [
          for (final m in store.everyone)
            FilterChip(
              avatar: CircleAvatar(backgroundColor: Color(m.color), radius: 8),
              label: Text(m == store.me ? '${m.name} (ja)' : m.name),
              selected: ids.contains(m.memberId),
              onSelected: (_) => store.toggleSelected(m.memberId),
            ),
        ],
      ),
    );
  }

  Widget _summary(CombinedMonth c, double endBalance, bool joint) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: joint ? 'Wspólny bilans' : 'Bilans miesiąca',
      child: Column(
        children: [
          AmountRow('Dochód na rękę', c.income, bold: true),
          AmountRow('Wydatki', c.expenses, negative: true),
          AmountRow('Oszczędności i inwestycje', c.savings, negative: true),
          const Divider(),
          AmountRow(
            'Zostaje',
            c.balance,
            bold: true,
            color: c.balance < 0 ? scheme.error : Colors.green.shade700,
          ),
          AmountRow(
            'Stan konta na koniec miesiąca',
            endBalance,
            sub: 'saldo początkowe + bilanse kolejnych miesięcy',
          ),
        ],
      ),
    );
  }

  Widget _categories(CombinedMonth c) {
    final cats = c.byCategory.entries.toList()
      ..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    final levies = round2(c.pit + c.zus);
    final inflow = c.inflow;
    if (cats.isEmpty && levies == 0) {
      return const SectionCard(
        title: 'Na co idą pieniądze',
        child: Text('Brak wydatków w tym miesiącu.'),
      );
    }
    final sections = [
      if (c.vat > 0)
        PieChartSectionData(
          value: c.vat,
          color: Colors.grey.shade500,
          title: '',
          radius: 40,
        ),
      if (levies > 0)
        PieChartSectionData(
          value: levies,
          color: Colors.red.shade900,
          title: '',
          radius: 40,
        ),
      for (final e in cats)
        PieChartSectionData(
          value: e.value.amount,
          color: Color(e.value.color),
          title: '',
          radius: 40,
        ),
      if (c.balance > 0)
        PieChartSectionData(
          value: c.balance,
          color: Colors.green.shade300,
          title: '',
          radius: 40,
        ),
    ];
    String share(double v) => inflow > 0 ? pct(v / inflow) : '';
    Widget row(Color color, String name, double v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 10, height: 10, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(name)),
          SizedBox(
            width: 52,
            child: Text(
              share(v),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(width: 110, child: Text(zl(v), textAlign: TextAlign.right)),
        ],
      ),
    );
    return SectionCard(
      title: 'Procentowy plan wydatków',
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 36,
                sectionsSpace: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '% wpływów na konto (${zl(inflow)})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          if (c.vat > 0) row(Colors.grey.shade500, 'VAT', c.vat),
          if (levies > 0) row(Colors.red.shade900, 'Ryczałt + ZUS', levies),
          for (final e in cats)
            row(Color(e.value.color), e.key, e.value.amount),
          if (c.balance > 0) row(Colors.green.shade300, 'Zostaje', c.balance),
        ],
      ),
    );
  }

  Widget _forecast(
    List<CombinedMonth> months,
    List<double> balances,
    List<MemberData> members,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final groups = <BarChartGroupData>[];
    var maxY = 0.0;
    for (var i = 0; i < months.length; i++) {
      final c = months[i];
      // Income stacked per member, outflow next to it.
      var acc = 0.0;
      final stack = <BarChartRodStackItem>[];
      for (final p in c.plans) {
        final v = p.income < 0 ? 0.0 : p.income;
        stack.add(BarChartRodStackItem(acc, acc + v, Color(p.member.color)));
        acc += v;
      }
      final out = c.expenses + c.savings;
      maxY = [maxY, acc, out].reduce((a, b) => a > b ? a : b);
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 2,
          barRods: [
            BarChartRodData(
              toY: acc,
              rodStackItems: stack,
              width: 8,
              borderRadius: BorderRadius.zero,
            ),
            BarChartRodData(
              toY: out,
              color: scheme.outline,
              width: 8,
              borderRadius: BorderRadius.zero,
            ),
          ],
        ),
      );
    }
    final titles = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(zlShort(v), style: const TextStyle(fontSize: 10)),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              months[v.toInt()].month.shortLabel.split(' ').first,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
      ),
    );
    final minBal = balances.reduce((a, b) => a < b ? a : b);
    return SectionCard(
      title: 'Prognoza 12 miesięcy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            children: [
              for (final m in members) _legend(Color(m.color), m.name),
              _legend(scheme.outline, 'wydatki + oszczędności'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                barGroups: groups,
                maxY: maxY * 1.1 + 1,
                titlesData: titles,
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                      '${months[g.x].month.shortLabel}\n'
                      '${ri == 0 ? 'dochód' : 'wydatki'} ${zl(rod.toY)}',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Stan konta na koniec miesiąca',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minY: minBal < 0 ? minBal * 1.1 : 0,
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < balances.length; i++)
                        FlSpot(i.toDouble(), balances[i]),
                    ],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: scheme.primary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: scheme.primary.withValues(alpha: 0.12),
                    ),
                  ),
                ],
                titlesData: titles,
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${months[s.x.toInt()].month.shortLabel}\n${zl(s.y)}',
                          const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, color: c),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );

  Widget _budgets(CombinedMonth c) {
    final lines = [
      for (final p in c.plans)
        for (final l in p.lines)
          if (l.expense.budget) (member: p.member, line: l),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final isCurrent = c.month == YearMonth.now();
    return SectionCard(
      title: 'Budżety',
      child: Column(
        children: [
          for (final x in lines)
            _BudgetBar(
              name: c.plans.length > 1
                  ? '${x.line.expense.name} · ${x.member.name}'
                  : x.line.expense.name,
              limit: x.line.expense.amount,
              spent: x.line.spent ?? 0,
              // Share of the month gone, to compare with the bar.
              elapsed: isCurrent ? now.day / c.month.daysInMonth : null,
            ),
        ],
      ),
    );
  }

  Widget _upcoming(List<MemberData> members) {
    final up = upcomingOneOffs(members, _month, 12);
    final wishes = members.fold<int>(
      0,
      (a, m) => a + m.expenses.where((e) => e.isWish).length,
    );
    return SectionCard(
      title: 'Zaplanowane jednorazowe i roczne',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (up.isEmpty)
            const Text('Nic zaplanowanego na najbliższe 12 miesięcy.'),
          for (final x in up)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: Color(x.member.color),
                child: Text(
                  monthShort[nextDue(x.expense, _month).month - 1],
                  style: const TextStyle(fontSize: 9, color: Colors.white),
                ),
              ),
              title: Text(x.expense.name),
              subtitle: Text(
                [
                  nextDue(x.expense, _month).label,
                  if (x.expense.repeat == Repeat.yearly) 'co rok',
                  if (x.expense.spreadMonths > 1)
                    'odkładane przez ${x.expense.spreadMonths} mies.',
                  if (members.length > 1) x.member.name,
                ].join(' · '),
              ),
              trailing: Text(zl(x.expense.amount)),
            ),
          if (wishes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$wishes pozycji na liście życzeń bez terminu '
                '(Wydatki → Lista życzeń).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _BudgetBar extends StatelessWidget {
  const _BudgetBar({
    required this.name,
    required this.limit,
    required this.spent,
    this.elapsed,
  });

  final String name;
  final double limit;
  final double spent;
  final double? elapsed;

  @override
  Widget build(BuildContext context) {
    final ratio = limit > 0 ? spent / limit : 0.0;
    final over = ratio > 1;
    final ahead = elapsed != null && ratio > elapsed! + 0.1;
    final color = over
        ? Theme.of(context).colorScheme.error
        : ahead
        ? Colors.orange
        : Colors.green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(name)),
              Text('${zl(spent)} / ${zl(limit)}'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          if (limit > spent)
            Text(
              'zostało ${zl(limit - spent)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.plan, required this.showName});
  final MonthPlan plan;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final t = plan.tax;
    final m = plan.member;
    final inc = m.income;
    final hoursInfo = switch (inc.rateType) {
      RateType.hourly =>
        '${t.workDays} dni × ${inc.hoursPerDay.toStringAsFixed(0)} h = '
            '${t.hours.toStringAsFixed(0)} h × ${zl(inc.rate)}',
      RateType.daily => '${t.workDays} dni × ${zl(inc.rate)}',
      RateType.monthly => 'ryczałt miesięczny',
    };
    return SectionCard(
      title: showName ? 'Dochód · ${m.name}' : 'Dochód',
      trailing: showName
          ? CircleAvatar(backgroundColor: Color(m.color), radius: 6)
          : null,
      child: Column(
        children: [
          if (inc.b2b) ...[
            AmountRow('Przychód netto (faktura)', t.net, sub: hoursInfo),
            AmountRow(
              'VAT ${(m.tax.vatRate * 100).toStringAsFixed(0)}%',
              t.vat,
              sub: 'do zapłaty do US, faktura brutto ${zl(t.gross)}',
            ),
            AmountRow(
              'Ryczałt ${(m.tax.ryczaltRate * 100).toStringAsFixed(1).replaceAll('.0', '')}%',
              t.pit,
              negative: true,
              sub: 'podstawa ${zl(t.pitBase)}',
            ),
            AmountRow(
              'ZUS',
              t.zus,
              negative: true,
              sub:
                  'społeczne ${zl(t.social)} · FP ${zl(t.laborFund)} · '
                  'zdrowotna ${zl(t.health)} (próg ${t.healthTier})',
            ),
            AmountRow('Na rękę z B2B', t.takeHome, bold: true),
          ],
          if (plan.otherIncome > 0) AmountRow(inc.otherLabel, plan.otherIncome),
          if (inc.b2b)
            AmountRow(
              'Do odłożenia na podatki',
              t.levies,
              sub: 'VAT + ryczałt + ZUS, płatne do 20. następnego miesiąca',
              color: Theme.of(context).colorScheme.error,
            ),
        ],
      ),
    );
  }
}
