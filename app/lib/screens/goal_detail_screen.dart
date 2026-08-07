import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/colors.dart';
import '../core/dialogs.dart';
import '../models/goal.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤#,##0',
);
final _date = DateFormat('dd/MM/yyyy');

class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({
    super.key,
    required this.goal,
    required this.ahorrado,
    required this.cuentaNombre,
    required this.onTogglePausado,
    required this.onDelete,
  });

  final Goal goal;
  final double ahorrado;
  final String cuentaNombre;
  final Future<void> Function() onTogglePausado;
  final Future<void> Function() onDelete;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _toggle() async {
    setState(() => _loading = true);
    try {
      await widget.onTogglePausado();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo actualizar la meta. Revisa tu conexion e intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmDelete(
      context,
      title: 'Eliminar meta',
      message:
          'Vas a eliminar "${widget.goal.nombre}". Esta accion no se puede deshacer.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _loading = true);
    try {
      await widget.onDelete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo eliminar la meta. Revisa tu conexion e intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final porcentaje = goal.montoObjetivo <= 0
        ? 0.0
        : widget.ahorrado / goal.montoObjetivo;
    final pausada = goal.estado == 'pausado';
    final alcanzada = goal.estado == 'alcanzado';
    final scheme = Theme.of(context).colorScheme;
    final visual = goalVisual(goal.estado, scheme.primary);

    return Scaffold(
      appBar: AppBar(title: Text(goal.nombre)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: visual.color.withValues(alpha: 0.16),
                        child: Icon(visual.icon, color: visual.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cuenta: ${widget.cuentaNombre}'),
                            Text(
                              'Fecha objetivo: ${_date.format(goal.fechaObjetivo)}',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: porcentaje.clamp(0, 1),
                      minHeight: 12,
                      color: visual.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Ahorrado: ${_currency.format(widget.ahorrado)}'),
                  Text('Objetivo: ${_currency.format(goal.montoObjetivo)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          if (!alcanzada)
            FilledButton(
              onPressed: _loading ? null : _toggle,
              child: Text(pausada ? 'Reactivar' : 'Pausar'),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _delete,
            icon: Icon(Icons.delete_outline, color: scheme.error),
            label: Text('Eliminar meta', style: TextStyle(color: scheme.error)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
