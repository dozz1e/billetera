import 'package:billetera/logic/google_pay_category_matcher.dart';
import 'package:billetera/models/category.dart';
import 'package:flutter_test/flutter_test.dart';

const _categories = [
  Category(id: 'c-comida', userId: 'u', nombre: 'Comida', tipo: 'gasto', icono: 'restaurant', predefinida: true),
  Category(id: 'c-transporte', userId: 'u', nombre: 'Transporte', tipo: 'gasto', icono: 'directions_car', predefinida: true),
  Category(id: 'c-otros', userId: 'u', nombre: 'Otros gastos', tipo: 'gasto', icono: 'category', predefinida: true),
];

void main() {
  group('matchCategoryId', () {
    test('matches a food-related keyword', () {
      final id = matchCategoryId(comercioTexto: 'MERCADOPAGO *ARIZMEND', categories: _categories);
      expect(id, 'c-comida');
    });

    test('matches a transport-related keyword', () {
      final id = matchCategoryId(comercioTexto: 'UBER *TRIP HELP.UBER.COM', categories: _categories);
      expect(id, 'c-transporte');
    });

    test('is case-insensitive', () {
      final id = matchCategoryId(comercioTexto: 'starbucks providencia', categories: _categories);
      expect(id, 'c-comida');
    });

    test('falls back to Otros gastos when nothing matches', () {
      final id = matchCategoryId(comercioTexto: 'HIPER VINA CENTRO', categories: _categories);
      expect(id, 'c-otros');
    });

    test('returns null when even Otros gastos is missing from categories', () {
      final id = matchCategoryId(comercioTexto: 'HIPER VINA CENTRO', categories: const []);
      expect(id, isNull);
    });
  });
}
