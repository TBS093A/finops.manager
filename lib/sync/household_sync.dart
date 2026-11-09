import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:veilid/veilid.dart';

import 'codec.dart';
import 'dht.dart';
import 'invite.dart';
import 'veilid_node.dart';

/// Household layout on the Veilid DHT (same pattern as p2p.communicator):
///
/// * roster record (DFLT, [rosterSubkeys] subkeys, writer key shared through
///   the QR invite): subkey 0 = {name}, subkeys 1.. = one member entry each
///   {o: outbox record key, id: member id, n: name};
/// * one outbox record per member (DFLT, writer key known only to that
///   member's phone): their whole data set, see [OutboxLayout].
///
/// Everyone writes only their own outbox and reads everyone else's. Values
/// are encrypted with the record keys' secrets, which only members have.
class HouseholdLayout {
  static const rosterSubkeys = 16;
}

class HouseholdFullException implements Exception {
  @override
  String toString() => 'Gospodarstwo ma już komplet uczestników';
}

class HouseholdNotFoundException implements Exception {
  @override
  String toString() => 'Nie znaleziono gospodarstwa (zły kod QR?)';
}

class RosterMember {
  RosterMember({required this.outbox, required this.memberId, this.name = ''});
  final String outbox;
  final String memberId;
  String name;
  int rev = 0;
  DateTime? lastSync;
}

class HouseholdSync extends ChangeNotifier {
  HouseholdSync({
    required this.secrets,
    required this.myMemberId,
    required this.onMemberData,
  });

  final HouseholdSecrets secrets;
  final String myMemberId;

  /// Called with a peer's full data set whenever a newer revision arrives.
  final void Function(Map<String, dynamic> json) onMemberData;

  /// Other members, by outbox key.
  final Map<String, RosterMember> members = {};
  String? error;
  bool connected = false;
  DateTime? lastPublished;

  late final RecordKey _rosterKey = RecordKey.fromString(secrets.rosterKey);
  late final KeyPair _rosterWriter = KeyPair.fromString(secrets.rosterWriter);
  late final RecordKey _outboxKey = RecordKey.fromString(secrets.outboxKey);
  late final KeyPair _outboxWriter = KeyPair.fromString(secrets.outboxWriter);

  final _watched = <String, RecordKey>{};
  StreamSubscription<VeilidUpdate>? _sub;
  Timer? _poll;
  Timer? _publishTimer;
  Future<void>? _syncing;
  Future<void> _publishChain = Future.value();
  Map<String, dynamic>? _pending;
  int _publishedRev = -1;
  bool _closed = false;

  // ------------------------------------------------------------ creation

  static Future<HouseholdSecrets> create({
    required String name,
    required String memberId,
    required String myName,
  }) async {
    await VeilidNode.instance.waitUntilOnline(
      timeout: const Duration(seconds: 90),
    );
    final rc = Dht.rc;
    final roster = await rc.createDHTRecord(
      bestCryptoKind,
      const DHTSchema.dflt(oCnt: HouseholdLayout.rosterSubkeys),
    );
    final outbox = await _createOutbox();
    await Future.wait([
      Dht.setJsonSoon(roster.key, 0, {'name': name, 'v': 1}),
      Dht.setJsonSoon(
        roster.key,
        1,
        _entry(outbox.key.toString(), memberId, myName),
      ),
    ]);
    return HouseholdSecrets(
      name: name,
      rosterKey: roster.key.toString(),
      rosterWriter: roster.ownerKeyPair!.toString(),
      outboxKey: outbox.key.toString(),
      outboxWriter: outbox.ownerKeyPair!.toString(),
      slot: 1,
    );
  }

  static Future<HouseholdSecrets> join({
    required HouseholdInvite invite,
    required String memberId,
    required String myName,
  }) async {
    await VeilidNode.instance.waitUntilOnline(
      timeout: const Duration(seconds: 90),
    );
    final rosterKey = RecordKey.fromString(invite.rosterKey);
    final writer = KeyPair.fromString(invite.rosterWriter);
    try {
      await Dht.retry(() => Dht.rc.openDHTRecord(rosterKey, writer: writer));
    } on VeilidAPIExceptionKeyNotFound {
      throw HouseholdNotFoundException();
    }
    try {
      final meta = await Dht.getJson(rosterKey, 0);
      if (meta == null) throw HouseholdNotFoundException();
      final outbox = await _createOutbox();
      final entry = Uint8List.fromList(
        utf8.encode(
          jsonEncode(_entry(outbox.key.toString(), memberId, myName)),
        ),
      );
      final slot = await _claimSlot(rosterKey, entry, memberId);
      return HouseholdSecrets(
        name: meta['name'] as String? ?? invite.name,
        rosterKey: invite.rosterKey,
        rosterWriter: invite.rosterWriter,
        outboxKey: outbox.key.toString(),
        outboxWriter: outbox.ownerKeyPair!.toString(),
        slot: slot,
      );
    } finally {
      await Dht.close(rosterKey);
    }
  }

  static Map<String, dynamic> _entry(String outbox, String id, String name) => {
    'o': outbox,
    'id': id,
    'n': name,
  };

  static Future<DHTRecordDescriptor> _createOutbox() => Dht.rc.createDHTRecord(
    bestCryptoKind,
    const DHTSchema.dflt(oCnt: OutboxLayout.subkeys),
  );

  /// Everyone shares the roster writer, so two people joining at once could
  /// pick the same subkey: write, then check the network kept ours. A slot
  /// already holding our member id (re-join after reinstall) is reused.
  static Future<int> _claimSlot(
    RecordKey roster,
    Uint8List entry,
    String memberId,
  ) async {
    for (var slot = 1; slot < HouseholdLayout.rosterSubkeys; slot++) {
      final cur = await Dht.get(roster, slot);
      if (cur != null) {
        try {
          final j = jsonDecode(utf8.decode(cur)) as Map<String, dynamic>;
          if (j['id'] != memberId) continue;
        } on Object {
          continue;
        }
      }
      final winner = await Dht.set(roster, slot, entry);
      if (winner != null && !listEquals(winner, entry)) continue;
      final check = await Dht.get(roster, slot);
      if (check != null && listEquals(check, entry)) return slot;
    }
    throw HouseholdFullException();
  }

  // ------------------------------------------------------------ lifecycle

  Future<void> start() async {
    while (!_closed) {
      try {
        await VeilidNode.instance.waitUntilOnline(
          timeout: const Duration(seconds: 60),
        );
        final rc = Dht.rc;
        await Dht.retry(
          () => rc.openDHTRecord(_rosterKey, writer: _rosterWriter),
        );
        await Dht.retry(
          () => rc.openDHTRecord(_outboxKey, writer: _outboxWriter),
        );
        if (_closed) return;
        _sub = VeilidNode.instance.updates.listen(_onUpdate);
        await rc.watchDHTValues(_rosterKey);
        connected = true;
        _setError(null);
        _schedulePublishNow();
        await _sync(roster: true);
        var tick = 0;
        _poll = Timer.periodic(const Duration(seconds: 30), (_) {
          // Watches can lapse: a slow poll is the safety net.
          tick++;
          unawaited(_sync(roster: tick % 4 == 0));
        });
        return;
      } on Object catch (e) {
        _setError('Brak połączenia z siecią P2P ($e)');
        await Future<void>.delayed(const Duration(seconds: 10));
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _poll?.cancel();
    _publishTimer?.cancel();
    await _sub?.cancel();
    await Future.any<void>([
      _publishChain.catchError((Object _) {}),
      Future<void>.delayed(const Duration(seconds: 15)),
    ]);
    if (connected) {
      await Dht.close(_rosterKey);
      await Dht.close(_outboxKey);
      for (final k in _watched.values) {
        await Dht.close(k);
      }
    }
  }

  void _setError(String? e) {
    if (_closed) return;
    error = e;
    notifyListeners();
  }

  /// Forces a full refresh (pull-to-refresh).
  Future<void> refresh() => _sync(roster: true);

  // ------------------------------------------------------------- publish

  /// Queues our data set; written a moment later so a burst of edits makes
  /// one network write.
  void publish(Map<String, dynamic> memberJson) {
    _pending = memberJson;
    _publishTimer?.cancel();
    _publishTimer = Timer(const Duration(seconds: 3), _schedulePublishNow);
  }

  void _schedulePublishNow() {
    final json = _pending;
    if (json == null || !connected) return;
    final rev = (json['rev'] as num?)?.toInt() ?? 0;
    if (rev <= _publishedRev) return;
    _publishChain = _publishChain.then((_) => _write(json, rev)).catchError((
      Object e,
    ) {
      _setError('Nie udało się wysłać danych ($e)');
    });
  }

  Future<void> _write(Map<String, dynamic> json, int rev) async {
    if (rev <= _publishedRev) return;
    final enc = encodeMember(json, rev);
    // Chunks first, the head last: a reader that sees the new head finds
    // the matching chunks (or retries until they propagate).
    await Future.wait([
      for (var i = 0; i < enc.chunks.length; i++)
        Dht.setSoon(_outboxKey, 1 + i, enc.chunks[i]),
    ]);
    await Dht.setJsonSoon(_outboxKey, 0, enc.head);
    _publishedRev = rev;
    lastPublished = DateTime.now();
    if (error != null) _setError(null);
    notifyListeners();
  }

  // ------------------------------------------------------------- receive

  void _onUpdate(VeilidUpdate u) {
    if (u is! VeilidUpdateValueChange || _closed) return;
    if (u.key.opaque == _rosterKey.opaque) {
      unawaited(_sync(roster: true));
      return;
    }
    for (final e in _watched.entries) {
      if (e.value.opaque == u.key.opaque) {
        unawaited(_syncMember(e.key, e.value));
        return;
      }
    }
  }

  Future<void> _sync({bool roster = false}) {
    return _syncing ??= () async {
      try {
        if (roster) await _refreshRoster();
        for (final e in _watched.entries.toList()) {
          await _syncMember(e.key, e.value);
        }
      } on Object catch (e) {
        debugPrint('[sync] failed: $e');
      } finally {
        _syncing = null;
      }
    }();
  }

  Future<void> _refreshRoster() async {
    final entries = <Map<String, dynamic>?>[];
    await Future.wait([
      for (var i = 1; i < HouseholdLayout.rosterSubkeys; i++)
        Dht.getJson(_rosterKey, i).then(entries.add),
    ]);
    for (final e in entries.whereType<Map<String, dynamic>>()) {
      final outbox = e['o'] as String?;
      final id = e['id'] as String?;
      if (outbox == null || id == null) continue;
      if (outbox == secrets.outboxKey || id == myMemberId) continue;
      members
              .putIfAbsent(
                outbox,
                () => RosterMember(outbox: outbox, memberId: id),
              )
              .name =
          e['n'] as String? ?? '?';
      if (_watched.containsKey(outbox)) continue;
      final key = RecordKey.fromString(outbox);
      try {
        await Dht.retry(() => Dht.rc.openDHTRecord(key));
        await Dht.rc.watchDHTValues(
          key,
          subkeys: [const ValueSubkeyRange(low: 0, high: 0)],
        );
        _watched[outbox] = key;
      } on VeilidAPIException catch (err) {
        debugPrint('[sync] cannot open a member outbox: $err');
      }
    }
    notifyListeners();
  }

  Future<void> _syncMember(String outbox, RecordKey key) async {
    final head = await Dht.getJson(key, 0);
    if (head == null) return;
    final m = members[outbox];
    final rev = (head['rev'] as num?)?.toInt() ?? 0;
    if (m != null && rev <= m.rev) return;
    final n = (head['chunks'] as num?)?.toInt() ?? 0;
    if (n < 1 || n > OutboxLayout.maxChunks) return;
    final chunks = await Future.wait([
      for (var i = 0; i < n; i++) Dht.get(key, 1 + i),
    ]);
    final json = decodeMember(head, chunks);
    if (json == null) return; // not propagated yet: next poll
    if (m != null) {
      m.rev = rev;
      m.lastSync = DateTime.now();
      m.name = json['name'] as String? ?? m.name;
    }
    onMemberData(json);
    notifyListeners();
  }
}
