import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../logic/budget_progress.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../repositories/budget_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';
import 'goals_screen.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
);

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  final _budgetRepo = BudgetRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);

  final _mesActual = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<Category> _categories = [];
  late Future<List<BudgetProgress>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _categoryRepo
        .fetchAll()
        .then((c) {
          if (mounted)
            setState(
              () => _categories = c.where((c) => c.tipo == 'gasto').toList(),
            );
        })
        .onError((e, st) {
          debugPrint('Error al cargar categorias: $e');
        });
  }

  Future<List<BudgetProgress>> _load() async {
    final budgets = await _budgetRepo.fetchForMonth(_mesActual);
    final transactions = await _transactionRepo.fetchAll(
      from: _mesActual,
      to: DateTime(_mesActual.year, _mesActual.month + 1, 0),
    );
    return calculateBudgetProgress(
      budgets: budgets,
      transactions: transactions,
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _openForm() async {
    if (_categories.isEmpty) return;
    var categoryId = _categories.first.id;
    final montoController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Presupuesto del mes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: categoryId,
                items: _categories
                    .map(
                      (c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.nombre)),
                    )
                    .toList(),
                onChanged: (v) => setDialogState(() => categoryId = v!),
              ),
              TextField(
                controller: montoController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Monto limite'),
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
                  await _budgetRepo.upsert(
                    Budget(
                      id: '',
                      userId: '',
                      categoryId: categoryId,
                      mes: _mesActual,
                      montoLimite: monto,
                    ),
                  );
                } catch (e) {
                  setDialogState(
                    () => error =
                        'No se pudo guardar el presupuesto. Revisa tu conexion e intenta de nuevo.',
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Presupuestos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Presupuestos'),
              Tab(text: 'Metas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Scaffold(
              floatingActionButton: FloatingActionButton(
                onPressed: _openForm,
                child: const Icon(Icons.add),
              ),
              body: FutureBuilder<List<BudgetProgress>>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final progresos = snapshot.data!;
                  if (progresos.isEmpty)
                    return const Center(
                      child: Text('Sin presupuestos este mes'),
                    );
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Column(
                          children: [
                            for (final (i, p) in progresos.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              Builder(
                                builder: (context) {
                                  final categoria = _categories.firstWhere(
                                    (c) => c.id == p.budget.categoryId,
                                    orElse: () => const Category(
                                      id: '',
                                      userId: '',
                                      nombre: 'Categoria',
                                      tipo: 'gasto',
                                      icono: '',
                                      predefinida: false,
                                    ),
                                  );
                                  final color = p.excedido
                                      ? AppColors.gasto
                                      : AppColors.ingreso;
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: color.withValues(
                                        alpha: 0.16,
                                      ),
                                      child: Icon(
                                        p.excedido
                                            ? Icons.warning_amber_rounded
                                            : Icons
                                                  .check_circle_outline_rounded,
                                        color: color,
                                      ),
                                    ),
                                    title: Text(categoria.nombre),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: p.porcentaje.clamp(0, 1),
                                          minHeight: 6,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                    trailing: Text(
                                      '${_currency.format(p.gastado)} / ${_currency.format(p.budget.montoLimite)}',
                                    ),
                                    isThreeLine: false,
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const GoalsScreen(),
          ],
        ),
      ),
    );
  }
}
