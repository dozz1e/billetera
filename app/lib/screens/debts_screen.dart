import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/dialogs.dart';
import '../logic/debt_calculator.dart';
import '../models/debt.dart';
import '../models/person.dart';
import '../repositories/debt_repository.dart';
import '../repositories/person_repository.dart';
import 'person_debts_screen.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤ #,##0',
);

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final _personRepo = PersonRepository(Supabase.instance.client);
  final _debtRepo = DebtRepository(Supabase.instance.client);

  late Future<(List<Person>, List<Debt>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Person>, List<Debt>)> _load() async {
    final people = await _personRepo.fetchAll();
    final debts = await _debtRepo.fetchAll();
    return (people, debts);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _openForm() async {
    final nombreController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: kDialogInsetPadding,
          title: const Text('Nueva persona'),
          content: wideDialogContent([
            TextField(
              controller: nombreController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            dialogActions(
              onCancel: () => Navigator.pop(context),
              onConfirm: () async {
                try {
                  await _personRepo.create(
                    Person(
                      id: '',
                      userId: '',
                      nombre: nombreController.text.trim(),
                    ),
                  );
                } catch (e) {
                  setDialogState(
                    () => error =
                        'No se pudo guardar la persona. Revisa tu conexion e intenta de nuevo.',
                  );
                  return;
                }
                if (context.mounted) Navigator.pop(context);
                if (mounted) _reload();
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _delete(Person person) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Eliminar persona',
      message:
          'Vas a eliminar a "${person.nombre}" y todas sus deudas registradas. Esta accion no se puede deshacer.',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _personRepo.delete(person.id);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar la persona. Revisa tu conexion e intenta de nuevo.',
          ),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }

  Future<void> _abrirDetalle(Person person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonDebtsScreen(person: person),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deudas')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'debts_fab',
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<(List<Person>, List<Debt>)>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (people, debts) = snapshot.data!;
          if (people.isEmpty) {
            return const Center(child: Text('Sin personas todavia'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    for (final (i, person) in people.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      Builder(
                        builder: (context) {
                          final total = calculatePersonDebtTotal(
                            personId: person.id,
                            debts: debts,
                          );
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(person.nombre),
                            subtitle: Text(
                              total > 0
                                  ? 'Total pendiente: ${_currency.format(total)}'
                                  : 'Sin deuda pendiente',
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              tooltip: 'Eliminar',
                              onPressed: () => _delete(person),
                            ),
                            onTap: () => _abrirDetalle(person),
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
    );
  }
}
