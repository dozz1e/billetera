import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account.dart';

class AccountRepository {
  AccountRepository(this._client);

  final SupabaseClient _client;

  Future<List<Account>> fetchAll() async {
    final rows = await _client.from('accounts').select().order('nombre');
    return (rows as List)
        .map((r) => Account.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Account> create(Account account) async {
    final row = await _client
        .from('accounts')
        .insert({
          ...account.toInsertJson(),
          'user_id': _client.auth.currentUser!.id,
        })
        .select()
        .single();
    return Account.fromJson(row);
  }

  Future<Account> update(String id, Map<String, dynamic> changes) async {
    final row = await _client
        .from('accounts')
        .update(changes)
        .eq('id', id)
        .select()
        .single();
    return Account.fromJson(row);
  }
}
