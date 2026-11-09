/// Monthly B2B income and public levies for a sole trader on lump-sum tax
/// (ryczałt od przychodów ewidencjonowanych).
///
/// Defaults are the 2026 values. They change every January, so they are all
/// editable in the app (Dochód → Parametry ZUS).
library;

double round2(double v) => (v * 100).roundToDouble() / 100;

enum ZusMode {
  full('Pełny ZUS'),
  preferential('Preferencyjny (mały ZUS)'),
  startRelief('Ulga na start (tylko zdrowotna)'),
  none('Brak (np. etat obok)');

  const ZusMode(this.label);
  final String label;

  static ZusMode parse(Object? v) =>
      values.firstWhere((m) => m.name == v, orElse: () => ZusMode.full);
}

enum RateType {
  hourly('Stawka godzinowa'),
  daily('Stawka dzienna'),
  monthly('Ryczałt miesięczny');

  const RateType(this.label);
  final String label;

  static RateType parse(Object? v) =>
      values.firstWhere((m) => m.name == v, orElse: () => RateType.hourly);
}

class TaxSettings {
  const TaxSettings({
    this.ryczaltRate = 0.12,
    this.vatRate = 0.23,
    this.vatPayer = true,
    this.zusMode = ZusMode.full,
    this.sickness = true,
    this.fullBase = 5652.00,
    this.preferentialBase = 1441.80,
    this.accidentRate = 0.0167,
    this.avgWage = 9228.64,
    this.healthTier = 0,
    this.deductSocial = true,
    this.deductHalfHealth = true,
  });

  /// 0.12 for IT services (PKWiU 62.0x), 0.085 / 0.15 / 0.17 for others.
  final double ryczaltRate;
  final double vatRate;
  final bool vatPayer;
  final ZusMode zusMode;

  /// Voluntary sickness insurance (chorobowe).
  final bool sickness;

  /// Social contribution base: 60% of the forecast average wage (2026).
  final double fullBase;

  /// 30% of the minimum wage (2026: 4806 zł).
  final double preferentialBase;
  final double accidentRate;

  /// Average wage in Q4 of the previous year; the ryczałt health contribution
  /// is 9% of 60% / 100% / 180% of it, by yearly revenue.
  final double avgWage;

  /// 0 = pick from the projected yearly revenue, 1..3 = fixed tier.
  final int healthTier;
  final bool deductSocial;
  final bool deductHalfHealth;

  TaxSettings copyWith({
    double? ryczaltRate,
    double? vatRate,
    bool? vatPayer,
    ZusMode? zusMode,
    bool? sickness,
    double? fullBase,
    double? preferentialBase,
    double? accidentRate,
    double? avgWage,
    int? healthTier,
    bool? deductSocial,
    bool? deductHalfHealth,
  }) => TaxSettings(
    ryczaltRate: ryczaltRate ?? this.ryczaltRate,
    vatRate: vatRate ?? this.vatRate,
    vatPayer: vatPayer ?? this.vatPayer,
    zusMode: zusMode ?? this.zusMode,
    sickness: sickness ?? this.sickness,
    fullBase: fullBase ?? this.fullBase,
    preferentialBase: preferentialBase ?? this.preferentialBase,
    accidentRate: accidentRate ?? this.accidentRate,
    avgWage: avgWage ?? this.avgWage,
    healthTier: healthTier ?? this.healthTier,
    deductSocial: deductSocial ?? this.deductSocial,
    deductHalfHealth: deductHalfHealth ?? this.deductHalfHealth,
  );

  Map<String, dynamic> toJson() => {
    'ryczaltRate': ryczaltRate,
    'vatRate': vatRate,
    'vatPayer': vatPayer,
    'zusMode': zusMode.name,
    'sickness': sickness,
    'fullBase': fullBase,
    'preferentialBase': preferentialBase,
    'accidentRate': accidentRate,
    'avgWage': avgWage,
    'healthTier': healthTier,
    'deductSocial': deductSocial,
    'deductHalfHealth': deductHalfHealth,
  };

  factory TaxSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const TaxSettings();
    const d = TaxSettings();
    double n(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return TaxSettings(
      ryczaltRate: n('ryczaltRate', d.ryczaltRate),
      vatRate: n('vatRate', d.vatRate),
      vatPayer: j['vatPayer'] as bool? ?? d.vatPayer,
      zusMode: ZusMode.parse(j['zusMode']),
      sickness: j['sickness'] as bool? ?? d.sickness,
      fullBase: n('fullBase', d.fullBase),
      preferentialBase: n('preferentialBase', d.preferentialBase),
      accidentRate: n('accidentRate', d.accidentRate),
      avgWage: n('avgWage', d.avgWage),
      healthTier: (j['healthTier'] as num?)?.toInt() ?? 0,
      deductSocial: j['deductSocial'] as bool? ?? true,
      deductHalfHealth: j['deductHalfHealth'] as bool? ?? true,
    );
  }

  /// Health tier for a yearly revenue: ≤60k, ≤300k, above.
  int tierFor(double yearlyRevenue) {
    if (healthTier >= 1 && healthTier <= 3) return healthTier;
    if (yearlyRevenue <= 60000) return 1;
    if (yearlyRevenue <= 300000) return 2;
    return 3;
  }

  double healthFor(int tier) =>
      round2(avgWage * const [0.6, 1.0, 1.8][tier - 1] * 0.09);
}

/// Everything one month of B2B work costs and leaves.
class MonthTax {
  const MonthTax({
    required this.workDays,
    required this.hours,
    required this.net,
    required this.vat,
    required this.pension,
    required this.disability,
    required this.sickness,
    required this.accident,
    required this.laborFund,
    required this.health,
    required this.healthTier,
    required this.pitBase,
    required this.pit,
  });

  static const zero = MonthTax(
    workDays: 0,
    hours: 0,
    net: 0,
    vat: 0,
    pension: 0,
    disability: 0,
    sickness: 0,
    accident: 0,
    laborFund: 0,
    health: 0,
    healthTier: 1,
    pitBase: 0,
    pit: 0,
  );

  final int workDays;
  final double hours;

  /// Invoiced amount without VAT (przychód).
  final double net;
  final double vat;
  final double pension; // emerytalne 19.52%
  final double disability; // rentowe 8%
  final double sickness; // chorobowe 2.45%
  final double accident; // wypadkowe
  final double laborFund; // Fundusz Pracy + FS 2.45%
  final double health; // zdrowotna
  final int healthTier;
  final double pitBase;
  final double pit; // ryczałt

  /// Invoice total, what lands on the account.
  double get gross => round2(net + vat);
  double get social => round2(pension + disability + sickness + accident);
  double get zus => round2(social + laborFund + health);
  double get levies => round2(vat + pit + zus);

  /// What stays after VAT, ryczałt and ZUS.
  double get takeHome => round2(net - pit - zus);
}

class TaxCalculator {
  const TaxCalculator(this.s);
  final TaxSettings s;

  MonthTax compute({
    required double net,
    required int workDays,
    required double hours,
    required double yearlyRevenue,
    bool active = true,
  }) {
    if (!active) return MonthTax.zero;
    final vat = s.vatPayer ? round2(net * s.vatRate) : 0.0;

    double base;
    var fp = false;
    switch (s.zusMode) {
      case ZusMode.full:
        base = s.fullBase;
        fp = true;
      case ZusMode.preferential:
        base = s.preferentialBase;
      case ZusMode.startRelief:
      case ZusMode.none:
        base = 0;
    }
    final pension = round2(base * 0.1952);
    final disability = round2(base * 0.08);
    final sickness = s.sickness ? round2(base * 0.0245) : 0.0;
    final accident = round2(base * s.accidentRate);
    final laborFund = fp ? round2(base * 0.0245) : 0.0;

    final tier = s.tierFor(yearlyRevenue);
    final health = s.zusMode == ZusMode.none ? 0.0 : s.healthFor(tier);

    var pitBase = net;
    if (s.deductSocial) {
      pitBase -= pension + disability + sickness + accident;
    }
    if (s.deductHalfHealth) pitBase -= health / 2;
    if (pitBase < 0) pitBase = 0;
    // Ryczałt is paid in whole złoty.
    final pit = (pitBase.round() * s.ryczaltRate).roundToDouble();

    return MonthTax(
      workDays: workDays,
      hours: hours,
      net: round2(net),
      vat: vat,
      pension: pension,
      disability: disability,
      sickness: sickness,
      accident: accident,
      laborFund: laborFund,
      health: health,
      healthTier: tier,
      pitBase: round2(pitBase),
      pit: pit,
    );
  }
}
