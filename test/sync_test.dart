import 'dart:math';
import 'dart:typed_data';

import 'package:finops_manager/domain/calendar.dart';
import 'package:finops_manager/domain/models.dart';
import 'package:finops_manager/sync/codec.dart';
import 'package:finops_manager/sync/invite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MemberData big() {
    final m = MemberData(memberId: 'm1', name: 'Anna');
    final rnd = Random(1);
    for (var i = 0; i < 40; i++) {
      m.expenses.add(
        Expense(
          id: 'e$i',
          name: 'pozycja $i',
          amount: rnd.nextInt(200000) / 100,
          categoryId: defaultCategories[i % defaultCategories.length].id,
          repeat: Repeat.values[i % Repeat.values.length],
          start: i % 7 == 0 ? null : const YearMonth(2026, 11).add(i % 12),
        ),
      );
    }
    for (var i = 0; i < 3000; i++) {
      m.spendings.add(
        Spending(
          id: 'id-$i-${rnd.nextInt(1 << 30)}',
          date: DateTime(2026, 1 + i % 12, 1 + i % 28),
          amount: rnd.nextInt(50000) / 100,
          name: 'zakupy ${rnd.nextInt(1 << 20)}',
          budgetId: m.expenses.first.id,
        ),
      );
    }
    return m;
  }

  test('member data survives encode/decode across chunks', () {
    final m = big();
    final enc = encodeMember(m.toJson(), 7);
    expect(enc.chunks.length, greaterThan(1));
    expect(enc.head['rev'], 7);
    final back = decodeMember(enc.head, enc.chunks);
    expect(back, isNotNull);
    expect(MemberData.fromJson(back!).toJson(), m.toJson());
  });

  test('chunks of another revision are rejected', () {
    final m = big();
    final a = encodeMember(m.toJson(), 1);
    m.name = 'X';
    final b = encodeMember(m.toJson(), 2);
    final mixed = <Uint8List?>[b.chunks.first, ...a.chunks.skip(1)];
    expect(decodeMember(b.head, mixed), isNull);
    expect(decodeMember(b.head, [b.chunks.first, null]), isNull);
  });

  test('every chunk fits a Veilid subkey', () {
    final enc = encodeMember(big().toJson(), 3);
    for (final c in enc.chunks) {
      expect(c.length, lessThanOrEqualTo(32 * 1024));
    }
  });

  test('invite round trip and rejection of foreign codes', () {
    const inv = HouseholdInvite(
      name: 'Dom',
      rosterKey: 'VLD0:abc',
      rosterWriter: 'VLD0:pub:sec',
    );
    final back = HouseholdInvite.tryParse(inv.encode())!;
    expect(back.name, 'Dom');
    expect(back.rosterKey, inv.rosterKey);
    expect(back.rosterWriter, inv.rosterWriter);
    expect(HouseholdInvite.tryParse('p2pc1.eyJ9'), isNull);
    expect(HouseholdInvite.tryParse('finops1.!!!'), isNull);
  });
}
