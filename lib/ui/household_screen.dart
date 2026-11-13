import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:veilid/veilid.dart';

import '../app.dart';
import '../data/store.dart';
import '../sync/household_sync.dart';
import '../sync/invite.dart';
import '../sync/veilid_node.dart';
import 'widgets.dart';

/// Shared planning: a household of participants syncing over Veilid (P2P,
/// no server). Joining = scanning the QR shown on a member's phone.
class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({super.key});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job, String doing) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(doing), duration: const Duration(seconds: 30)),
    );
    try {
      await job();
      messenger.hideCurrentSnackBar();
    } on Object catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Błąd: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(Store store) async {
    final c = TextEditingController(text: 'Dom');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nowe gospodarstwo'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nazwa'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            child: const Text('Załóż'),
          ),
        ],
      ),
    );
    disposeAfterClose([c]);
    if (name == null || name.isEmpty) return;
    await _run(
      () => store.createHousehold(name),
      'Tworzę gospodarstwo w sieci P2P…',
    );
  }

  Future<void> _join(Store store) async {
    final raw = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (raw == null) return;
    final invite = HouseholdInvite.tryParse(raw);
    if (invite == null) return;
    await _run(
      () => store.joinHousehold(invite),
      'Dołączam do „${invite.name}”…',
    );
  }

  Future<void> _leave(Store store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Opuścić gospodarstwo?'),
        content: const Text(
          'Ten telefon przestanie wysyłać i odbierać dane. Twoje własne dane '
          'zostają; dane pozostałych uczestników zostaną usunięte z tego '
          'telefonu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Opuść'),
          ),
        ],
      ),
    );
    if (ok == true) await store.leaveHousehold();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.secrets;
    return Scaffold(
      appBar: BunnyAppBar(
        peek: Peek.bottomLeft,
        seed: 5,
        appBar: AppBar(
          title: Text(s?.name ?? 'Wspólne planowanie'),
          actions: const [_NodeStatus()],
        ),
      ),
      body: s == null ? _noHousehold(store) : _household(store, s),
    );
  }

  Widget _noHousehold(Store store) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Połącz się z innymi uczestnikami (np. partnerką/partnerem), żeby '
          'nałożyć wasze plany na siebie: wspólny bilans przychodów, '
          'wydatków i oszczędności.\n\n'
          'Każdy wypełnia tylko swój formularz na swoim telefonie. Dane '
          'płyną bezpośrednio między telefonami (sieć P2P Veilid, bez '
          'serwera), zaszyfrowane — odczytać je mogą tylko uczestnicy.\n\n'
          'Dołączenie wymaga zeskanowania kodu QR z telefonu kogoś, kto już '
          'jest w gospodarstwie.',
        ),
        const SizedBox(height: 24),
        if (store.nodeError != null)
          Text(
            'Sieć P2P niedostępna: ${store.nodeError}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton.icon(
          key: const Key('household-create'),
          onPressed: _busy || !store.nodeStarted ? null : () => _create(store),
          icon: const Icon(Icons.add_home),
          label: const Text('Załóż gospodarstwo'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy || !store.nodeStarted ? null : () => _join(store),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Dołącz — zeskanuj kod QR'),
        ),
        if (!store.nodeStarted && store.nodeError == null)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Uruchamiam węzeł P2P…', textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _household(Store store, HouseholdSecrets s) {
    final sync = store.sync;
    return RefreshIndicator(
      onRefresh: () async => sync?.refresh(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (sync?.error != null)
            ListTile(
              leading: const Icon(Icons.cloud_off),
              title: Text(sync!.error!),
            ),
          ListTile(
            leading: CircleAvatar(backgroundColor: Color(store.me.color)),
            title: Text('${store.me.name} (ja)'),
            subtitle: Text(
              sync?.lastPublished == null
                  ? 'czekam na wysłanie danych…'
                  : 'wysłano ${_ago(sync!.lastPublished!)}',
            ),
          ),
          for (final m in sync?.members.values ?? const <RosterMember>[])
            Builder(
              builder: (context) {
                final data = store.peers[m.memberId];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(data?.color ?? 0xFF9E9E9E),
                  ),
                  title: Text(data?.name ?? m.name),
                  subtitle: Text(
                    data == null
                        ? 'pobieram dane…'
                        : 'zaktualizowano ${_ago(data.updatedAt)}',
                  ),
                );
              },
            ),
          // Peers known from earlier sessions, before the roster loads.
          for (final p in store.peers.values)
            if (!(sync?.members.values.any((m) => m.memberId == p.memberId) ??
                false))
              ListTile(
                leading: CircleAvatar(backgroundColor: Color(p.color)),
                title: Text(p.name),
                subtitle: Text('ostatnio ${_ago(p.updatedAt)}'),
              ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.qr_code_2),
            title: const Text('Zaproś uczestnika'),
            subtitle: const Text('Pokaż kod QR do zeskanowania na miejscu'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InviteScreen(invite: s.invite),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Opuść gospodarstwo'),
            onTap: () => _leave(store),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'przed chwilą';
    if (d.inHours < 1) return '${d.inMinutes} min temu';
    if (d.inDays < 1) return '${d.inHours} h temu';
    return '${t.day}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  }
}

class _NodeStatus extends StatelessWidget {
  const _NodeStatus();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AttachmentState>(
      valueListenable: VeilidNode.instance.attachment,
      builder: (context, state, _) {
        final online = state.isOnline;
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Tooltip(
            message: 'Sieć P2P: ${state.name}',
            child: Icon(
              online ? Icons.cloud_done : Icons.cloud_queue,
              color: online ? Colors.green : Colors.grey,
            ),
          ),
        );
      },
    );
  }
}

class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key, required this.invite});
  final HouseholdInvite invite;

  @override
  Widget build(BuildContext context) {
    final code = invite.encode();
    return Scaffold(
      appBar: AppBar(title: const Text('Zaproszenie')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: code, size: 280),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Niech druga osoba otworzy FinOps Manager → Wspólne → Dołącz i '
            'zeskanuje ten kod. Kod daje pełny dostęp do wspólnych danych — '
            'pokazuj go tylko na żywo.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Kopiuj kod (gdy nie da się zeskanować)'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Skopiowano kod zaproszenia')),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Scans an invite QR (or takes a pasted code) and returns its text.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;

  void _accept(String raw) {
    if (_done || HouseholdInvite.tryParse(raw) == null) return;
    _done = true;
    Navigator.of(context).pop(raw);
  }

  Future<void> _paste() async {
    final c = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wklej kod zaproszenia'),
        content: TextField(
          key: const Key('invite-paste'),
          controller: c,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: const Text('Dołącz'),
          ),
        ],
      ),
    );
    disposeAfterClose([c]);
    if (raw == null || !mounted) return;
    if (HouseholdInvite.tryParse(raw) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('To nie jest kod zaproszenia FinOps')),
      );
      return;
    }
    _accept(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zeskanuj zaproszenie'),
        actions: [
          IconButton(
            tooltip: 'Wklej kod',
            icon: const Icon(Icons.content_paste),
            onPressed: _paste,
          ),
        ],
      ),
      body: MobileScanner(
        onDetect: (capture) {
          for (final b in capture.barcodes) {
            final raw = b.rawValue;
            if (raw != null) _accept(raw);
          }
        },
      ),
    );
  }
}
