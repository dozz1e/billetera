import 'package:flutter/foundation.dart' show debugPrint;

import '../logic/recurring_payment_generator.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/recurring_payment.dart';
import '../models/transaction.dart';

/// Narrow read/write surface RecurringPaymentService needs from
/// RecurringPaymentRepository — lets tests substitute a fake instead of a
/// live Supabase-backed repository.
abstract class RecurringPaymentSource {
  Future<List<RecurringPayment>> fetchActive();
  Future<void> updateUltimaGenerada(String id, DateTime fecha);
}

/// Narrow write surface RecurringPaymentService needs from OutboxService —
/// lets tests substitute a fake instead of a live Hive/Supabase-backed
/// outbox.
abstract class TransactionSink {
  Future<void> create(Transaction transaction);
}

class RecurringPaymentService {
  RecurringPaymentService(
    this._source,
    this._sink,
    this._accounts,
    this._categories,
  );

  final RecurringPaymentSource _source;
  final TransactionSink _sink;
  final List<Account> _accounts;
  final List<Category> _categories;

  /// Generates every Transaction due for the active recurring payments, up
  /// to [today] (defaults to `DateTime.now()`). Returns how many were
  /// generated. Never throws — a failure (e.g. no network) is logged and
  /// treated as "generated 0 for that template" so it never blocks
  /// HomeScreen from loading, and never blocks other templates in the same
  /// run from being processed.
  Future<int> generateDue({DateTime? today}) async {
    final hoy = today ?? DateTime.now();
    List<RecurringPayment> templates;
    try {
      templates = await _source.fetchActive();
    } catch (e) {
      debugPrint('RecurringPaymentService: failed to fetch active templates: $e');
      return 0;
    }

    var generated = 0;
    for (final template in templates) {
      try {
        final accountExists = _accounts.any((a) => a.id == template.accountId && a.activo);
        final categoryExists = _categories.any((c) => c.id == template.categoryId);
        if (!accountExists || !categoryExists) continue;

        final due = computeDueOccurrences(
          diaMes: template.diaMes,
          fechaInicio: template.fechaInicio,
          ultimaGenerada: template.ultimaGenerada,
          hoy: hoy,
        );
        if (due.isEmpty) continue;

        for (final fecha in due) {
          await _sink.create(
            Transaction(
              id: '',
              userId: '',
              accountId: template.accountId,
              categoryId: template.categoryId,
              tipo: TransactionType.gasto,
              monto: template.monto,
              fecha: fecha,
              nota: template.nota,
              recurringPaymentId: template.id,
            ),
          );
          generated++;
        }
        await _source.updateUltimaGenerada(template.id, due.last);
      } catch (e) {
        debugPrint('RecurringPaymentService: failed to generate for template ${template.id}: $e');
      }
    }
    return generated;
  }
}
