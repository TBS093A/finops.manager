/// A calendar month. Comparable and usable as a map key ("2026-11").
class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month) : assert(month >= 1 && month <= 12);

  factory YearMonth.fromIndex(int index) =>
      YearMonth(index ~/ 12, index % 12 + 1);

  factory YearMonth.now() {
    final n = DateTime.now();
    return YearMonth(n.year, n.month);
  }

  factory YearMonth.of(DateTime d) => YearMonth(d.year, d.month);

  static YearMonth? tryParse(String? s) {
    if (s == null) return null;
    final parts = s.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return null;
    return YearMonth(y, m);
  }

  final int year;
  final int month;

  /// Months since year 0; consecutive months differ by one.
  int get index => year * 12 + month - 1;

  YearMonth add(int months) => YearMonth.fromIndex(index + months);
  int monthsUntil(YearMonth other) => other.index - index;

  int get daysInMonth => DateTime(year, month + 1, 0).day;

  String get key =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  String get label => '${monthNames[month - 1]} $year';
  String get shortLabel =>
      '${monthShort[month - 1]} ${(year % 100).toString().padLeft(2, '0')}';

  bool operator <(YearMonth o) => index < o.index;
  bool operator <=(YearMonth o) => index <= o.index;
  bool operator >(YearMonth o) => index > o.index;
  bool operator >=(YearMonth o) => index >= o.index;

  @override
  int compareTo(YearMonth other) => index.compareTo(other.index);

  @override
  bool operator ==(Object other) => other is YearMonth && other.index == index;

  @override
  int get hashCode => index;

  @override
  String toString() => key;
}

const monthNames = [
  'Styczeń',
  'Luty',
  'Marzec',
  'Kwiecień',
  'Maj',
  'Czerwiec',
  'Lipiec',
  'Sierpień',
  'Wrzesień',
  'Październik',
  'Listopad',
  'Grudzień',
];

const monthShort = [
  'sty',
  'lut',
  'mar',
  'kwi',
  'maj',
  'cze',
  'lip',
  'sie',
  'wrz',
  'paź',
  'lis',
  'gru',
];

/// Easter Sunday (Gregorian, anonymous algorithm).
DateTime easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = (h + l - 7 * m + 114) % 31 + 1;
  return DateTime(year, month, day);
}

/// Polish statutory days off (ustawa o dniach wolnych od pracy).
/// Christmas Eve is a day off since 2025.
Set<DateTime> polishHolidays(int year) {
  final easter = easterSunday(year);
  DateTime plus(int days) =>
      DateTime(easter.year, easter.month, easter.day + days);
  return {
    DateTime(year, 1, 1),
    DateTime(year, 1, 6),
    easter,
    plus(1), // Poniedziałek Wielkanocny
    DateTime(year, 5, 1),
    DateTime(year, 5, 3),
    plus(49), // Zielone Świątki
    plus(60), // Boże Ciało
    DateTime(year, 8, 15),
    DateTime(year, 11, 1),
    DateTime(year, 11, 11),
    if (year >= 2025) DateTime(year, 12, 24),
    DateTime(year, 12, 25),
    DateTime(year, 12, 26),
  };
}

final _holidayCache = <int, Set<DateTime>>{};

bool isWorkingDay(DateTime d) {
  if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
    return false;
  }
  final h = _holidayCache.putIfAbsent(d.year, () => polishHolidays(d.year));
  return !h.contains(DateTime(d.year, d.month, d.day));
}

/// Mon–Fri days of [ym] that are not public holidays.
int workingDaysIn(YearMonth ym) {
  var n = 0;
  for (var day = 1; day <= ym.daysInMonth; day++) {
    if (isWorkingDay(DateTime(ym.year, ym.month, day))) n++;
  }
  return n;
}
