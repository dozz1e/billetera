import 'package:billetera/models/account.dart';
import 'package:billetera/models/category.dart';
import 'package:billetera/models/recurring_payment.dart';
import 'package:billetera/models/transaction.dart';
import 'package:billetera/services/recurring_payment_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource implements RecurringPaymentSource {
  List<RecurringPayment> templates = [];
  final Map<String, DateTime> updated = {};
  Object? fetchError;

  @override
  Future<List<RecurringPayment>> fetchActive() async {
    final error = fetchError;
    if (error != null) throw error;
    return templates;
  }

  @override
  Future<void> updateUltimaGenerada(String id, DateTime fecha) async {
    updated[id] = fecha;
  }
}

class _FakeSink implements TransactionSink {
  final List<Transaction> created = [];

  @override
  Future<void> create(Transaction transaction) async {
    created.add(transaction);
  }
}

const _account = Account(id: 'a1', userId: 'u', nombre: 'Cuenta', tipo: 'banco', saldoInicial: 0, activo: true);
const _category = Category(id: 'c1', userId: 'u', nombre: 'Vivienda', tipo: 'gasto', icono: 'home', predefinida: true);

RecurringPayment _template({
  String id = 'r1',
  DateTime? ultimaGenerada,
}) =>
    RecurringPayment(
      id: id,
      userId: 'u',
      accountId: 'a1',
      categoryId: 'c1',
      monto: 15000,
      diaMes: 5,
      fechaInicio: DateTime(2026, 1, 5),
      activo: true,
      ultimaGenerada: ultimaGenerada,
    );

void main() {
  test('generates one transaction per missed month and advances ultimaGenerada', () async {
    final source = _FakeSource()..templates = [_template(ultimaGenerada: DateTime(2026, 1, 5))];
    final sink = _FakeSink();
    final service = RecurringPaymentService(source, sink, const [_account], const [_category]);

    final count = await service.generateDue(today: DateTime(2026, 3, 10));

    expect(count, 2);
    expect(sink.created.map((t) => t.fecha), [DateTime(2026, 2, 5), DateTime(2026, 3, 5)]);
    expect(sink.created.every((t) => t.recurringPaymentId == 'r1'), isTrue);
    expect(sink.created.every((t) => t.tipo == TransactionType.gasto), isTrue);
    expect(source.updated['r1'], DateTime(2026, 3, 5));
  });

  test('skips a template whose account no longer exists', () async {
    final source = _FakeSource()..templates = [_template()];
    final sink = _FakeSink();
    final service = RecurringPaymentService(source, sink, const [], const [_category]);

    final count = await service.generateDue(today: DateTime(2026, 1, 5));

    expect(count, 0);
    expect(sink.created, isEmpty);
    expect(source.updated, isEmpty);
  });

  test('skips a template whose category no longer exists', () async {
    final source = _FakeSource()..templates = [_template()];
    final sink = _FakeSink();
    final service = RecurringPaymentService(source, sink, const [_account], const []);

    final count = await service.generateDue(today: DateTime(2026, 1, 5));

    expect(count, 0);
    expect(sink.created, isEmpty);
  });

  test('returns 0 without throwing when fetching templates fails', () async {
    final source = _FakeSource()..fetchError = Exception('boom: network down');
    final sink = _FakeSink();
    final service = RecurringPaymentService(source, sink, const [_account], const [_category]);

    final count = await service.generateDue(today: DateTime(2026, 1, 5));

    expect(count, 0);
    expect(sink.created, isEmpty);
  });

  test('does nothing when nothing is due', () async {
    final source = _FakeSource()..templates = [_template(ultimaGenerada: DateTime(2026, 3, 5))];
    final sink = _FakeSink();
    final service = RecurringPaymentService(source, sink, const [_account], const [_category]);

    final count = await service.generateDue(today: DateTime(2026, 3, 20));

    expect(count, 0);
    expect(sink.created, isEmpty);
    expect(source.updated, isEmpty);
  });
}
