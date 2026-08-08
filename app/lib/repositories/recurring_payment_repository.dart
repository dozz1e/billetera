import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/recurring_payment.dart';
import '../services/recurring_payment_service.dart';

class RecurringPaymentRepository implements RecurringPaymentSource {
  RecurringPaymentRepository(this._client);

  final SupabaseClient _client;

  Future<List<RecurringPayment>> fetchAll() async {
    final rows = await _client
        .from('recurring_payments')
        .select()
        .order('created_at');
    return (rows as List)
        .map((r) => RecurringPayment.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<RecurringPayment>> fetchActive() async {
    final rows = await _client
        .from('recurring_payments')
        .select()
        .eq('activo', true)
        .order('created_at');
    return (rows as List)
        .map((r) => RecurringPayment.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<RecurringPayment> create(RecurringPayment payment) async {
    final row = await _client
        .from('recurring_payments')
        .insert({
          ...payment.toInsertJson(),
          'user_id': _client.auth.currentUser!.id,
        })
        .select()
        .single();
    return RecurringPayment.fromJson(row);
  }

  Future<void> setActivo(String id, bool activo) async {
    await _client
        .from('recurring_payments')
        .update({'activo': activo})
        .eq('id', id);
  }

  @override
  Future<void> updateUltimaGenerada(String id, DateTime fecha) async {
    await _client
        .from('recurring_payments')
        .update({'ultima_generada': fecha.toIso8601String().split('T').first})
        .eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('recurring_payments').delete().eq('id', id);
  }
}
