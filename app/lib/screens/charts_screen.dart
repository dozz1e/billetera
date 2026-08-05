import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../logic/balance_calculator.dart';
import '../logic/chart_aggregator.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';

const _palette = AppColors.chartPalette;

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  final _accountRepo = AccountRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);

  late Future<(List<Account>, List<Category>, List<Transaction>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Account>, List<Category>, List<Transaction>)> _load() async {
    final accounts = await _accountRepo.fetchAll();
    final categories = await _categoryRepo.fetchAll();
    final transactions = await _transactionRepo.fetchAll();
    return (accounts, categories, transactions);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Graficas')),
      body: FutureBuilder<(List<Account>, List<Category>, List<Transaction>)>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final (accounts, categories, transactions) = snapshot.data!;
          final now = DateTime.now();
          final categoryNames = {for (final c in categories) c.id: c.nombre};

          final gastosPorCategoria = expensesByCategory(
            transactions: transactions,
            categoryNamesById: categoryNames,
            year: now.year,
            month: now.month,
          );
          final mensual = monthlyIncomeVsExpense(
            transactions: transactions,
            monthsBack: 6,
            referenceDate: now,
          );
          final saldoEnElTiempo = balanceOverTime(
            accounts: accounts,
            transactions: transactions,
          );

          Widget chartCard(String titulo, Widget chart) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  SizedBox(height: 220, child: chart),
                ],
              ),
            ),
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              chartCard(
                'Gasto por categoria (este mes)',
                gastosPorCategoria.isEmpty
                    ? const Center(child: Text('Sin gastos este mes'))
                    : PieChart(
                        PieChartData(
                          sections: [
                            for (final (i, entry)
                                in gastosPorCategoria.entries.indexed)
                              PieChartSectionData(
                                value: entry.value,
                                title: entry.key,
                                color: _palette[i % _palette.length],
                                radius: 80,
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              chartCard(
                'Ingresos vs gastos (6 meses)',
                BarChart(
                  BarChartData(
                    barGroups: [
                      for (final (i, m) in mensual.indexed)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: m.ingresos,
                              color: AppColors.ingreso,
                              width: 8,
                            ),
                            BarChartRodData(
                              toY: m.gastos,
                              color: AppColors.gasto,
                              width: 8,
                            ),
                          ],
                        ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= mensual.length)
                              return const SizedBox.shrink();
                            return Text(
                              '${mensual[i].month}/${mensual[i].year % 100}',
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              chartCard(
                'Evolucion del saldo',
                saldoEnElTiempo.isEmpty
                    ? const Center(child: Text('Sin datos'))
                    : LineChart(
                        LineChartData(
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (final (i, p) in saldoEnElTiempo.indexed)
                                  FlSpot(i.toDouble(), p.saldo),
                              ],
                              isCurved: false,
                              color: Theme.of(context).colorScheme.primary,
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              chartCard(
                'Saldo por cuenta',
                BarChart(
                  BarChartData(
                    barGroups: [
                      for (final (i, a) in accounts.indexed)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: calculateAccountBalance(
                                saldoInicial: a.saldoInicial,
                                accountId: a.id,
                                transactions: transactions,
                              ),
                              color: _palette[i % _palette.length],
                              width: 16,
                            ),
                          ],
                        ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= accounts.length)
                              return const SizedBox.shrink();
                            return Text(
                              accounts[i].nombre,
                              style: const TextStyle(fontSize: 10),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
