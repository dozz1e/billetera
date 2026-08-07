import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/debt.dart';

class DebtRepository {
  DebtRepository(this._client);

  final SupabaseClient _client;

  Future<List<Debt>> fetchAll() async {
    final rows = await _client.from('debts').select().order('created_at');
    return (rows as List)
        .map((r) => Debt.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Debt>> fetchForPerson(String personId) async {
    final rows = await _client
        .from('debts')
        .select()
        .eq('person_id', personId)
        .order('created_at');
    return (rows as List)
        .map((r) => Debt.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Debt> create(Debt debt) async {
    final row = await _client
        .from('debts')
        .insert({
          ...debt.toInsertJson(),
          'user_id': _client.auth.currentUser!.id,
        })
        .select()
        .single();
    return Debt.fromJson(row);
  }

  Future<Debt> update(String id, Map<String, dynamic> changes) async {
    final row = await _client
        .from('debts')
        .update(changes)
        .eq('id', id)
        .select()
        .single();
    return Debt.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('debts').delete().eq('id', id);
  }
}
