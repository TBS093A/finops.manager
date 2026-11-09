import 'package:flutter/material.dart';

import '../app.dart';
import '../data/store.dart';
import '../domain/models.dart';

const _palette = <int>[
  0xFFE53935,
  0xFFD81B60,
  0xFF8E24AA,
  0xFF3949AB,
  0xFF1E88E5,
  0xFF00ACC1,
  0xFF00897B,
  0xFF43A047,
  0xFF7CB342,
  0xFFFFB300,
  0xFFF4511E,
  0xFF6D4C41,
  0xFF546E7A,
];

/// This participant's categories: rename, recolor, add, remove.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final me = store.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Kategorie')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nowa kategoria',
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final c in me.categories)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(c.color),
                radius: 10,
              ),
              title: Text(c.name),
              subtitle: Text(
                '${c.kind.label} · '
                '${me.expenses.where((e) => e.categoryId == c.id).length} pozycji',
              ),
              onTap: () => _edit(context, c),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, Category? c) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: c?.name);
    var color =
        c?.color ?? _palette[store.me.categories.length % _palette.length];
    var kind = c?.kind ?? CategoryKind.expense;
    final used =
        c != null && store.me.expenses.any((e) => e.categoryId == c.id);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? 'Nowa kategoria' : 'Kategoria'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: c == null,
                  decoration: const InputDecoration(labelText: 'Nazwa'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in _palette)
                      GestureDetector(
                        onTap: () => set(() => color = p),
                        child: CircleAvatar(
                          backgroundColor: Color(p),
                          radius: 13,
                          child: color == p
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final k in CategoryKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: kind == k,
                    onSelected: (_) => set(() => kind = k),
                  ),
                if (kind == CategoryKind.saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Pokazywane osobno od wydatków: to pieniądze, które '
                      'zostają (lokaty, ETF, IKE, poduszka finansowa).',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (c != null)
              TextButton(
                onPressed: used ? null : () => Navigator.of(ctx).pop('delete'),
                child: Text(used ? 'W użyciu' : 'Usuń'),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: const Text('Zapisz'),
            ),
          ],
        ),
      ),
    );
    final label = name.text.trim();
    name.dispose();
    if (result == 'delete' && c != null) {
      store.update((me) => me.categories.removeWhere((x) => x.id == c.id));
      return;
    }
    if (result != 'save' || label.isEmpty) return;
    final updated = Category(
      id: c?.id ?? uuid.v4(),
      name: label,
      kind: kind,
      color: color,
    );
    store.update((me) {
      final i = me.categories.indexWhere((x) => x.id == updated.id);
      if (i >= 0) {
        me.categories[i] = updated;
      } else {
        me.categories.add(updated);
      }
    });
  }
}
