import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  runApp(const BilleteraApp());
}

class BilleteraApp extends StatelessWidget {
  const BilleteraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Billetera',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = Supabase.instance.client.auth.currentSession;
          if (session == null) return const LoginScreen();
          return AppShell(
            tabs: [
              const Center(child: Text('Home')), // replaced in Task 11
              const Center(child: Text('Cuentas')), // replaced in Task 8
              const Center(child: Text('Presupuestos')), // replaced in Task 13
              const Center(child: Text('Graficas')), // replaced in Task 14
              const Center(child: Text('Historial')), // replaced in Task 12
            ],
          );
        },
      ),
    );
  }
}
