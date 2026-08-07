import 'package:billetera/logic/google_pay_notification_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseGooglePayNotification', () {
    test('parses Spanish format with CL-style decimal comma', () {
      final parsed = parseGooglePayNotification(
        title: 'Google Wallet',
        text: 'Pagaste \$8.574,00 en MERCADOPAGO *ARIZMEND',
      );

      expect(parsed, isNotNull);
      expect(parsed!.monto, 8574.0);
      expect(parsed.comercioTexto, 'MERCADOPAGO *ARIZMEND');
    });

    test('parses English format with US-style decimal point', () {
      final parsed = parseGooglePayNotification(
        title: 'Google Wallet',
        text: 'You paid \$45.00 at STARBUCKS',
      );

      expect(parsed, isNotNull);
      expect(parsed!.monto, 45.0);
      expect(parsed.comercioTexto, 'STARBUCKS');
    });

    test('parses an amount with no decimal separator at all', () {
      final parsed = parseGooglePayNotification(
        title: 'Google Wallet',
        text: 'Pagaste \$1300 en HIPER VINA CENTRO',
      );

      expect(parsed, isNotNull);
      expect(parsed!.monto, 1300.0);
      expect(parsed.comercioTexto, 'HIPER VINA CENTRO');
    });

    test('parses a CL-style whole-peso amount with thousands dot and no cents', () {
      final parsed = parseGooglePayNotification(
        title: 'Google Wallet',
        text: 'Pagaste \$1.300 en ALGUN COMERCIO',
      );

      expect(parsed, isNotNull);
      expect(parsed!.monto, 1300.0);
      expect(parsed.comercioTexto, 'ALGUN COMERCIO');
    });

    test('parses a US-style whole-dollar amount with thousands comma and no cents', () {
      final parsed = parseGooglePayNotification(
        title: 'Google Wallet',
        text: 'You paid \$8,574 at SOME MERCHANT',
      );

      expect(parsed, isNotNull);
      expect(parsed!.monto, 8574.0);
      expect(parsed.comercioTexto, 'SOME MERCHANT');
    });

    test('returns null for an unrelated notification body', () {
      final parsed = parseGooglePayNotification(
        title: 'Google Wallet',
        text: 'Tu tarjeta fue agregada correctamente',
      );

      expect(parsed, isNull);
    });

    test('returns null when text is null', () {
      final parsed = parseGooglePayNotification(title: 'Google Wallet', text: null);

      expect(parsed, isNull);
    });
  });
}
