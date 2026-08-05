// This is a basic Flutter widget test.
//
// To perform an interaction with a widget, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.
//
// BilleteraApp.build() reads Supabase.instance.client.auth.onAuthStateChange,
// which requires Supabase.initialize() (only called from main(), not here).
// Pumping LoginScreen directly avoids touching Supabase.instance while still
// exercising real, meaningful app content: LoginScreen is what an
// unauthenticated user (the default state) sees.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billetera/screens/login_screen.dart';

void main() {
  testWidgets('Billetera login screen displays text', (WidgetTester tester) async {
    // Build the login screen and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // Verify that the 'Billetera' text is displayed.
    expect(find.text('Billetera'), findsOneWidget);
  });
}
