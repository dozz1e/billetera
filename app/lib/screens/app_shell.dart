import 'package:flutter/material.dart';

import '../core/colors.dart';

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
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home, color: AppColors.chartPalette[0]),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.account_balance_wallet,
              color: AppColors.chartPalette[1],
            ),
            label: 'Cuentas',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.pie_chart_outline,
              color: AppColors.chartPalette[2],
            ),
            label: 'Presupuestos',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart, color: AppColors.chartPalette[3]),
            label: 'Graficas',
          ),
          NavigationDestination(
            icon: Icon(Icons.history, color: AppColors.chartPalette[4]),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline, color: AppColors.chartPalette[5]),
            label: 'Deudas',
          ),
        ],
      ),
    );
  }
}
