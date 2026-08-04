import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'screens/accounts_screen.dart';
import 'screens/app_shell.dart';
import 'screens/budgets_screen.dart';
import 'screens/charts_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
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
              const HomeScreen(),
              const AccountsScreen(),
              const BudgetsScreen(),
              const ChartsScreen(),
              const HistoryScreen(),
            ],
          );
        },
      ),
    );
  }
}
