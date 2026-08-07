// app/test/logic/recurring_payment_generator_test.dart
import 'package:billetera/logic/recurring_payment_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeDueOccurrences', () {
    test('generates the first occurrence when never generated and it is due today', () {
      final result = computeDueOccurrences(
        diaMes: 15,
        fechaInicio: DateTime(2026, 1, 15),
        ultimaGenerada: null,
        hoy: DateTime(2026, 1, 15),
      );
      expect(result, [DateTime(2026, 1, 15)]);
    });

    test('does not generate a future occurrence that is not yet due', () {
      final result = computeDueOccurrences(
        diaMes: 20,
        fechaInicio: DateTime(2026, 3, 20),
        ultimaGenerada: null,
        hoy: DateTime(2026, 3, 10),
      );
      expect(result, isEmpty);
    });

    test('returns nothing when the current month was already generated', () {
      final result = computeDueOccurrences(
        diaMes: 15,
        fechaInicio: DateTime(2026, 1, 15),
        ultimaGenerada: DateTime(2026, 3, 15),
        hoy: DateTime(2026, 3, 20),
      );
      expect(result, isEmpty);
    });

    test('generates one occurrence per missed month, in order', () {
      final result = computeDueOccurrences(
        diaMes: 5,
        fechaInicio: DateTime(2026, 1, 5),
        ultimaGenerada: DateTime(2026, 1, 5),
        hoy: DateTime(2026, 4, 10),
      );
      expect(result, [
        DateTime(2026, 2, 5),
        DateTime(2026, 3, 5),
        DateTime(2026, 4, 5),
      ]);
    });

    test('clamps dia_mes to the last day of a shorter month', () {
      final result = computeDueOccurrences(
        diaMes: 31,
        fechaInicio: DateTime(2026, 1, 31),
        ultimaGenerada: DateTime(2026, 1, 31),
        hoy: DateTime(2026, 2, 28),
      );
      expect(result, [DateTime(2026, 2, 28)]);
    });

    test('caps backfill at maxBackfill, keeping the most recent months', () {
      final result = computeDueOccurrences(
        diaMes: 1,
        fechaInicio: DateTime(2020, 1, 1),
        ultimaGenerada: null,
        hoy: DateTime(2026, 6, 1),
        maxBackfill: 12,
      );
      expect(result.length, 12);
      expect(result.first, DateTime(2025, 7, 1));
      expect(result.last, DateTime(2026, 6, 1));
    });
  });
}
