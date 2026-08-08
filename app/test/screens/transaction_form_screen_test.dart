import 'package:billetera/models/account.dart';
import 'package:billetera/models/category.dart';
import 'package:billetera/models/recurring_payment.dart';
import 'package:billetera/models/transaction.dart';
import 'package:billetera/screens/transaction_form_screen.dart';
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
      home: TransactionFormScreen(accounts: _accounts, categories: _categories, onSubmit: (_) async {}),
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
      home: TransactionFormScreen(
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

  testWidgets('prefills fields from initial transaction and shows edit title', (tester) async {
    final initial = Transaction(
      id: 't1',
      userId: 'u1',
      accountId: 'a2',
      categoryId: 'c1',
      tipo: TransactionType.gasto,
      monto: 2500,
      fecha: DateTime(2026, 5, 10),
      nota: 'Super',
    );

    await tester.pumpWidget(MaterialApp(
      home: TransactionFormScreen(
        accounts: _accounts,
        categories: _categories,
        onSubmit: (_) async {},
        initial: initial,
      ),
    ));

    expect(find.text('Editar transaccion'), findsOneWidget);
    expect(find.text('2500'), findsOneWidget);
    expect(find.text('Super'), findsOneWidget);
    expect(find.text('10/05/2026'), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('Comida'), findsOneWidget);
  });

  testWidgets('prefills transferencia fields from initial transaction', (tester) async {
    final initial = Transaction(
      id: 't2',
      userId: 'u1',
      accountId: 'a2',
      accountDestinoId: 'a1',
      tipo: TransactionType.transferencia,
      monto: 500,
      fecha: DateTime(2026, 3, 1),
    );

    await tester.pumpWidget(MaterialApp(
      home: TransactionFormScreen(
        accounts: _accounts,
        categories: _categories,
        onSubmit: (_) async {},
        initial: initial,
      ),
    ));

    expect(find.text('Categoria'), findsNothing);
    expect(find.text('Cuenta destino'), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('Banco'), findsOneWidget);
  });

  testWidgets('changing the date via the date picker updates the submitted transaction', (tester) async {
    Transaction? submitted;
    final today = DateTime.now();

    await tester.pumpWidget(MaterialApp(
      home: TransactionFormScreen(
        accounts: _accounts,
        categories: _categories,
        onSubmit: (t) async {
          submitted = t;
        },
      ),
    ));

    // Day 1 is always <= today regardless of what day the suite runs on,
    // so it's always selectable under lastDate: DateTime.now().
    await tester.tap(find.byKey(const Key('fecha_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('monto_field')), '1000');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.fecha, DateTime(today.year, today.month, 1));
  });

  testWidgets('shows the repeat-monthly checkbox only for new gasto entries when onSubmitRecurring is provided', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TransactionFormScreen(
        accounts: _accounts,
        categories: _categories,
        onSubmit: (_) async {},
        onSubmitRecurring: (_) async {},
      ),
    ));

    expect(find.text('Repetir cada mes'), findsOneWidget);

    await tester.tap(find.text('Ingreso'));
    await tester.pumpAndSettle();
    expect(find.text('Repetir cada mes'), findsNothing);
  });

  testWidgets('hides the repeat-monthly checkbox when editing an existing transaction', (tester) async {
    final initial = Transaction(
      id: 't1',
      userId: 'u1',
      accountId: 'a1',
      categoryId: 'c1',
      tipo: TransactionType.gasto,
      monto: 100,
      fecha: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(MaterialApp(
      home: TransactionFormScreen(
        accounts: _accounts,
        categories: _categories,
        onSubmit: (_) async {},
        onSubmitRecurring: (_) async {},
        initial: initial,
      ),
    ));

    expect(find.text('Repetir cada mes'), findsNothing);
  });

  testWidgets('checking repeat-monthly calls onSubmitRecurring instead of onSubmit', (tester) async {
    RecurringPayment? submitted;
    var onSubmitCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: TransactionFormScreen(
        accounts: _accounts,
        categories: _categories,
        onSubmit: (_) async {
          onSubmitCalled = true;
        },
        onSubmitRecurring: (r) async {
          submitted = r;
        },
      ),
    ));

    await tester.enterText(find.byKey(const Key('monto_field')), '15000');
    await tester.tap(find.byKey(const Key('recurrente_checkbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(onSubmitCalled, isFalse);
    expect(submitted, isNotNull);
    expect(submitted!.monto, 15000.0);
    expect(submitted!.accountId, 'a1');
    expect(submitted!.categoryId, 'c1');
    expect(submitted!.diaMes, DateTime.now().day);
  });
}
