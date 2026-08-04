import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billetera/core/theme.dart';

void main() {
  test('appTheme usa fondo y superficie de card planos, oscuros', () {
    expect(appTheme.scaffoldBackgroundColor, const Color(0xFF121212));
    expect(appTheme.cardColor, const Color(0xFF1E1E1E));
  });

  test('appTheme usa brightness oscuro con semilla teal', () {
    expect(appTheme.brightness, Brightness.dark);
    expect(appTheme.colorScheme.brightness, Brightness.dark);
  });

  test('appTheme usa Material3', () {
    expect(appTheme.useMaterial3, true);
  });
}
