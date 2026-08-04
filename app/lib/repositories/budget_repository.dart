import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/budget.dart';

class BudgetRepository {
  BudgetRepository(this._client);

  final SupabaseClient _client;

  Future<List<Budget>> fetchForMonth(DateTime mes) async {
    final firstOfMonth = DateTime(mes.year, mes.month, 1);
    final rows = await _client
        .from('budgets')
        .select()
        .eq('mes', firstOfMonth.toIso8601String().split('T').first);
    return (rows as List)
        .map((r) => Budget.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Budget> upsert(Budget budget) async {
    final row = await _client
        .from('budgets')
        .upsert(budget.toInsertJson(), onConflict: 'user_id,category_id,mes')
        .select()
        .single();
    return Budget.fromJson(row);
  }
}
