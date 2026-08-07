import 'package:flutter/material.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.tabs});

  /// One widget per bottom-nav tab, in order: Home, Cuentas, Presupuestos, Graficas, Historial, Deudas.
  final List<Widget> tabs;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: widget.tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Cuentas'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Presupuestos'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Graficas'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Deudas'),
        ],
      ),
    );
  }
}
