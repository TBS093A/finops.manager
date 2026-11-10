import 'package:finops_manager/domain/calendar.dart';
import 'package:finops_manager/domain/models.dart';
import 'package:finops_manager/domain/planner.dart';
import 'package:finops_manager/domain/tax.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calendar', () {
    test('Easter dates', () {
      expect(easterSunday(2026), DateTime(2026, 4, 5));
      expect(easterSunday(2027), DateTime(2027, 3, 28));
    });

    test('working days in Polish months', () {
      // 1 Nov is a Sunday, 11 Nov a Wednesday.
      expect(workingDaysIn(const YearMonth(2026, 11)), 20);
      // 15 Aug 2026 is a Saturday.
      expect(workingDaysIn(const YearMonth(2026, 8)), 21);
      // 24, 25 Dec (Thu, Fri) off; 26 is a Saturday.
      expect(workingDaysIn(const YearMonth(2026, 12)), 21);
      // Easter Monday 6 Apr 2026.
      expect(workingDaysIn(const YearMonth(2026, 4)), 21);
    });

    test('YearMonth arithmetic', () {
      const ym = YearMonth(2026, 11);
      expect(ym.add(2), const YearMonth(2027, 1));
      expect(ym.add(-11), const YearMonth(2025, 12));
      expect(YearMonth.tryParse(ym.key), ym);
    });
  });

  group('tax (ryczałt 12%, 2026)', () {
    // 20 days × 1000 zł net.
    final t = const TaxCalculator(
      TaxSettings(),
    ).compute(net: 20000, workDays: 20, hours: 160, yearlyRevenue: 20000 * 12);

    test('VAT 23%', () => expect(t.vat, 4600));
    test('invoice gross', () => expect(t.gross, 24600));

    test('full ZUS, 2026 statutory amounts (2757.34)', () {
      expect(t.pension, 1103.27);
      expect(t.disability, 452.16);
      expect(t.sickness, 138.47);
      expect(t.accident, 94.39);
      expect(t.laborFund, 138.47);
      expect(t.healthTier, 2);
      expect(t.health, 830.58);
      expect(t.zus, 2757.34);
    });

    test('ryczałt: base minus social and half of health', () {
      // 20000 - 1788.29 - 415.29 = 17796.42 → 17796 × 12% = 2135.52
      expect(t.pit, 2136);
      expect(t.takeHome, round2(20000 - 2136 - 2757.34));
    });

    test('regression: a month checked against an accountant', () {
      // 22 days × 900 zł, full ZUS with sickness insurance, 69 zł input
      // VAT (a 300 zł net purchase at 23%).
      final r = const TaxCalculator(TaxSettings()).compute(
        net: 19800,
        workDays: 22,
        hours: 176,
        yearlyRevenue: 19800 * 12,
        inputVat: 69,
      );
      expect(r.zus, 2757.34);
      expect(r.pit, 2112);
      expect(r.vat, 4554);
      expect(r.vatPayable, 4485);
      expect(r.levies, 9354.34);
      // Account inflow minus everything paid to ZUS and the tax office.
      expect(r.takeHome, 14999.66);

      // The same month without sickness insurance: what the app showed
      // before the setting was checked.
      final noSick = const TaxCalculator(TaxSettings(sickness: false)).compute(
        net: 19800,
        workDays: 22,
        hours: 176,
        yearlyRevenue: 19800 * 12,
      );
      expect(noSick.zus, 2618.87);
      expect(noSick.pit, 2128);
    });

    test('input VAT from business expenses lands in the purchase month', () {
      final m = MemberData(
        memberId: 'v',
        income: const IncomeSettings(rate: 100),
        expenses: [
          const Expense(
            id: 'acc',
            name: 'księgowość',
            amount: 369,
            categoryId: 'firma',
            start: YearMonth(2026, 1),
            vatRate: 0.23,
          ),
          const Expense(
            id: 'laptop',
            name: 'laptop',
            amount: 6150,
            categoryId: 'firma',
            repeat: Repeat.once,
            start: YearMonth(2026, 12),
            spreadMonths: 3,
            vatRate: 0.23,
          ),
        ],
        overrides: {'2026-11': const MonthOverride(inputVat: 10)},
      );
      final p = Planner(m, today: const YearMonth(2026, 11));
      expect(p.inputVat(const YearMonth(2026, 11)), 69 + 10);
      // Saved up from October, deducted only when bought in December.
      expect(p.inputVat(const YearMonth(2026, 10)), 69);
      expect(p.inputVat(const YearMonth(2026, 12)), 69 + 1150);
      final dec = p.month(const YearMonth(2026, 12));
      expect(dec.tax.vatPayable, round2(dec.tax.vat - 1219));
    });

    test('health tiers', () {
      const s = TaxSettings();
      expect(s.healthFor(s.tierFor(50000)), 498.35);
      expect(s.healthFor(s.tierFor(400000)), 1495.04);
    });

    test('start relief pays health only', () {
      final r = const TaxCalculator(TaxSettings(zusMode: ZusMode.startRelief))
          .compute(net: 10000, workDays: 20, hours: 160, yearlyRevenue: 120000);
      expect(r.social, 0);
      expect(r.laborFund, 0);
      expect(r.zus, 830.58);
    });
  });

  group('planner', () {
    MemberData member() => MemberData(
      memberId: 'a',
      name: 'A',
      income: const IncomeSettings(rate: 125),
      expenses: [
        const Expense(
          id: 'rent',
          name: 'wynajem',
          amount: 2000,
          categoryId: 'mieszkanie',
          start: YearMonth(2026, 1),
        ),
        const Expense(
          id: 'loan',
          name: 'rata',
          amount: 500,
          categoryId: 'kredyty',
          start: YearMonth(2026, 1),
          end: YearMonth(2026, 12),
        ),
        const Expense(
          id: 'bike',
          name: 'rower',
          amount: 1500,
          categoryId: 'zakupy',
          repeat: Repeat.once,
          start: YearMonth(2027, 2),
          spreadMonths: 3,
        ),
        const Expense(
          id: 'domain',
          name: 'domena',
          amount: 84,
          categoryId: 'subskrypcje',
          repeat: Repeat.yearly,
          start: YearMonth(2026, 6),
        ),
        const Expense(
          id: 'save',
          name: 'odłożyć',
          amount: 1000,
          categoryId: 'inwestycje',
          start: YearMonth(2026, 1),
        ),
        const Expense(
          id: 'food',
          name: 'jedzenie',
          amount: 3000,
          categoryId: 'codzienne',
          start: YearMonth(2026, 1),
          budget: true,
        ),
      ],
      spendings: [
        Spending(
          id: 's1',
          date: DateTime(2026, 10, 3),
          amount: 2500,
          name: 'sklep',
          budgetId: 'food',
        ),
        Spending(
          id: 's2',
          date: DateTime(2026, 11, 3),
          amount: 3200,
          name: 'sklep',
          budgetId: 'food',
        ),
      ],
    );

    test('income from working days × 8 h × rate', () {
      final p = Planner(member(), today: const YearMonth(2026, 11));
      // 20 days × 8 h × 125 = 20000
      expect(p.net(const YearMonth(2026, 11)), 20000);
      final m = p.month(const YearMonth(2026, 11));
      expect(m.tax.vat, 4600);
      expect(m.income, m.tax.takeHome);
    });

    test('days off and overrides', () {
      final m = member()
        ..overrides['2026-11'] = const MonthOverride(daysOff: 5, extraNet: 100);
      expect(Planner(m).net(const YearMonth(2026, 11)), 15 * 1000 + 100);
    });

    test('expense recurrence', () {
      final p = Planner(member(), today: const YearMonth(2026, 11));
      double cat(YearMonth ym, String c) => p.month(ym).byCategory[c] ?? 0;
      expect(cat(const YearMonth(2026, 12), 'kredyty'), 500);
      expect(cat(const YearMonth(2027, 1), 'kredyty'), 0);
      // Spread over Dec–Feb.
      expect(cat(const YearMonth(2026, 11), 'zakupy'), 0);
      expect(cat(const YearMonth(2026, 12), 'zakupy'), 500);
      expect(cat(const YearMonth(2027, 2), 'zakupy'), 500);
      expect(cat(const YearMonth(2027, 3), 'zakupy'), 0);
      expect(cat(const YearMonth(2027, 6), 'subskrypcje'), 84);
      expect(cat(const YearMonth(2027, 7), 'subskrypcje'), 0);
    });

    test('budgets: past = spent, current = max, future = limit', () {
      final p = Planner(member(), today: const YearMonth(2026, 11));
      expect(p.month(const YearMonth(2026, 10)).byCategory['codzienne'], 2500);
      expect(p.month(const YearMonth(2026, 11)).byCategory['codzienne'], 3200);
      expect(p.month(const YearMonth(2026, 12)).byCategory['codzienne'], 3000);
    });

    test('savings are not expenses', () {
      final m = Planner(
        member(),
        today: const YearMonth(2026, 11),
      ).month(const YearMonth(2026, 12));
      expect(m.savings, 1000);
      expect(m.balance, round2(m.income - m.expenses - 1000));
    });

    test('combined months sum members', () {
      final a = member();
      final b = MemberData(
        memberId: 'b',
        name: 'B',
        income: const IncomeSettings(b2b: false, otherNetMonthly: 6000),
        expenses: [
          const Expense(
            id: 'x',
            name: 'wynajem',
            amount: 1000,
            categoryId: 'mieszkanie',
            start: YearMonth(2026, 1),
          ),
        ],
      );
      final c = combine(
        [a, b],
        const YearMonth(2026, 12),
        1,
        today: const YearMonth(2026, 11),
      ).single;
      final pa = Planner(
        a,
        today: const YearMonth(2026, 11),
      ).month(const YearMonth(2026, 12));
      expect(c.income, round2(pa.income + 6000));
      expect(c.byCategory['Mieszkanie']!.amount, 3000);
    });

    test('upcoming one-offs', () {
      final up = upcomingOneOffs([member()], const YearMonth(2026, 11), 12);
      expect(up.map((x) => x.expense.id), ['bike', 'domain']);
    });

    test('json round trip', () {
      final m = member();
      final back = MemberData.fromJson(m.toJson());
      expect(back.toJson(), m.toJson());
    });
  });
}
