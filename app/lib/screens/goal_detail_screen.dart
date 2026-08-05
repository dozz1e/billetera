import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/goal.dart';

final _currency = NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0);
final _date = DateFormat('dd/MM/yyyy');

class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({
    super.key,
    required this.goal,
    required this.ahorrado,
    required this.cuentaNombre,
    required this.onTogglePausado,
  });

  final Goal goal;
  final double ahorrado;
  final String cuentaNombre;
  final Future<void> Function() onTogglePausado;

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
      if (mounted) setState(() => _error = 'No se pudo actualizar la meta. Revisa tu conexion e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final porcentaje = goal.montoObjetivo <= 0 ? 0.0 : widget.ahorrado / goal.montoObjetivo;
    final pausada = goal.estado == 'pausado';
    final alcanzada = goal.estado == 'alcanzado';

    return Scaffold(
      appBar: AppBar(title: Text(goal.nombre)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cuenta: ${widget.cuentaNombre}'),
            const SizedBox(height: 8),
            Text('Fecha objetivo: ${_date.format(goal.fechaObjetivo)}'),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: porcentaje.clamp(0, 1), minHeight: 12),
            const SizedBox(height: 12),
            Text('Ahorrado: ${_currency.format(widget.ahorrado)}'),
            Text('Objetivo: ${_currency.format(goal.montoObjetivo)}'),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (!alcanzada)
              FilledButton(
                onPressed: _loading ? null : _toggle,
                child: Text(pausada ? 'Reactivar' : 'Pausar'),
              ),
          ],
        ),
      ),
    );
  }
}
