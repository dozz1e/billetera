import 'package:billetera/logic/goal_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextGoalState', () {
    test('stays activo when ahorrado is below el objetivo', () {
      final estado = nextGoalState(ahorrado: 500000, montoObjetivo: 1500000, estadoActual: 'activo');
      expect(estado, 'activo');
    });

    test('moves from activo to alcanzado when ahorrado reaches el objetivo', () {
      final estado = nextGoalState(ahorrado: 1500000, montoObjetivo: 1500000, estadoActual: 'activo');
      expect(estado, 'alcanzado');
    });

    test('stays pausado even if ahorrado reaches el objetivo', () {
      final estado = nextGoalState(ahorrado: 2000000, montoObjetivo: 1500000, estadoActual: 'pausado');
      expect(estado, 'pausado');
    });

    test('stays alcanzado even if ahorrado drops below el objetivo afterward', () {
      final estado = nextGoalState(ahorrado: 100000, montoObjetivo: 1500000, estadoActual: 'alcanzado');
      expect(estado, 'alcanzado');
    });
  });
}
