import 'dart:convert';

/// Household invite shown as a QR code. It carries the roster record key
/// (with its encryption secret) and the roster writer key pair, so holding
/// it IS membership: show it only in person, to people you want in.
class HouseholdInvite {
  const HouseholdInvite({
    required this.name,
    required this.rosterKey,
    required this.rosterWriter,
  });

  static const _prefix = 'finops1.';

  final String name;
  final String rosterKey;
  final String rosterWriter;

  String encode() =>
      _prefix +
      base64Url
          .encode(
            utf8.encode(
              jsonEncode({'n': name, 'r': rosterKey, 'w': rosterWriter}),
            ),
          )
          .replaceAll('=', '');

  static HouseholdInvite? tryParse(String raw) {
    final s = raw.trim();
    if (!s.startsWith(_prefix)) return null;
    try {
      final body = base64Url.normalize(s.substring(_prefix.length));
      final j = jsonDecode(
        utf8.decode(base64Url.decode(body)),
      ) as Map<String, dynamic>;
      return HouseholdInvite(
        name: j['n'] as String,
        rosterKey: j['r'] as String,
        rosterWriter: j['w'] as String,
      );
    } on Object {
      return null;
    }
  }
}

/// What this phone keeps about the household it belongs to.
class HouseholdSecrets {
  const HouseholdSecrets({
    required this.name,
    required this.rosterKey,
    required this.rosterWriter,
    required this.outboxKey,
    required this.outboxWriter,
    required this.slot,
  });

  final String name;
  final String rosterKey;
  final String rosterWriter;
  final String outboxKey;
  final String outboxWriter;
  final int slot;

  HouseholdInvite get invite => HouseholdInvite(
    name: name,
    rosterKey: rosterKey,
    rosterWriter: rosterWriter,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'rosterKey': rosterKey,
    'rosterWriter': rosterWriter,
    'outboxKey': outboxKey,
    'outboxWriter': outboxWriter,
    'slot': slot,
  };

  factory HouseholdSecrets.fromJson(Map<String, dynamic> j) => HouseholdSecrets(
    name: j['name'] as String,
    rosterKey: j['rosterKey'] as String,
    rosterWriter: j['rosterWriter'] as String,
    outboxKey: j['outboxKey'] as String,
    outboxWriter: j['outboxWriter'] as String,
    slot: (j['slot'] as num).toInt(),
  );
}
