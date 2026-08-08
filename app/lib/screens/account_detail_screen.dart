// app/lib/screens/account_detail_screen.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../logic/account_period_summary.dart';
import '../logic/balance_calculator.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../repositories/transaction_repository.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤ #,##0',
);

enum _Periodo { dia, semana, mes, seisMeses }

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({
    super.key,
    required this.account,
    required this.onEdit,
  });

  final Account account;
  final Future<Account?> Function() onEdit;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  final _transactionRepo = TransactionRepository(Supabase.instance.client);
  late Account _account;
  late Future<List<Transaction>> _future;
  _Periodo _periodo = _Periodo.mes;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _future = _transactionRepo.fetchAll();
  }

  DateTime _from(DateTime hoy) => switch (_periodo) {
    _Periodo.dia => DateTime(hoy.year, hoy.month, hoy.day),
    _Periodo.semana => hoy.subtract(const Duration(days: 7)),
    _Periodo.mes => DateTime(hoy.year, hoy.month, 1),
    _Periodo.seisMeses => DateTime(hoy.year, hoy.month - 6, 1),
  };

  Future<void> _edit() async {
    final updated = await widget.onEdit();
    if (updated != null && mounted) setState(() => _account = updated);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_account.nombre),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: _edit,
          ),
        ],
      ),
      body: FutureBuilder<List<Transaction>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final transactions = snapshot.data!;
          final saldoActual = calculateAccountBalance(
            saldoInicial: _account.saldoInicial,
            accountId: _account.id,
            transactions: transactions,
          );
          final visual = accountVisual(_account.tipo, scheme.primary);
          final hoy = DateTime.now();
          final resumen = accountBalanceForPeriod(
            account: _account,
            transactions: transactions,
            from: _from(hoy),
            hasta: hoy,
          );
          final variacion = resumen.variacionPorcentual;
          final variacionColor = variacion == null
              ? scheme.onSurfaceVariant
              : variacion >= 0
              ? AppColors.ingreso
              : AppColors.gasto;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: visual.color.withValues(alpha: 0.16),
                        child: Icon(visual.icon, color: visual.color),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saldo actual',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            _currency.format(saldoActual),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<_Periodo>(
                segments: const [
                  ButtonSegment(value: _Periodo.dia, label: Text('Dia')),
                  ButtonSegment(value: _Periodo.semana, label: Text('Semana')),
                  ButtonSegment(value: _Periodo.mes, label: Text('Mes')),
                  ButtonSegment(
                    value: _Periodo.seisMeses,
                    label: Text('6 meses'),
                  ),
                ],
                selected: {_periodo},
                onSelectionChanged: (s) => setState(() => _periodo = s.first),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Variacion del periodo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    variacion == null
                        ? '—'
                        : '${variacion >= 0 ? '+' : ''}${variacion.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: variacionColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: resumen.points.length <= 1
                      ? const SizedBox(
                          height: 220,
                          child: Center(
                            child: Text('Sin movimientos en este periodo'),
                          ),
                        )
                      : SizedBox(
                          height: 220,
                          child: LineChart(
                            LineChartData(
                              lineBarsData: [
                                LineChartBarData(
                                  spots: [
                                    for (final (i, p) in resumen.points.indexed)
                                      FlSpot(i.toDouble(), p.saldo),
                                  ],
                                  isCurved: false,
                                  color: scheme.primary,
                                  dotData: const FlDotData(show: false),
                                ),
                              ],
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
