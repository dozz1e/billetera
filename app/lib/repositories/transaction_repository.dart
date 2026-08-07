import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/transaction.dart';

class TransactionRepository {
  TransactionRepository(this._client);

  final SupabaseClient _client;

  Future<List<Transaction>> fetchAll({
    String? accountId,
    String? categoryId,
    TransactionType? tipo,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client.from('transactions').select();

    if (accountId != null) query = query.eq('account_id', accountId);
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (tipo != null) query = query.eq('tipo', transactionTypeToString(tipo));
    if (from != null) {
      query = query.gte('fecha', from.toIso8601String().split('T').first);
    }
    if (to != null) {
      query = query.lte('fecha', to.toIso8601String().split('T').first);
    }

    final rows = await query.order('fecha', ascending: false);
    return (rows as List)
        .map((r) => Transaction.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Transaction> create(Transaction transaction) async {
    final row = await _client
        .from('transactions')
        .insert({
          ...transaction.toInsertJson(),
          'user_id': _client.auth.currentUser!.id,
        })
        .select()
        .single();
    return Transaction.fromJson(row);
  }

  /// [changes] must be the transaction's full field set (e.g.
  /// `toInsertJson()`), not a partial patch — the `transferencia_shape` CHECK
  /// constraint requires `category_id`/`account_destino_id` to stay
  /// consistent with `tipo` on every write.
  Future<Transaction> update(String id, Map<String, dynamic> changes) async {
    final row = await _client
        .from('transactions')
        .update(changes)
        .eq('id', id)
        .select()
        .single();
    return Transaction.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('transactions').delete().eq('id', id);
  }
}
