import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/goal.dart';

class GoalRepository {
  GoalRepository(this._client);

  final SupabaseClient _client;

  Future<List<Goal>> fetchAll() async {
    final rows = await _client.from('goals').select().order('created_at');
    return (rows as List)
        .map((r) => Goal.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Goal> create(Goal goal) async {
    final row = await _client
        .from('goals')
        .insert({
          ...goal.toInsertJson(),
          'user_id': _client.auth.currentUser!.id,
        })
        .select()
        .single();
    return Goal.fromJson(row);
  }

  Future<Goal> updateEstado(String id, String estado) async {
    final row = await _client
        .from('goals')
        .update({'estado': estado})
        .eq('id', id)
        .select()
        .single();
    return Goal.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('goals').delete().eq('id', id);
  }
}
