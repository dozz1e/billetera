import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../logic/balance_calculator.dart';
import '../logic/goal_state.dart';
import '../models/account.dart';
import '../models/goal.dart';
import '../repositories/account_repository.dart';
import '../repositories/goal_repository.dart';
import '../repositories/transaction_repository.dart';
import 'goal_detail_screen.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
);
final _date = DateFormat('dd/MM/yyyy');

class GoalWithProgress {
  const GoalWithProgress({
    required this.goal,
    required this.ahorrado,
    required this.account,
  });

  final Goal goal;
  final double ahorrado;
  final Account account;
}

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _goalRepo = GoalRepository(Supabase.instance.client);
  final _accountRepo = AccountRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);

  List<Account> _accounts = [];
  late Future<List<GoalWithProgress>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<GoalWithProgress>> _load() async {
    final goals = await _goalRepo.fetchAll();
    final accounts = await _accountRepo.fetchAll();
    final transactions = await _transactionRepo.fetchAll();
    _accounts = accounts;

    final result = <GoalWithProgress>[];
    for (final goal in goals) {
      final account = accounts.firstWhere(
        (a) => a.id == goal.accountId,
        orElse: () => const Account(
          id: '',
          userId: '',
          nombre: 'Cuenta',
          tipo: 'efectivo',
          saldoInicial: 0,
          activo: false,
        ),
      );
      final ahorrado = calculateAccountBalance(
        saldoInicial: account.saldoInicial,
        accountId: goal.accountId,
        transactions: transactions,
      );
      final nuevoEstado = nextGoalState(
        ahorrado: ahorrado,
        montoObjetivo: goal.montoObjetivo,
        estadoActual: goal.estado,
      );

      var goalActual = goal;
      if (nuevoEstado != goal.estado) {
        goalActual = await _goalRepo.updateEstado(goal.id, nuevoEstado);
      }
      result.add(
        GoalWithProgress(
          goal: goalActual,
          ahorrado: ahorrado,
          account: account,
        ),
      );
    }
    return result;
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _openForm() async {
    final cuentasActivas = _accounts.where((a) => a.activo).toList();
    if (cuentasActivas.isEmpty) return;

    final nombreController = TextEditingController();
    final montoController = TextEditingController();
    var accountId = cuentasActivas.first.id;
    var fecha = DateTime.now().add(const Duration(days: 30));
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva meta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              DropdownButton<String>(
                value: accountId,
                items: cuentasActivas
                    .map(
                      (a) =>
                          DropdownMenuItem(value: a.id, child: Text(a.nombre)),
                    )
                    .toList(),
                onChanged: (v) => setDialogState(() => accountId = v!),
              ),
              TextField(
                controller: montoController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Monto objetivo'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Fecha objetivo: ${_date.format(fecha)}'),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fecha,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (picked != null && context.mounted)
                        setDialogState(() => fecha = picked);
                    },
                    child: const Text('Cambiar'),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final monto = double.tryParse(montoController.text) ?? 0;
                try {
                  await _goalRepo.create(
                    Goal(
                      id: '',
                      userId: '',
                      nombre: nombreController.text.trim(),
                      accountId: accountId,
                      montoObjetivo: monto,
                      fechaObjetivo: fecha,
                      estado: 'activo',
                    ),
                  );
                } catch (e) {
                  setDialogState(
                    () => error =
                        'No se pudo guardar la meta. Revisa tu conexion e intenta de nuevo.',
                  );
                  return;
                }
                if (context.mounted) Navigator.pop(context);
                if (mounted) _reload();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirDetalle(GoalWithProgress gp) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GoalDetailScreen(
          goal: gp.goal,
          ahorrado: gp.ahorrado,
          cuentaNombre: gp.account.nombre,
          onTogglePausado: () async {
            final nuevoEstado = gp.goal.estado == 'pausado'
                ? 'activo'
                : 'pausado';
            await _goalRepo.updateEstado(gp.goal.id, nuevoEstado);
          },
        ),
      ),
    );
    if (mounted) _reload();
  }

  Widget _lista(List<GoalWithProgress> metas, String estado) {
    final filtradas = metas.where((m) => m.goal.estado == estado).toList();
    if (filtradas.isEmpty)
      return const Center(child: Text('Sin metas en este estado'));
    final primary = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              for (final (i, gp) in filtradas.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Builder(
                  builder: (context) {
                    final porcentaje = gp.goal.montoObjetivo <= 0
                        ? 0.0
                        : gp.ahorrado / gp.goal.montoObjetivo;
                    final visual = goalVisual(gp.goal.estado, primary);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: visual.color.withValues(alpha: 0.16),
                        child: Icon(visual.icon, color: visual.color),
                      ),
                      title: Text(gp.goal.nombre),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: porcentaje.clamp(0, 1),
                                minHeight: 6,
                                color: visual.color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_currency.format(gp.ahorrado)} / ${_currency.format(gp.goal.montoObjetivo)}',
                            ),
                          ],
                        ),
                      ),
                      onTap: () => _abrirDetalle(gp),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<GoalWithProgress>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final metas = snapshot.data!;
          return DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Activo'),
                    Tab(text: 'Pausado'),
                    Tab(text: 'Alcanzado'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _lista(metas, 'activo'),
                      _lista(metas, 'pausado'),
                      _lista(metas, 'alcanzado'),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'goals_fab',
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}
