import 'package:flutter/material.dart';

import 'data/store.dart';
import 'ui/bunny.dart';
import 'ui/dashboard_screen.dart';
import 'ui/expenses_screen.dart';
import 'ui/household_screen.dart';
import 'ui/income_screen.dart';
import 'ui/log_screen.dart';
import 'ui/setup_screen.dart';

/// Gives every screen the [Store] and rebuilds them when it changes.
class StoreScope extends InheritedNotifier<Store> {
  const StoreScope({super.key, required Store store, required super.child})
    : super(notifier: store);

  static Store of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// Without subscribing to changes: for event handlers.
  static Store read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

class FinOpsApp extends StatelessWidget {
  const FinOpsApp({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1E88E5),
        brightness: b,
      ),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
    return StoreScope(
      store: store,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          title: 'FinOps Manager',
          debugShowCheckedModeBanner: false,
          // The bunny theme is a light, flat picture-book look.
          theme: store.bunny ? bunnyTheme() : theme(Brightness.light),
          darkTheme: store.bunny ? bunnyTheme() : theme(Brightness.dark),
          home: const _Root(),
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return store.isSetUp ? const HomeShell() : const SetupScreen();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _pages = <Widget>[
    DashboardScreen(),
    ExpensesScreen(),
    LogScreen(),
    IncomeScreen(),
    HouseholdScreen(),
  ];

  static const _navBunny = 40.0;

  @override
  Widget build(BuildContext context) {
    // Bunny theme: the bunny stands behind the bottom bar, on the
    // left so it never hides the + buttons. Content scrolls right up to the
    // bar: the bunny hides behind it, only its ear tips show between visits.
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: PeekingBunny(
        peek: Peek.topLeft,
        width: _navBunny,
        earsWhileHidden: false,
        inset: 18,
        seed: 7,
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            setState(() => _tab = i);
            cueBunny();
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Plan',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note),
              label: 'Wydatki',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Dziennik',
            ),
            NavigationDestination(
              icon: Icon(Icons.work_outline),
              selectedIcon: Icon(Icons.work),
              label: 'Dochód',
            ),
            NavigationDestination(
              icon: Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group),
              label: 'Wspólne',
            ),
          ],
        ),
      ),
    );
  }
}
