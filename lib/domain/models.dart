import 'calendar.dart';
import 'tax.dart';

double _d(Object? v, [double def = 0]) => (v as num?)?.toDouble() ?? def;

/// What a category of money going out means for the plan.
enum CategoryKind {
  expense('Wydatek'),
  saving('Oszczędności / inwestycje');

  const CategoryKind(this.label);
  final String label;

  static CategoryKind parse(Object? v) =>
      values.firstWhere((k) => k.name == v, orElse: () => CategoryKind.expense);
}

class Category {
  const Category({
    required this.id,
    required this.name,
    this.kind = CategoryKind.expense,
    required this.color,
  });

  final String id;
  final String name;
  final CategoryKind kind;
  final int color; // ARGB

  bool get isSaving => kind == CategoryKind.saving;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'color': color,
  };

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String,
    name: j['name'] as String? ?? '?',
    kind: CategoryKind.parse(j['kind']),
    color: (j['color'] as num?)?.toInt() ?? 0xFF9E9E9E,
  );
}

/// Starting categories; each participant can rename, add and remove them.
const defaultCategories = <Category>[
  Category(id: 'firma', name: 'Firma (poza podatkami)', color: 0xFFE53935),
  Category(id: 'mieszkanie', name: 'Mieszkanie', color: 0xFF8E24AA),
  Category(id: 'kredyty', name: 'Kredyty i raty', color: 0xFFF4511E),
  Category(id: 'subskrypcje', name: 'Subskrypcje', color: 0xFF3949AB),
  Category(id: 'codzienne', name: 'Życie codzienne', color: 0xFF00897B),
  Category(id: 'transport', name: 'Transport', color: 0xFF6D4C41),
  Category(id: 'zdrowie', name: 'Zdrowie', color: 0xFF26A69A),
  Category(id: 'wlasne', name: 'Wydatki własne', color: 0xFF7CB342),
  Category(id: 'zakupy', name: 'Zakupy planowane', color: 0xFFFFB300),
  Category(id: 'prezenty', name: 'Prezenty i darowizny', color: 0xFFD81B60),
  Category(
    id: 'inwestycje',
    name: 'Oszczędności i inwestycje',
    kind: CategoryKind.saving,
    color: 0xFF1E88E5,
  ),
];

enum Repeat {
  once('Jednorazowo'),
  monthly('Co miesiąc'),
  yearly('Co rok');

  const Repeat(this.label);
  final String label;

  static Repeat parse(Object? v) =>
      values.firstWhere((r) => r.name == v, orElse: () => Repeat.once);
}

/// A planned outflow. Recurring ones (rent, loan instalments, subscriptions)
/// run from [start] to [end]; one-off ones land in [start], optionally saved
/// up for over [spreadMonths] months ending there. Without [start] it is a
/// wish-list item that does not count in the plan yet.
class Expense {
  const Expense({
    required this.id,
    required this.name,
    required this.amount,
    required this.categoryId,
    this.repeat = Repeat.monthly,
    this.start,
    this.end,
    this.dayOfMonth,
    this.spreadMonths = 1,
    this.budget = false,
    this.note = '',
  });

  final String id;
  final String name;
  final double amount;
  final String categoryId;
  final Repeat repeat;
  final YearMonth? start;
  final YearMonth? end;
  final int? dayOfMonth;
  final int spreadMonths;

  /// A monthly spending limit (e.g. food) that the spending log draws from.
  final bool budget;
  final String note;

  bool get isWish => start == null;

  /// How much this expense takes out of [ym].
  double amountIn(YearMonth ym) {
    final s = start;
    if (s == null) return 0;
    switch (repeat) {
      case Repeat.once:
        final n = spreadMonths < 1 ? 1 : spreadMonths;
        final first = s.add(-(n - 1));
        if (ym < first || ym > s) return 0;
        return round2(amount / n);
      case Repeat.monthly:
        if (ym < s) return 0;
        if (end != null && ym > end!) return 0;
        return amount;
      case Repeat.yearly:
        if (ym < s) return 0;
        if (end != null && ym > end!) return 0;
        return ym.month == s.month ? amount : 0;
    }
  }

  /// Whether this expense falls in [ym] at all (also with no amount yet).
  bool activeIn(YearMonth ym) => copyWith(amount: 1).amountIn(ym) > 0;

  /// Instalments left from [from] on, for monthly expenses with an end.
  int? remainingFrom(YearMonth from) {
    if (repeat != Repeat.monthly || end == null || start == null) return null;
    final first = from > start! ? from : start!;
    final n = first.monthsUntil(end!) + 1;
    return n < 0 ? 0 : n;
  }

  Expense copyWith({
    String? name,
    double? amount,
    String? categoryId,
    Repeat? repeat,
    YearMonth? Function()? start,
    YearMonth? Function()? end,
    int? Function()? dayOfMonth,
    int? spreadMonths,
    bool? budget,
    String? note,
  }) => Expense(
    id: id,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    categoryId: categoryId ?? this.categoryId,
    repeat: repeat ?? this.repeat,
    start: start != null ? start() : this.start,
    end: end != null ? end() : this.end,
    dayOfMonth: dayOfMonth != null ? dayOfMonth() : this.dayOfMonth,
    spreadMonths: spreadMonths ?? this.spreadMonths,
    budget: budget ?? this.budget,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'cat': categoryId,
    'repeat': repeat.name,
    if (start != null) 'start': start!.key,
    if (end != null) 'end': end!.key,
    if (dayOfMonth != null) 'day': dayOfMonth,
    if (spreadMonths != 1) 'spread': spreadMonths,
    if (budget) 'budget': true,
    if (note.isNotEmpty) 'note': note,
  };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    amount: _d(j['amount']),
    categoryId: j['cat'] as String? ?? 'wlasne',
    repeat: Repeat.parse(j['repeat']),
    start: YearMonth.tryParse(j['start'] as String?),
    end: YearMonth.tryParse(j['end'] as String?),
    dayOfMonth: (j['day'] as num?)?.toInt(),
    spreadMonths: (j['spread'] as num?)?.toInt() ?? 1,
    budget: j['budget'] as bool? ?? false,
    note: j['note'] as String? ?? '',
  );
}

/// One actual purchase from the spending log, drawn from a budget expense.
class Spending {
  const Spending({
    required this.id,
    required this.date,
    required this.amount,
    required this.name,
    required this.budgetId,
  });

  final String id;
  final DateTime date;
  final double amount;
  final String name;
  final String budgetId;

  YearMonth get month => YearMonth.of(date);

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String().substring(0, 10),
    'amount': amount,
    'name': name,
    'budget': budgetId,
  };

  factory Spending.fromJson(Map<String, dynamic> j) => Spending(
    id: j['id'] as String,
    date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime(2000),
    amount: _d(j['amount']),
    name: j['name'] as String? ?? '',
    budgetId: j['budget'] as String? ?? '',
  );
}

/// How the participant earns.
class IncomeSettings {
  const IncomeSettings({
    this.b2b = true,
    this.rateType = RateType.hourly,
    this.rate = 0,
    this.hoursPerDay = 8,
    this.otherNetMonthly = 0,
    this.otherLabel = 'Inny dochód netto',
  });

  /// Invoices as a sole trader on ryczałt.
  final bool b2b;
  final RateType rateType;

  /// Net (without VAT) per hour, per day or per month.
  final double rate;
  final double hoursPerDay;

  /// Salary, 800+, rent income… already net, added on top.
  final double otherNetMonthly;
  final String otherLabel;

  IncomeSettings copyWith({
    bool? b2b,
    RateType? rateType,
    double? rate,
    double? hoursPerDay,
    double? otherNetMonthly,
    String? otherLabel,
  }) => IncomeSettings(
    b2b: b2b ?? this.b2b,
    rateType: rateType ?? this.rateType,
    rate: rate ?? this.rate,
    hoursPerDay: hoursPerDay ?? this.hoursPerDay,
    otherNetMonthly: otherNetMonthly ?? this.otherNetMonthly,
    otherLabel: otherLabel ?? this.otherLabel,
  );

  Map<String, dynamic> toJson() => {
    'b2b': b2b,
    'rateType': rateType.name,
    'rate': rate,
    'hoursPerDay': hoursPerDay,
    'otherNetMonthly': otherNetMonthly,
    'otherLabel': otherLabel,
  };

  factory IncomeSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const IncomeSettings();
    return IncomeSettings(
      b2b: j['b2b'] as bool? ?? true,
      rateType: RateType.parse(j['rateType']),
      rate: _d(j['rate']),
      hoursPerDay: _d(j['hoursPerDay'], 8),
      otherNetMonthly: _d(j['otherNetMonthly']),
      otherLabel: j['otherLabel'] as String? ?? 'Inny dochód netto',
    );
  }
}

/// Per-month corrections: holidays taken, a different number of days,
/// a bonus.
class MonthOverride {
  const MonthOverride({
    this.workDays,
    this.daysOff = 0,
    this.extraNet = 0,
    this.note = '',
  });

  /// Replaces the computed number of working days.
  final int? workDays;

  /// Days of leave (unpaid on B2B) taken this month.
  final int daysOff;

  /// Extra invoiced amount (net), taxed like the rest.
  final double extraNet;
  final String note;

  bool get isEmpty =>
      workDays == null && daysOff == 0 && extraNet == 0 && note.isEmpty;

  Map<String, dynamic> toJson() => {
    if (workDays != null) 'workDays': workDays,
    if (daysOff != 0) 'daysOff': daysOff,
    if (extraNet != 0) 'extraNet': extraNet,
    if (note.isNotEmpty) 'note': note,
  };

  factory MonthOverride.fromJson(Map<String, dynamic> j) => MonthOverride(
    workDays: (j['workDays'] as num?)?.toInt(),
    daysOff: (j['daysOff'] as num?)?.toInt() ?? 0,
    extraNet: _d(j['extraNet']),
    note: j['note'] as String? ?? '',
  );
}

/// Everything one participant owns. Each participant edits only their own;
/// the others receive it read-only over P2P.
class MemberData {
  MemberData({
    required this.memberId,
    this.name = '',
    this.color = 0xFF1E88E5,
    this.income = const IncomeSettings(),
    this.tax = const TaxSettings(),
    Map<String, MonthOverride>? overrides,
    List<Category>? categories,
    List<Expense>? expenses,
    List<Spending>? spendings,
    this.startingBalance = 0,
    this.balanceMonth,
    this.rev = 0,
    DateTime? updatedAt,
  }) : overrides = overrides ?? {},
       categories = categories ?? List.of(defaultCategories),
       expenses = expenses ?? [],
       spendings = spendings ?? [],
       updatedAt = updatedAt ?? DateTime.now();

  final String memberId;
  String name;
  int color;
  IncomeSettings income;
  TaxSettings tax;
  final Map<String, MonthOverride> overrides;
  final List<Category> categories;
  final List<Expense> expenses;
  final List<Spending> spendings;

  /// Money on the account at the start of [balanceMonth].
  double startingBalance;
  YearMonth? balanceMonth;

  /// Bumped on every local change; peers keep the highest they saw.
  int rev;
  DateTime updatedAt;

  Category category(String id) => categories.firstWhere(
    (c) => c.id == id,
    orElse: () => defaultCategories.firstWhere(
      (c) => c.id == id,
      orElse: () => Category(id: id, name: id, color: 0xFF9E9E9E),
    ),
  );

  MonthOverride overrideFor(YearMonth ym) =>
      overrides[ym.key] ?? const MonthOverride();

  Map<String, dynamic> toJson() => {
    'v': 1,
    'memberId': memberId,
    'name': name,
    'color': color,
    'income': income.toJson(),
    'tax': tax.toJson(),
    'overrides': {
      for (final e in overrides.entries)
        if (!e.value.isEmpty) e.key: e.value.toJson(),
    },
    'categories': [for (final c in categories) c.toJson()],
    'expenses': [for (final e in expenses) e.toJson()],
    'spendings': [for (final s in spendings) s.toJson()],
    'startingBalance': startingBalance,
    if (balanceMonth != null) 'balanceMonth': balanceMonth!.key,
    'rev': rev,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory MemberData.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) => [
      for (final e in (j[k] as List?) ?? const [])
        if (e is Map<String, dynamic>) f(e),
    ];
    final cats = list('categories', Category.fromJson);
    return MemberData(
      memberId: j['memberId'] as String,
      name: j['name'] as String? ?? '',
      color: (j['color'] as num?)?.toInt() ?? 0xFF1E88E5,
      income: IncomeSettings.fromJson(j['income'] as Map<String, dynamic>?),
      tax: TaxSettings.fromJson(j['tax'] as Map<String, dynamic>?),
      overrides: {
        for (final e
            in ((j['overrides'] as Map<String, dynamic>?) ?? const {}).entries)
          e.key: MonthOverride.fromJson(e.value as Map<String, dynamic>),
      },
      categories: cats.isEmpty ? null : cats,
      expenses: list('expenses', Expense.fromJson),
      spendings: list('spendings', Spending.fromJson),
      startingBalance: _d(j['startingBalance']),
      balanceMonth: YearMonth.tryParse(j['balanceMonth'] as String?),
      rev: (j['rev'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
    );
  }
}
