import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../sync/household_sync.dart';
import '../sync/invite.dart';
import '../sync/veilid_node.dart';

const uuid = Uuid();

/// App state: this phone's participant (editable), the other participants
/// (read-only copies received over P2P), and the household membership.
class Store extends ChangeNotifier {
  Store._(this._dir, this.me);

  /// Tests and previews: in-memory, nothing written.
  Store.memory(this.me) : _dir = null;

  static Future<Store> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'finops'));
    await dir.create(recursive: true);
    final meFile = File(p.join(dir.path, 'me.json'));
    MemberData me;
    if (await meFile.exists()) {
      me = MemberData.fromJson(
        jsonDecode(await meFile.readAsString()) as Map<String, dynamic>,
      );
    } else {
      me = MemberData(memberId: uuid.v4());
    }
    final s = Store._(dir, me);
    await s._loadRest();
    return s;
  }

  final Directory? _dir;
  final MemberData me;
  final Map<String, MemberData> peers = {};

  /// Member ids shown together on the dashboard (me included by default).
  final Set<String> selected = {};

  HouseholdSecrets? secrets;
  HouseholdSync? sync;
  String? nodeError;
  bool nodeStarted = false;

  bool get isSetUp => me.name.trim().isNotEmpty;

  List<MemberData> get everyone => [me, ...peers.values];

  List<MemberData> get selectedMembers {
    final s = everyone.where((m) => selected.contains(m.memberId)).toList();
    return s.isEmpty ? [me] : s;
  }

  File _file(String name) => File(p.join(_dir!.path, name));

  Future<void> _loadRest() async {
    final peersFile = _file('peers.json');
    if (await peersFile.exists()) {
      final j = jsonDecode(await peersFile.readAsString()) as List;
      for (final e in j) {
        final m = MemberData.fromJson(e as Map<String, dynamic>);
        peers[m.memberId] = m;
      }
    }
    final hh = _file('household.json');
    if (await hh.exists()) {
      secrets = HouseholdSecrets.fromJson(
        jsonDecode(await hh.readAsString()) as Map<String, dynamic>,
      );
    }
    final sel = _file('selected.json');
    if (await sel.exists()) {
      selected.addAll(
        (jsonDecode(await sel.readAsString()) as List).cast<String>(),
      );
    }
    if (selected.isEmpty) selected.add(me.memberId);
  }

  Future<void> _write(String name, Object json) async {
    if (_dir == null) return;
    // Write-then-rename: a crash mid-write never leaves half a file.
    final f = _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> _saveMe() => _write('me.json', me.toJson());
  Future<void> _savePeers() =>
      _write('peers.json', [for (final m in peers.values) m.toJson()]);

  /// Every change to this participant's data goes through here.
  void update(void Function(MemberData me) change) {
    change(me);
    me.rev++;
    me.updatedAt = DateTime.now();
    unawaited(_saveMe());
    sync?.publish(me.toJson());
    notifyListeners();
  }

  void toggleSelected(String memberId) {
    if (selected.contains(memberId)) {
      if (selected.length > 1) selected.remove(memberId);
    } else {
      selected.add(memberId);
    }
    unawaited(_write('selected.json', selected.toList()));
    notifyListeners();
  }

  // ----------------------------------------------------------- P2P

  /// Starts the embedded Veilid node and, if this phone is in a household,
  /// its sync. The UI never waits for this.
  Future<void> startNetwork() async {
    try {
      await VeilidNode.instance.start();
      nodeStarted = true;
      nodeError = null;
      debugPrint('[startup] ready');
    } on Object catch (e) {
      nodeError = '$e';
      debugPrint('[startup] failed: $e');
      notifyListeners();
      return;
    }
    if (secrets != null) _startSync();
    notifyListeners();
  }

  void _startSync() {
    final s = secrets!;
    final hs = HouseholdSync(
      secrets: s,
      myMemberId: me.memberId,
      onMemberData: _onPeerData,
    );
    hs.addListener(notifyListeners);
    sync = hs;
    hs.publish(me.toJson());
    unawaited(hs.start());
  }

  void _onPeerData(Map<String, dynamic> json) {
    final MemberData m;
    try {
      m = MemberData.fromJson(json);
    } on Object catch (e) {
      debugPrint('[sync] bad member data: $e');
      return;
    }
    if (m.memberId == me.memberId) return;
    final old = peers[m.memberId];
    if (old != null && old.rev >= m.rev) return;
    final isNew = old == null;
    peers[m.memberId] = m;
    // A new participant shows on the joint dashboard right away.
    if (isNew) {
      selected.add(m.memberId);
      unawaited(_write('selected.json', selected.toList()));
    }
    unawaited(_savePeers());
    notifyListeners();
  }

  Future<void> createHousehold(String name) async {
    final s = await HouseholdSync.create(
      name: name,
      memberId: me.memberId,
      myName: me.name,
    );
    await _setSecrets(s);
  }

  Future<void> joinHousehold(HouseholdInvite invite) async {
    final s = await HouseholdSync.join(
      invite: invite,
      memberId: me.memberId,
      myName: me.name,
    );
    await _setSecrets(s);
  }

  Future<void> _setSecrets(HouseholdSecrets s) async {
    secrets = s;
    await _write('household.json', s.toJson());
    _startSync();
    notifyListeners();
  }

  /// Leaves the household on this phone: stops syncing and forgets the
  /// others' data. Our entry stays in the roster (DHT values cannot be
  /// deleted), the others just stop receiving updates.
  Future<void> leaveHousehold() async {
    await sync?.close();
    sync = null;
    secrets = null;
    peers.clear();
    selected
      ..clear()
      ..add(me.memberId);
    if (_dir != null) {
      for (final f in ['household.json', 'peers.json', 'selected.json']) {
        final file = _file(f);
        if (await file.exists()) await file.delete();
      }
    }
    notifyListeners();
  }
}
