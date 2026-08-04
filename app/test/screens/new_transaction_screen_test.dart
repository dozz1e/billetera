import 'package:billetera/models/account.dart';
import 'package:billetera/models/category.dart';
import 'package:billetera/screens/new_transaction_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _accounts = [
  const Account(id: 'a1', userId: 'u', nombre: 'Banco', tipo: 'banco', saldoInicial: 0, activo: true),
  const Account(id: 'a2', userId: 'u', nombre: 'Efectivo', tipo: 'efectivo', saldoInicial: 0, activo: true),
];

final _categories = [
  const Category(id: 'c1', userId: 'u', nombre: 'Comida', tipo: 'gasto', icono: 'restaurant', predefinida: true),
  const Category(id: 'c2', userId: 'u', nombre: 'Sueldo', tipo: 'ingreso', icono: 'work', predefinida: true),
];

void main() {
  testWidgets('hides category field and shows destination account field for transferencia', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NewTransactionScreen(accounts: _accounts, categories: _categories, onSubmit: (_) async {}),
    ));

    expect(find.text('Categoria'), findsOneWidget);
    expect(find.text('Cuenta destino'), findsNothing);

    await tester.tap(find.text('Transferencia'));
    await tester.pumpAndSettle();

    expect(find.text('Categoria'), findsNothing);
    expect(find.text('Cuenta destino'), findsOneWidget);
  });

  testWidgets('save button calls onSubmit with a Transaction built from the form', (tester) async {
    Map<String, dynamic>? submitted;

    await tester.pumpWidget(MaterialApp(
      home: NewTransactionScreen(
        accounts: _accounts,
        categories: _categories,
        onSubmit: (t) async {
          submitted = t.toInsertJson();
        },
      ),
    ));

    await tester.enterText(find.byKey(const Key('monto_field')), '1500');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!['monto'], 1500.0);
    expect(submitted!['tipo'], 'gasto');
  });
}
