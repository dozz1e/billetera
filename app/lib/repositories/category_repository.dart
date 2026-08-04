import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category.dart';

class CategoryRepository {
  CategoryRepository(this._client);

  final SupabaseClient _client;

  Future<List<Category>> fetchAll() async {
    final rows = await _client.from('categories').select().order('nombre');
    return (rows as List)
        .map((r) => Category.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Category> create(Category category) async {
    final row = await _client
        .from('categories')
        .insert(category.toInsertJson())
        .select()
        .single();
    return Category.fromJson(row);
  }
}
