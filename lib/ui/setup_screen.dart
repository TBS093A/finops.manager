import 'package:flutter/material.dart';

import '../app.dart';
import '../data/starter_template.dart';
import 'widgets.dart';

/// First run: who is this phone's participant.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _name = TextEditingController();
  int _color = memberColors.first;
  bool _template = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    StoreScope.of(context).update((me) {
      me.name = name;
      me.color = _color;
      if (_template && me.expenses.isEmpty) addStarterTemplate(me);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Text(
              'FinOps Manager',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Plan finansowy: dochód z dni roboczych, VAT, ryczałt i ZUS '
              'liczone automatycznie, wydatki rozpisane na miesiące, '
              'wspólny bilans z innymi uczestnikami przez P2P.',
            ),
            const SizedBox(height: 32),
            TextField(
              key: const Key('setup-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Twoje imię'),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _done(),
            ),
            const SizedBox(height: 16),
            const Text('Kolor na wspólnych wykresach'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final c in memberColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      backgroundColor: Color(c),
                      radius: 18,
                      child: _color == c
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _template,
              onChanged: (v) => setState(() => _template = v),
              title: const Text('Dodaj typowe pozycje do uzupełnienia'),
              subtitle: const Text(
                'Czynsz, media, internet, jedzenie (budżet), transport, '
                'księgowość, oszczędności — bez kwot, wpiszesz swoje.',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('setup-done'),
              onPressed: _done,
              child: const Text('Zaczynamy'),
            ),
          ],
        ),
      ),
    );
  }
}
