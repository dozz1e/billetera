import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/person.dart';

class PersonRepository {
  PersonRepository(this._client);

  final SupabaseClient _client;

  Future<List<Person>> fetchAll() async {
    final rows = await _client.from('people').select().order('nombre');
    return (rows as List)
        .map((r) => Person.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Person> create(Person person) async {
    final row = await _client
        .from('people')
        .insert({
          ...person.toInsertJson(),
          'user_id': _client.auth.currentUser!.id,
        })
        .select()
        .single();
    return Person.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('people').delete().eq('id', id);
  }
}
