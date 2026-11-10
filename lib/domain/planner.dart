import 'calendar.dart';
import 'models.dart';
import 'tax.dart';

/// One expense's share of a month.
class PlanLine {
  const PlanLine(this.expense, this.amount, {this.spent});
  final Expense expense;
  final double amount;

  /// Budgets only: what the spending log shows for the month.
  final double? spent;
}

/// One participant's month: income after levies, planned outflows, balance.
class MonthPlan {
  MonthPlan({
    required this.member,
    required this.month,
    required this.tax,
    required this.otherIncome,
    required this.lines,
  });

  final MemberData member;
  final YearMonth month;
  final MonthTax tax;
  final double otherIncome;
  final List<PlanLine> lines;

  /// Net income: B2B after VAT, ryczałt and ZUS, plus other net income.
  double get income => round2(tax.takeHome + otherIncome);

  /// Money arriving on the account (invoices with VAT + other income).
  double get inflow => round2(tax.gross + otherIncome);

  double get expenses => round2(
    lines
        .where((l) => !member.category(l.expense.categoryId).isSaving)
        .fold(0.0, (s, l) => s + l.amount),
  );

  double get savings => round2(
    lines
        .where((l) => member.category(l.expense.categoryId).isSaving)
        .fold(0.0, (s, l) => s + l.amount),
  );

  /// What is left after expenses and savings.
  double get balance => round2(income - expenses - savings);

  Map<String, double> get byCategory {
    final m = <String, double>{};
    for (final l in lines) {
      m.update(
        l.expense.categoryId,
        (v) => v + l.amount,
        ifAbsent: () => l.amount,
      );
    }
    return m;
  }
}

class Planner {
  Planner(this.member, {YearMonth? today}) : today = today ?? YearMonth.now();

  final MemberData member;
  final YearMonth today;
  final _netCache = <int, double>{};

  int workDays(YearMonth ym) {
    final o = member.overrideFor(ym);
    final days = (o.workDays ?? workingDaysIn(ym)) - o.daysOff;
    return days < 0 ? 0 : days;
  }

  /// Invoiced amount without VAT for [ym].
  double net(YearMonth ym) => _netCache.putIfAbsent(ym.index, () {
    final inc = member.income;
    if (!inc.b2b) return 0;
    final o = member.overrideFor(ym);
    final days = workDays(ym);
    final base = switch (inc.rateType) {
      RateType.hourly => days * inc.hoursPerDay * inc.rate,
      RateType.daily => days * inc.rate,
      RateType.monthly => inc.rate,
    };
    return round2(base + o.extraNet);
  });

  double yearlyRevenue(int year) {
    var sum = 0.0;
    for (var m = 1; m <= 12; m++) {
      sum += net(YearMonth(year, m));
    }
    return sum;
  }

  /// Input VAT of [ym]: business expenses on VAT invoices plus the month's
  /// manual correction.
  double inputVat(YearMonth ym) => round2(
    member.expenses.fold(0.0, (a, e) => a + e.inputVatIn(ym)) +
        member.overrideFor(ym).inputVat,
  );

  double spentIn(String budgetId, YearMonth ym) => round2(
    member.spendings
        .where((s) => s.budgetId == budgetId && s.month == ym)
        .fold(0.0, (a, s) => a + s.amount),
  );

  MonthPlan month(YearMonth ym) {
    final inc = member.income;
    final days = workDays(ym);
    final tax = TaxCalculator(member.tax).compute(
      net: net(ym),
      workDays: days,
      hours: days * inc.hoursPerDay,
      yearlyRevenue: yearlyRevenue(ym.year),
      inputVat: inputVat(ym),
      active: inc.b2b,
    );
    final lines = <PlanLine>[];
    for (final e in member.expenses) {
      final planned = e.amountIn(ym);
      if (!e.activeIn(ym)) continue;
      if (!e.budget) {
        if (planned <= 0) continue;
        lines.add(PlanLine(e, planned));
        continue;
      }
      // Budgets: the past counts what was really spent, the current month
      // at least the limit, the future the limit.
      final spent = spentIn(e.id, ym);
      final amount = ym < today
          ? spent
          : (ym == today && spent > planned ? spent : planned);
      lines.add(PlanLine(e, amount, spent: spent));
    }
    lines.sort((a, b) => b.amount.compareTo(a.amount));
    return MonthPlan(
      member: member,
      month: ym,
      tax: tax,
      otherIncome: inc.otherNetMonthly,
      lines: lines,
    );
  }

  List<MonthPlan> range(YearMonth from, int months) => [
    for (var i = 0; i < months; i++) month(from.add(i)),
  ];

  /// Expected account balance at the end of each month of [plans]
  /// (consecutive), starting from the member's known balance.
  List<double> runningBalance(List<MonthPlan> plans) {
    if (plans.isEmpty) return const [];
    final anchor = member.balanceMonth ?? plans.first.month;
    var acc = member.startingBalance;
    // Months between the anchor and the first plotted month count too.
    for (var ym = anchor; ym < plans.first.month; ym = ym.add(1)) {
      acc += month(ym).balance;
    }
    final out = <double>[];
    for (final p in plans) {
      if (p.month >= anchor) acc += p.balance;
      out.add(round2(acc));
    }
    return out;
  }
}

/// Several participants' months laid over each other.
class CombinedMonth {
  CombinedMonth(this.month, this.plans);
  final YearMonth month;
  final List<MonthPlan> plans;

  double _sum(double Function(MonthPlan) f) =>
      round2(plans.fold(0.0, (a, p) => a + f(p)));

  double get income => _sum((p) => p.income);
  double get inflow => _sum((p) => p.inflow);
  double get expenses => _sum((p) => p.expenses);
  double get savings => _sum((p) => p.savings);
  double get balance => _sum((p) => p.balance);

  /// VAT to pay (output minus input VAT).
  double get vat => _sum((p) => p.tax.vatPayable);
  double get pit => _sum((p) => p.tax.pit);
  double get zus => _sum((p) => p.tax.zus);

  /// Category name -> amount, across members (names, since each member may
  /// define their own categories).
  Map<String, ({double amount, int color, bool saving})> get byCategory {
    final m = <String, ({double amount, int color, bool saving})>{};
    for (final p in plans) {
      for (final e in p.byCategory.entries) {
        final c = p.member.category(e.key);
        final prev = m[c.name];
        m[c.name] = (
          amount: round2((prev?.amount ?? 0) + e.value),
          color: prev?.color ?? c.color,
          saving: c.isSaving,
        );
      }
    }
    return m;
  }
}

/// Plans of every selected member over [months] months from [from].
List<CombinedMonth> combine(
  List<MemberData> members,
  YearMonth from,
  int months, {
  YearMonth? today,
}) {
  final planners = [for (final m in members) Planner(m, today: today)];
  return [
    for (var i = 0; i < months; i++)
      CombinedMonth(from.add(i), [
        for (final p in planners) p.month(from.add(i)),
      ]),
  ];
}

/// Upcoming one-off expenses (the easy-to-forget ones) of [members] within
/// [months] months from [from], soonest first.
List<({MemberData member, Expense expense})> upcomingOneOffs(
  List<MemberData> members,
  YearMonth from,
  int months,
) {
  final out = <({MemberData member, Expense expense})>[];
  final until = from.add(months - 1);
  for (final m in members) {
    for (final e in m.expenses) {
      if (e.start == null || e.repeat == Repeat.monthly) continue;
      final due = nextDue(e, from);
      if (due < from || due > until) continue;
      if (e.end != null && due > e.end!) continue;
      out.add((member: m, expense: e));
    }
  }
  out.sort(
    (a, b) => nextDue(a.expense, from).compareTo(nextDue(b.expense, from)),
  );
  return out;
}

/// When a one-off or yearly expense next falls, from [from] on.
YearMonth nextDue(Expense e, YearMonth from) {
  if (e.repeat != Repeat.yearly || e.start == null) return e.start ?? from;
  var ym = YearMonth(from.year, e.start!.month);
  if (ym < from) ym = ym.add(12);
  if (ym < e.start!) ym = e.start!;
  return ym;
}
