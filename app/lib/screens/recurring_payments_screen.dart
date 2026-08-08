import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/dialogs.dart';
import '../models/recurring_payment.dart';
import '../repositories/category_repository.dart';
import '../repositories/recurring_payment_repository.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤ #,##0',
);

class RecurringPaymentsScreen extends StatefulWidget {
  const RecurringPaymentsScreen({super.key});

  @override
  State<RecurringPaymentsScreen> createState() =>
      _RecurringPaymentsScreenState();
}

class _RecurringPaymentsScreenState extends State<RecurringPaymentsScreen> {
  final _repo = RecurringPaymentRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  late Future<List<RecurringPayment>> _future;
  Map<String, String> _categoryNames = {};

  @override
  void initState() {
    super.initState();
    _reload();
    _categoryRepo.fetchAll().then((categories) {
      if (mounted) {
        setState(
          () => _categoryNames = {for (final c in categories) c.id: c.nombre},
        );
      }
    }).onError((e, st) {
      debugPrint('RecurringPaymentsScreen: failed to load categories: $e');
    });
  }

  void _reload() => setState(() {
    _future = _repo.fetchAll();
  });

  Future<void> _togglePausa(RecurringPayment payment) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.setActivo(payment.id, !payment.activo);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            payment.activo
                ? 'No se pudo pausar el pago recurrente. Revisa tu conexion e intenta de nuevo.'
                : 'No se pudo reanudar el pago recurrente. Revisa tu conexion e intenta de nuevo.',
          ),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }

  Future<void> _delete(RecurringPayment payment) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Eliminar pago recurrente',
      message:
          'Vas a eliminar este pago recurrente. Las transacciones ya generadas no se borran.',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.delete(payment.id);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar el pago recurrente. Revisa tu conexion e intenta de nuevo.',
          ),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<RecurringPayment>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final payments = snapshot.data!;
        if (payments.isEmpty) {
          return const Center(child: Text('Sin pagos recurrentes'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  for (final (i, p) in payments.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.primary.withValues(
                          alpha: p.activo ? 0.16 : 0.06,
                        ),
                        child: Icon(
                          Icons.repeat,
                          color: p.activo
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(_categoryNames[p.categoryId] ?? 'Categoria'),
                      subtitle: Text(
                        '${_currency.format(p.monto)} · dia ${p.diaMes}'
                        '${p.activo ? '' : ' · pausado'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              p.activo
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                            ),
                            tooltip: p.activo ? 'Pausar' : 'Reanudar',
                            onPressed: () => _togglePausa(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Eliminar',
                            color: scheme.error,
                            onPressed: () => _delete(p),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
