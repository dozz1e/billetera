import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../core/dialogs.dart';
import '../models/debt.dart';
import '../models/person.dart';
import '../repositories/debt_repository.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤ #,##0',
);
final _date = DateFormat('dd/MM/yyyy');

class PersonDebtsScreen extends StatefulWidget {
  const PersonDebtsScreen({super.key, required this.person});

  final Person person;

  @override
  State<PersonDebtsScreen> createState() => _PersonDebtsScreenState();
}

class _PersonDebtsScreenState extends State<PersonDebtsScreen> {
  final _debtRepo = DebtRepository(Supabase.instance.client);
  late Future<List<Debt>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Debt>> _load() => _debtRepo.fetchForPerson(widget.person.id);

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _openForm({Debt? debt}) async {
    final motivoController = TextEditingController(text: debt?.motivo ?? '');
    final montoController = TextEditingController(
      text: debt?.monto.toString() ?? '',
    );
    var fecha = debt?.fecha ?? DateTime.now();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: kDialogInsetPadding,
          title: Text(debt == null ? 'Nueva deuda' : 'Editar deuda'),
          content: wideDialogContent([
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: montoController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Monto'),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fecha: ${_date.format(fecha)}'),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fecha,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null && context.mounted) {
                      setDialogState(() => fecha = picked);
                    }
                  },
                  child: const Text('Cambiar'),
                ),
              ],
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
                final monto = double.tryParse(montoController.text) ?? 0;
                if (motivoController.text.trim().isEmpty) {
                  setDialogState(() => error = 'Ingresa un motivo.');
                  return;
                }
                if (monto <= 0) {
                  setDialogState(() => error = 'Ingresa un monto valido.');
                  return;
                }
                try {
                  if (debt == null) {
                    await _debtRepo.create(
                      Debt(
                        id: '',
                        userId: '',
                        personId: widget.person.id,
                        motivo: motivoController.text.trim(),
                        monto: monto,
                        fecha: fecha,
                        estado: 'pendiente',
                      ),
                    );
                  } else {
                    await _debtRepo.update(debt.id, {
                      'motivo': motivoController.text.trim(),
                      'monto': monto,
                      'fecha': fecha.toIso8601String().split('T').first,
                    });
                  }
                } catch (e) {
                  setDialogState(
                    () => error =
                        'No se pudo guardar la deuda. Revisa tu conexion e intenta de nuevo.',
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

  Future<void> _toggleEstado(Debt debt) async {
    final messenger = ScaffoldMessenger.of(context);
    final nuevoEstado = debt.estado == 'pendiente' ? 'pagada' : 'pendiente';
    try {
      await _debtRepo.update(debt.id, {'estado': nuevoEstado});
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            debt.estado == 'pendiente'
                ? 'No se pudo marcar la deuda como pagada. Revisa tu conexion e intenta de nuevo.'
                : 'No se pudo marcar la deuda como pendiente. Revisa tu conexion e intenta de nuevo.',
          ),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }

  Future<void> _delete(Debt debt) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Eliminar deuda',
      message:
          'Vas a eliminar la deuda de ${_currency.format(debt.monto)} ("${debt.motivo}"). Esta accion no se puede deshacer.',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _debtRepo.delete(debt.id);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar la deuda. Revisa tu conexion e intenta de nuevo.',
          ),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.person.nombre)),
      floatingActionButton: FloatingActionButton(
        heroTag: 'person_debts_fab',
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Debt>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final debts = snapshot.data!;
          if (debts.isEmpty) {
            return const Center(child: Text('Sin deudas registradas'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    for (final (i, debt) in debts.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      Builder(
                        builder: (context) {
                          final visual = debtVisual(debt.estado);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: visual.color.withValues(
                                alpha: 0.16,
                              ),
                              child: Icon(visual.icon, color: visual.color),
                            ),
                            title: Text(debt.motivo),
                            subtitle: Text(
                              '${_currency.format(debt.monto)} · ${_date.format(debt.fecha)} · ${debt.estado}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Editar',
                                  onPressed: () => _openForm(debt: debt),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Eliminar',
                                  color: Theme.of(context).colorScheme.error,
                                  onPressed: () => _delete(debt),
                                ),
                              ],
                            ),
                            onTap: () => _toggleEstado(debt),
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
