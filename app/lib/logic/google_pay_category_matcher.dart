import '../models/category.dart';

/// Keyword -> nombre de categoría predefinida (ver `supabase/migrations/0001_init.sql`).
/// Editable solo en código en este alcance — sin UI de reglas custom (YAGNI).
const _keywordRules = <String, String>{
  'restaurant': 'Comida',
  'mercadopago': 'Comida',
  'cafe': 'Comida',
  'starbucks': 'Comida',
  'bar': 'Comida',
  'mcdonalds': 'Comida',
  'pizza': 'Comida',
  'uber': 'Transporte',
  'cabify': 'Transporte',
  'taxi': 'Transporte',
  'metro': 'Transporte',
  'bip': 'Transporte',
  'farmacia': 'Salud',
  'cruz verde': 'Salud',
  'salcobrand': 'Salud',
  'clinica': 'Salud',
  'cine': 'Entretenimiento',
  'netflix': 'Entretenimiento',
  'spotify': 'Entretenimiento',
};

const _fallbackNombre = 'Otros gastos';

String? matchCategoryId({required String comercioTexto, required List<Category> categories}) {
  final lower = comercioTexto.toLowerCase();

  var nombre = _fallbackNombre;
  for (final entry in _keywordRules.entries) {
    if (lower.contains(entry.key)) {
      nombre = entry.value;
      break;
    }
  }

  for (final category in categories) {
    if (category.nombre == nombre && category.tipo == 'gasto') return category.id;
  }
  return null;
}
