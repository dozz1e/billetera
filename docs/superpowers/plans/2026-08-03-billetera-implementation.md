# Billetera Personal (Android) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal-use Flutter Android app to track income, expenses, transfers, account balances and charts, backed by a dedicated Supabase project.

**Architecture:** Flutter app talks directly to Supabase (Postgres + Auth) via `supabase_flutter`. All business logic that needs to be correct (balance math, chart aggregation, budget progress) lives in pure Dart functions with unit tests, independent of any widget. Screens are thin — they call repositories and pass data to the pure logic functions. Offline writes queue in a local Hive outbox and flush automatically on reconnect.

**Tech Stack:** Flutter (stable), `supabase_flutter`, `hive` + `hive_flutter`, `connectivity_plus`, `fl_chart`, `intl`, `uuid`. Backend: Supabase (Postgres, Auth, RLS).

## Global Constraints

- Package/org: `com.cenakin.billetera`.
- Currency: CLP only, formatted with `intl` `NumberFormat.currency(locale: 'es_CL', symbol: '$')`. No multi-currency, no exchange rates.
- Every Supabase table has RLS enabled, filtered by `user_id = auth.uid()`. No table is ever readable across users.
- No bank/Google Wallet integration, no push notifications, no multi-user sharing, no offline conflict resolution — all explicitly out of scope per the spec.
- Transactions are 100% manual entry.
- A transfer is a single `transactions` row with `account_id` (origin) and `account_destino_id` (destination); it never counts as income or expense in totals or charts.
- Account balance is always **calculated** (`saldo_inicial` + transactions), never stored as a column.
- Spec reference: `docs/superpowers/specs/2026-08-03-billetera-app-design.md`.

---

## Task 1: Supabase schema, RLS and default categories

**Files:**
- Create: `supabase/migrations/0001_init.sql`

**Interfaces:**
- Produces: tables `accounts`, `categories`, `transactions`, `budgets` — exact columns as below. Every later task's repository code depends on these exact column names.

**Prerequisite (not code, do this first):** Create a new Supabase project in the Supabase dashboard, dedicated to this app (per spec: separate from any other project in this workspace). Note the project URL and anon key — Task 2 needs them.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0001_init.sql

create table accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null,
  tipo text not null check (tipo in ('efectivo', 'banco', 'credito', 'billetera_digital')),
  saldo_inicial numeric not null default 0,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create table categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null,
  tipo text not null check (tipo in ('ingreso', 'gasto')),
  icono text not null default 'category',
  predefinida boolean not null default false
);

create table transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references accounts(id) on delete restrict,
  category_id uuid references categories(id) on delete restrict,
  account_destino_id uuid references accounts(id) on delete restrict,
  tipo text not null check (tipo in ('ingreso', 'gasto', 'transferencia')),
  monto numeric not null check (monto > 0),
  fecha date not null,
  nota text,
  created_at timestamptz not null default now(),
  constraint transferencia_shape check (
    (tipo = 'transferencia' and account_destino_id is not null and category_id is null and account_destino_id <> account_id)
    or
    (tipo in ('ingreso', 'gasto') and category_id is not null and account_destino_id is null)
  )
);

create index transactions_user_fecha_idx on transactions(user_id, fecha);
create index transactions_user_account_idx on transactions(user_id, account_id);
create index transactions_user_category_idx on transactions(user_id, category_id);

create table budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid not null references categories(id) on delete cascade,
  mes date not null,
  monto_limite numeric not null check (monto_limite > 0),
  unique (user_id, category_id, mes)
);

create index budgets_user_mes_idx on budgets(user_id, mes);

-- RLS

alter table accounts enable row level security;
alter table categories enable row level security;
alter table transactions enable row level security;
alter table budgets enable row level security;

create policy "accounts_owner" on accounts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "categories_owner" on categories
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "transactions_owner" on transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "budgets_owner" on budgets
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Seed predefined categories for every new user

create or replace function public.seed_default_categories()
returns trigger as $$
begin
  insert into public.categories (user_id, nombre, tipo, icono, predefinida) values
    (new.id, 'Comida', 'gasto', 'restaurant', true),
    (new.id, 'Transporte', 'gasto', 'directions_car', true),
    (new.id, 'Vivienda', 'gasto', 'home', true),
    (new.id, 'Salud', 'gasto', 'local_hospital', true),
    (new.id, 'Entretenimiento', 'gasto', 'movie', true),
    (new.id, 'Otros gastos', 'gasto', 'category', true),
    (new.id, 'Sueldo', 'ingreso', 'work', true),
    (new.id, 'Otros ingresos', 'ingreso', 'attach_money', true);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.seed_default_categories();
```

- [ ] **Step 2: Apply the migration**

Using the Supabase MCP tool against the new project (project must already be linked/selected):

Run: `mcp__supabase__apply_migration` with `name: "init"` and the SQL content above.

Expected: migration applies with no errors; `mcp__supabase__list_tables` shows `accounts`, `categories`, `transactions`, `budgets`.

- [ ] **Step 3: Verify RLS with a smoke query**

Run: `mcp__supabase__get_advisors` (security category).

Expected: no "RLS disabled" warnings for the four new tables.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0001_init.sql
git commit -m "feat: add Supabase schema, RLS policies and default category seed"
```

---

## Task 2: Flutter project scaffold + Supabase bootstrap

**Files:**
- Create: `app/` (via `flutter create`)
- Create: `app/lib/core/env.dart`
- Create: `app/lib/main.dart` (overwrite generated default)
- Modify: `app/pubspec.yaml`
- Create: `app/env.json.example`
- Modify: `app/.gitignore`

**Interfaces:**
- Produces: `Env.supabaseUrl`, `Env.supabaseAnonKey` (compile-time constants). `Supabase.instance.client` initialized and available app-wide via `supabase_flutter`'s global accessor — every later task's repository/auth code uses `Supabase.instance.client`.

- [ ] **Step 1: Scaffold the Flutter project**

Run from `/run/media/Respaldo/Trabajo/claude/billetera`:

```bash
flutter create --org com.cenakin --project-name billetera app
```

Expected: `app/` created with default Flutter counter app, `app/android`, `app/lib/main.dart` present.

- [ ] **Step 2: Add dependencies**

Edit `app/pubspec.yaml`, add under `dependencies:`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.5.0
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  connectivity_plus: ^6.0.0
  fl_chart: ^0.68.0
  intl: ^0.19.0
  uuid: ^4.4.0
```

Run: `cd app && flutter pub get`
Expected: exits 0, `pubspec.lock` updated.

- [ ] **Step 3: Create env config**

Create `app/lib/core/env.dart`:

```dart
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
```

Create `app/env.json.example`:

```json
{
  "SUPABASE_URL": "https://YOUR-PROJECT-REF.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR-ANON-KEY"
}
```

Copy it to a real, gitignored `app/env.json` and fill in the values from Task 1's Supabase project.

Add to `app/.gitignore`:

```
env.json
```

- [ ] **Step 4: Bootstrap Supabase in main.dart**

Replace the content of `app/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
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
      home: const Scaffold(body: Center(child: Text('Billetera'))),
    );
  }
}
```

- [ ] **Step 5: Add the INTERNET permission for release builds**

Flutter's debug/profile builds get network access automatically for tooling, but release builds do not request it unless declared explicitly — without this step the release APK from Task 16 cannot reach Supabase.

Edit `app/android/app/src/main/AndroidManifest.xml`, add inside the `<manifest>` tag, before `<application ...>`:

```xml
    <uses-permission android:name="android.permission.INTERNET" />
```

- [ ] **Step 6: Verify it builds and runs**

Run: `flutter run --dart-define-from-file=env.json` (with an Android emulator or device connected)
Expected: app launches showing a screen with the text "Billetera", no red error screen.

- [ ] **Step 7: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/core/env.dart app/lib/main.dart app/env.json.example app/.gitignore app/android app/ios app/test app/analysis_options.yaml
git commit -m "feat: scaffold Flutter app with Supabase bootstrap and INTERNET permission"
```

---

## Task 3: Domain models

**Files:**
- Create: `app/lib/models/account.dart`
- Create: `app/lib/models/category.dart`
- Create: `app/lib/models/transaction.dart`
- Create: `app/lib/models/budget.dart`
- Test: `app/test/models/transaction_test.dart`

**Interfaces:**
- Consumes: nothing (pure models).
- Produces: `Account`, `Category`, `Transaction`, `Budget` classes with `fromJson`/`toInsertJson`, and `TransactionType` enum with `transactionTypeFromString`/`transactionTypeToString`. Every repository (Task 4), logic function (Tasks 5-6, 13) and screen (Tasks 7-14) uses these exact types and field names.

- [ ] **Step 1: Write the failing model round-trip test**

Create `app/test/models/transaction_test.dart`:

```dart
import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Transaction.fromJson parses a gasto row correctly', () {
    final json = {
      'id': 't1',
      'user_id': 'u1',
      'account_id': 'a1',
      'category_id': 'c1',
      'account_destino_id': null,
      'tipo': 'gasto',
      'monto': 1500.0,
      'fecha': '2026-08-01',
      'nota': 'Almuerzo',
    };

    final t = Transaction.fromJson(json);

    expect(t.id, 't1');
    expect(t.tipo, TransactionType.gasto);
    expect(t.monto, 1500.0);
    expect(t.fecha, DateTime(2026, 8, 1));
    expect(t.accountDestinoId, isNull);
  });

  test('toInsertJson round-trips tipo as a string', () {
    final t = Transaction(
      id: 't1',
      userId: 'u1',
      accountId: 'a1',
      categoryId: 'c1',
      tipo: TransactionType.ingreso,
      monto: 2000.0,
      fecha: DateTime(2026, 8, 1),
    );

    expect(t.toInsertJson()['tipo'], 'ingreso');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/transaction_test.dart`
Expected: FAIL — `Transaction` / `TransactionType` not found (file doesn't exist yet).

- [ ] **Step 3: Implement the models**

Create `app/lib/models/account.dart`:

```dart
class Account {
  const Account({
    required this.id,
    required this.userId,
    required this.nombre,
    required this.tipo,
    required this.saldoInicial,
    required this.activo,
  });

  final String id;
  final String userId;
  final String nombre;
  final String tipo; // 'efectivo' | 'banco' | 'credito' | 'billetera_digital'
  final double saldoInicial;
  final bool activo;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        nombre: json['nombre'] as String,
        tipo: json['tipo'] as String,
        saldoInicial: (json['saldo_inicial'] as num).toDouble(),
        activo: json['activo'] as bool,
      );

  Map<String, dynamic> toInsertJson() => {
        'nombre': nombre,
        'tipo': tipo,
        'saldo_inicial': saldoInicial,
        'activo': activo,
      };
}
```

Create `app/lib/models/category.dart`:

```dart
class Category {
  const Category({
    required this.id,
    required this.userId,
    required this.nombre,
    required this.tipo,
    required this.icono,
    required this.predefinida,
  });

  final String id;
  final String userId;
  final String nombre;
  final String tipo; // 'ingreso' | 'gasto'
  final String icono;
  final bool predefinida;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        nombre: json['nombre'] as String,
        tipo: json['tipo'] as String,
        icono: json['icono'] as String,
        predefinida: json['predefinida'] as bool,
      );

  Map<String, dynamic> toInsertJson() => {
        'nombre': nombre,
        'tipo': tipo,
        'icono': icono,
        'predefinida': predefinida,
      };
}
```

Create `app/lib/models/transaction.dart`:

```dart
enum TransactionType { ingreso, gasto, transferencia }

TransactionType transactionTypeFromString(String value) {
  switch (value) {
    case 'ingreso':
      return TransactionType.ingreso;
    case 'gasto':
      return TransactionType.gasto;
    case 'transferencia':
      return TransactionType.transferencia;
    default:
      throw ArgumentError('Unknown transaction type: $value');
  }
}

String transactionTypeToString(TransactionType type) => type.name;

class Transaction {
  const Transaction({
    required this.id,
    required this.userId,
    required this.accountId,
    this.categoryId,
    this.accountDestinoId,
    required this.tipo,
    required this.monto,
    required this.fecha,
    this.nota,
  });

  final String id;
  final String userId;
  final String accountId;
  final String? categoryId;
  final String? accountDestinoId;
  final TransactionType tipo;
  final double monto;
  final DateTime fecha;
  final String? nota;

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        accountId: json['account_id'] as String,
        categoryId: json['category_id'] as String?,
        accountDestinoId: json['account_destino_id'] as String?,
        tipo: transactionTypeFromString(json['tipo'] as String),
        monto: (json['monto'] as num).toDouble(),
        fecha: DateTime.parse(json['fecha'] as String),
        nota: json['nota'] as String?,
      );

  Map<String, dynamic> toInsertJson() => {
        'account_id': accountId,
        'category_id': categoryId,
        'account_destino_id': accountDestinoId,
        'tipo': transactionTypeToString(tipo),
        'monto': monto,
        'fecha': fecha.toIso8601String().split('T').first,
        'nota': nota,
      };
}
```

Create `app/lib/models/budget.dart`:

```dart
class Budget {
  const Budget({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.mes,
    required this.montoLimite,
  });

  final String id;
  final String userId;
  final String categoryId;
  final DateTime mes;
  final double montoLimite;

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        categoryId: json['category_id'] as String,
        mes: DateTime.parse(json['mes'] as String),
        montoLimite: (json['monto_limite'] as num).toDouble(),
      );

  Map<String, dynamic> toInsertJson() => {
        'category_id': categoryId,
        'mes': mes.toIso8601String().split('T').first,
        'monto_limite': montoLimite,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/transaction_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/models app/test/models
git commit -m "feat: add domain models for accounts, categories, transactions, budgets"
```

---

## Task 4: Repositories

**Files:**
- Create: `app/lib/repositories/account_repository.dart`
- Create: `app/lib/repositories/category_repository.dart`
- Create: `app/lib/repositories/transaction_repository.dart`
- Create: `app/lib/repositories/budget_repository.dart`

**Interfaces:**
- Consumes: `Account`, `Category`, `Transaction`, `Budget`, `TransactionType` from Task 3; `Supabase.instance.client` from Task 2.
- Produces:
  - `AccountRepository.fetchAll() -> Future<List<Account>>`, `.create(Account) -> Future<Account>`, `.update(String id, Map<String, dynamic> changes) -> Future<Account>`.
  - `CategoryRepository.fetchAll() -> Future<List<Category>>`, `.create(Category) -> Future<Category>`.
  - `TransactionRepository.fetchAll({String? accountId, String? categoryId, TransactionType? tipo, DateTime? from, DateTime? to}) -> Future<List<Transaction>>`, `.create(Transaction) -> Future<Transaction>`.
  - `BudgetRepository.fetchForMonth(DateTime mes) -> Future<List<Budget>>`, `.upsert(Budget) -> Future<Budget>`.
  - These exact method signatures are used by every screen task (7-15).

No unit tests here — these are thin wrappers over the Supabase SDK; they are exercised through manual QA in Task 16 (mocking the Supabase HTTP layer is out of scope per the spec's testing section).

- [ ] **Step 1: Implement AccountRepository**

Create `app/lib/repositories/account_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account.dart';

class AccountRepository {
  AccountRepository(this._client);

  final SupabaseClient _client;

  Future<List<Account>> fetchAll() async {
    final rows = await _client.from('accounts').select().order('nombre');
    return (rows as List)
        .map((r) => Account.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Account> create(Account account) async {
    final row = await _client
        .from('accounts')
        .insert(account.toInsertJson())
        .select()
        .single();
    return Account.fromJson(row);
  }

  Future<Account> update(String id, Map<String, dynamic> changes) async {
    final row = await _client
        .from('accounts')
        .update(changes)
        .eq('id', id)
        .select()
        .single();
    return Account.fromJson(row);
  }
}
```

- [ ] **Step 2: Implement CategoryRepository**

Create `app/lib/repositories/category_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category.dart';

class CategoryRepository {
  CategoryRepository(this._client);

  final SupabaseClient _client;

  Future<List<Category>> fetchAll() async {
    final rows = await _client.from('categories').select().order('nombre');
    return (rows as List)
        .map((r) => Category.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Category> create(Category category) async {
    final row = await _client
        .from('categories')
        .insert(category.toInsertJson())
        .select()
        .single();
    return Category.fromJson(row);
  }
}
```

- [ ] **Step 3: Implement TransactionRepository**

Create `app/lib/repositories/transaction_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/transaction.dart';

class TransactionRepository {
  TransactionRepository(this._client);

  final SupabaseClient _client;

  Future<List<Transaction>> fetchAll({
    String? accountId,
    String? categoryId,
    TransactionType? tipo,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client.from('transactions').select();

    if (accountId != null) query = query.eq('account_id', accountId);
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (tipo != null) query = query.eq('tipo', transactionTypeToString(tipo));
    if (from != null) {
      query = query.gte('fecha', from.toIso8601String().split('T').first);
    }
    if (to != null) {
      query = query.lte('fecha', to.toIso8601String().split('T').first);
    }

    final rows = await query.order('fecha', ascending: false);
    return (rows as List)
        .map((r) => Transaction.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Transaction> create(Transaction transaction) async {
    final row = await _client
        .from('transactions')
        .insert(transaction.toInsertJson())
        .select()
        .single();
    return Transaction.fromJson(row);
  }
}
```

- [ ] **Step 4: Implement BudgetRepository**

Create `app/lib/repositories/budget_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/budget.dart';

class BudgetRepository {
  BudgetRepository(this._client);

  final SupabaseClient _client;

  Future<List<Budget>> fetchForMonth(DateTime mes) async {
    final firstOfMonth = DateTime(mes.year, mes.month, 1);
    final rows = await _client
        .from('budgets')
        .select()
        .eq('mes', firstOfMonth.toIso8601String().split('T').first);
    return (rows as List)
        .map((r) => Budget.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Budget> upsert(Budget budget) async {
    final row = await _client
        .from('budgets')
        .upsert(budget.toInsertJson(), onConflict: 'user_id,category_id,mes')
        .select()
        .single();
    return Budget.fromJson(row);
  }
}
```

- [ ] **Step 5: Verify the project still compiles**

Run: `cd app && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add app/lib/repositories
git commit -m "feat: add Supabase repositories for accounts, categories, transactions, budgets"
```

---

## Task 5: Balance calculation logic

**Files:**
- Create: `app/lib/logic/balance_calculator.dart`
- Test: `app/test/logic/balance_calculator_test.dart`

**Interfaces:**
- Consumes: `Account`, `Transaction`, `TransactionType` from Task 3.
- Produces: `calculateAccountBalance({required double saldoInicial, required String accountId, required List<Transaction> transactions}) -> double` and `calculateTotalBalance({required List<Account> accounts, required List<Transaction> allTransactions}) -> double`. Used by Task 11 (Home) and Task 14 (Charts).

- [ ] **Step 1: Write the failing tests**

Create `app/test/logic/balance_calculator_test.dart`:

```dart
import 'package:billetera/logic/balance_calculator.dart';
import 'package:billetera/models/account.dart';
import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculateAccountBalance', () {
    test('adds ingresos and subtracts gastos for the account', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'c1', tipo: TransactionType.ingreso, monto: 1000, fecha: DateTime(2026, 1, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'c2', tipo: TransactionType.gasto, monto: 300, fecha: DateTime(2026, 1, 2)),
      ];

      final balance = calculateAccountBalance(saldoInicial: 500, accountId: 'a1', transactions: transactions);

      expect(balance, 1200); // 500 + 1000 - 300
    });

    test('a transferencia subtracts from origin and adds to destination', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', accountDestinoId: 'a2', tipo: TransactionType.transferencia, monto: 400, fecha: DateTime(2026, 1, 1)),
      ];

      final origen = calculateAccountBalance(saldoInicial: 1000, accountId: 'a1', transactions: transactions);
      final destino = calculateAccountBalance(saldoInicial: 0, accountId: 'a2', transactions: transactions);

      expect(origen, 600);
      expect(destino, 400);
    });

    test('ignores transactions on other accounts', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'other', categoryId: 'c1', tipo: TransactionType.ingreso, monto: 999, fecha: DateTime(2026, 1, 1)),
      ];

      final balance = calculateAccountBalance(saldoInicial: 100, accountId: 'a1', transactions: transactions);

      expect(balance, 100);
    });
  });

  group('calculateTotalBalance', () {
    test('sums the balance of every account, transferencias net to zero across accounts', () {
      final accounts = [
        const Account(id: 'a1', userId: 'u', nombre: 'Banco', tipo: 'banco', saldoInicial: 1000, activo: true),
        const Account(id: 'a2', userId: 'u', nombre: 'Efectivo', tipo: 'efectivo', saldoInicial: 0, activo: true),
      ];
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', accountDestinoId: 'a2', tipo: TransactionType.transferencia, monto: 400, fecha: DateTime(2026, 1, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'c1', tipo: TransactionType.ingreso, monto: 200, fecha: DateTime(2026, 1, 2)),
      ];

      final total = calculateTotalBalance(accounts: accounts, allTransactions: transactions);

      expect(total, 1200); // 1000 + 0 - 400 + 400 + 200
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/logic/balance_calculator_test.dart`
Expected: FAIL — `calculateAccountBalance` not defined.

- [ ] **Step 3: Implement the logic**

Create `app/lib/logic/balance_calculator.dart`:

```dart
import '../models/account.dart';
import '../models/transaction.dart';

double calculateAccountBalance({
  required double saldoInicial,
  required String accountId,
  required List<Transaction> transactions,
}) {
  var balance = saldoInicial;
  for (final t in transactions) {
    switch (t.tipo) {
      case TransactionType.ingreso:
        if (t.accountId == accountId) balance += t.monto;
      case TransactionType.gasto:
        if (t.accountId == accountId) balance -= t.monto;
      case TransactionType.transferencia:
        if (t.accountId == accountId) balance -= t.monto;
        if (t.accountDestinoId == accountId) balance += t.monto;
    }
  }
  return balance;
}

double calculateTotalBalance({
  required List<Account> accounts,
  required List<Transaction> allTransactions,
}) {
  var total = 0.0;
  for (final account in accounts) {
    total += calculateAccountBalance(
      saldoInicial: account.saldoInicial,
      accountId: account.id,
      transactions: allTransactions,
    );
  }
  return total;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/logic/balance_calculator_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/logic/balance_calculator.dart app/test/logic/balance_calculator_test.dart
git commit -m "feat: add pure balance calculation logic with unit tests"
```

---

## Task 6: Chart aggregation logic

**Files:**
- Create: `app/lib/logic/chart_aggregator.dart`
- Test: `app/test/logic/chart_aggregator_test.dart`

**Interfaces:**
- Consumes: `Account`, `Transaction`, `TransactionType` from Task 3.
- Produces:
  - `expensesByCategory({required List<Transaction> transactions, required Map<String, String> categoryNamesById, required int year, required int month}) -> Map<String, double>`
  - `class MonthlyTotals { final int year; final int month; final double ingresos; final double gastos; }`
  - `monthlyIncomeVsExpense({required List<Transaction> transactions, required int monthsBack, required DateTime referenceDate}) -> List<MonthlyTotals>`
  - `class BalancePoint { final DateTime fecha; final double saldo; }`
  - `balanceOverTime({required List<Account> accounts, required List<Transaction> transactions}) -> List<BalancePoint>`
  - Used by Task 14 (Charts screen).

- [ ] **Step 1: Write the failing tests**

Create `app/test/logic/chart_aggregator_test.dart`:

```dart
import 'package:billetera/logic/chart_aggregator.dart';
import 'package:billetera/models/account.dart';
import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expensesByCategory', () {
    test('sums gasto amounts by category name for the given month, ignores other months and ingresos', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 100, fecha: DateTime(2026, 8, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 50, fecha: DateTime(2026, 8, 15)),
        Transaction(id: '3', userId: 'u', accountId: 'a1', categoryId: 'transporte', tipo: TransactionType.gasto, monto: 20, fecha: DateTime(2026, 8, 2)),
        Transaction(id: '4', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 999, fecha: DateTime(2026, 7, 1)),
        Transaction(id: '5', userId: 'u', accountId: 'a1', categoryId: 'sueldo', tipo: TransactionType.ingreso, monto: 5000, fecha: DateTime(2026, 8, 1)),
      ];

      final result = expensesByCategory(
        transactions: transactions,
        categoryNamesById: {'comida': 'Comida', 'transporte': 'Transporte', 'sueldo': 'Sueldo'},
        year: 2026,
        month: 8,
      );

      expect(result, {'Comida': 150, 'Transporte': 20});
    });
  });

  group('monthlyIncomeVsExpense', () {
    test('buckets ingresos and gastos per month for the requested range, filling months with no data as zero', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'c', tipo: TransactionType.ingreso, monto: 1000, fecha: DateTime(2026, 8, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'c', tipo: TransactionType.gasto, monto: 300, fecha: DateTime(2026, 8, 5)),
      ];

      final result = monthlyIncomeVsExpense(transactions: transactions, monthsBack: 3, referenceDate: DateTime(2026, 8, 10));

      expect(result.length, 3);
      expect(result.last.year, 2026);
      expect(result.last.month, 8);
      expect(result.last.ingresos, 1000);
      expect(result.last.gastos, 300);
      expect(result.first.month, 6);
      expect(result.first.ingresos, 0);
      expect(result.first.gastos, 0);
    });
  });

  group('balanceOverTime', () {
    test('produces a running total balance point per transaction, ignoring transferencias', () {
      final accounts = [
        const Account(id: 'a1', userId: 'u', nombre: 'Banco', tipo: 'banco', saldoInicial: 100, activo: true),
      ];
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'c', tipo: TransactionType.ingreso, monto: 50, fecha: DateTime(2026, 8, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'c', tipo: TransactionType.gasto, monto: 20, fecha: DateTime(2026, 8, 2)),
      ];

      final points = balanceOverTime(accounts: accounts, transactions: transactions);

      expect(points.length, 2);
      expect(points[0].saldo, 150);
      expect(points[1].saldo, 130);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/logic/chart_aggregator_test.dart`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement the logic**

Create `app/lib/logic/chart_aggregator.dart`:

```dart
import '../models/account.dart';
import '../models/transaction.dart';

Map<String, double> expensesByCategory({
  required List<Transaction> transactions,
  required Map<String, String> categoryNamesById,
  required int year,
  required int month,
}) {
  final result = <String, double>{};
  for (final t in transactions) {
    if (t.tipo != TransactionType.gasto) continue;
    if (t.fecha.year != year || t.fecha.month != month) continue;
    final name = categoryNamesById[t.categoryId] ?? 'Sin categoria';
    result[name] = (result[name] ?? 0) + t.monto;
  }
  return result;
}

class MonthlyTotals {
  const MonthlyTotals({
    required this.year,
    required this.month,
    required this.ingresos,
    required this.gastos,
  });

  final int year;
  final int month;
  final double ingresos;
  final double gastos;

  MonthlyTotals copyWith({double? ingresos, double? gastos}) => MonthlyTotals(
        year: year,
        month: month,
        ingresos: ingresos ?? this.ingresos,
        gastos: gastos ?? this.gastos,
      );
}

List<MonthlyTotals> monthlyIncomeVsExpense({
  required List<Transaction> transactions,
  required int monthsBack,
  required DateTime referenceDate,
}) {
  final buckets = <String, MonthlyTotals>{};
  final order = <String>[];
  for (var i = monthsBack - 1; i >= 0; i--) {
    final d = DateTime(referenceDate.year, referenceDate.month - i, 1);
    final key = '${d.year}-${d.month}';
    buckets[key] = MonthlyTotals(year: d.year, month: d.month, ingresos: 0, gastos: 0);
    order.add(key);
  }

  for (final t in transactions) {
    final key = '${t.fecha.year}-${t.fecha.month}';
    final existing = buckets[key];
    if (existing == null) continue;
    if (t.tipo == TransactionType.ingreso) {
      buckets[key] = existing.copyWith(ingresos: existing.ingresos + t.monto);
    } else if (t.tipo == TransactionType.gasto) {
      buckets[key] = existing.copyWith(gastos: existing.gastos + t.monto);
    }
  }

  return order.map((k) => buckets[k]!).toList();
}

class BalancePoint {
  const BalancePoint({required this.fecha, required this.saldo});

  final DateTime fecha;
  final double saldo;
}

List<BalancePoint> balanceOverTime({
  required List<Account> accounts,
  required List<Transaction> transactions,
}) {
  final sorted = [...transactions]..sort((a, b) => a.fecha.compareTo(b.fecha));
  final points = <BalancePoint>[];
  var running = accounts.fold(0.0, (sum, a) => sum + a.saldoInicial);

  for (final t in sorted) {
    if (t.tipo == TransactionType.ingreso) {
      running += t.monto;
    } else if (t.tipo == TransactionType.gasto) {
      running -= t.monto;
    }
    points.add(BalancePoint(fecha: t.fecha, saldo: running));
  }

  return points;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/logic/chart_aggregator_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/logic/chart_aggregator.dart app/test/logic/chart_aggregator_test.dart
git commit -m "feat: add pure chart aggregation logic with unit tests"
```

---

## Task 7: App shell, auth gate and login screen

**Files:**
- Create: `app/lib/screens/login_screen.dart`
- Create: `app/lib/screens/app_shell.dart`
- Modify: `app/lib/main.dart`

**Interfaces:**
- Consumes: `Supabase.instance.client` (Task 2).
- Produces: `AppShell` widget — a `Scaffold` with a `BottomNavigationBar` with 5 empty-body tabs (Home, Cuentas, Presupuestos, Graficas, Historial) that Tasks 8-14 fill in one by one by replacing each tab's placeholder body. `LoginScreen` widget.

- [ ] **Step 1: Implement the login screen**

Create `app/lib/screens/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'No se pudo iniciar sesion. Revisa tu conexion.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Billetera', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contrasena'),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Entrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Implement the app shell**

Create `app/lib/screens/app_shell.dart`:

```dart
import 'package:flutter/material.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.tabs});

  /// One widget per bottom-nav tab, in order: Home, Cuentas, Presupuestos, Graficas, Historial.
  final List<Widget> tabs;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: widget.tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Cuentas'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Presupuestos'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Graficas'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Wire auth gate into main.dart**

Replace `app/lib/main.dart`:

```dart
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
    anonKey: Env.supabaseAnonKey,
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
```

- [ ] **Step 4: Manual verification**

Run: `flutter run --dart-define-from-file=env.json`
Expected: app shows the login screen; after creating a user in the Supabase dashboard (Authentication > Users) and logging in with those credentials, the app shows the bottom-nav shell with 5 tabs.

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/login_screen.dart app/lib/screens/app_shell.dart app/lib/main.dart
git commit -m "feat: add login screen, auth gate and bottom-nav app shell"
```

---

## Task 8: Accounts screen

**Files:**
- Create: `app/lib/screens/accounts_screen.dart`
- Modify: `app/lib/main.dart:` replace the Cuentas tab placeholder

**Interfaces:**
- Consumes: `AccountRepository` (Task 4), `Account` (Task 3).
- Produces: `AccountsScreen` widget, self-contained (creates its own `AccountRepository` from `Supabase.instance.client`).

- [ ] **Step 1: Implement the screen**

Create `app/lib/screens/accounts_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account.dart';
import '../repositories/account_repository.dart';

const _tipos = ['efectivo', 'banco', 'credito', 'billetera_digital'];

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _repo = AccountRepository(Supabase.instance.client);
  late Future<List<Account>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAll();
  }

  void _reload() => setState(() => _future = _repo.fetchAll());

  Future<void> _openForm({Account? account}) async {
    final nombreController = TextEditingController(text: account?.nombre ?? '');
    final saldoController = TextEditingController(text: account?.saldoInicial.toString() ?? '0');
    var tipo = account?.tipo ?? _tipos.first;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(account == null ? 'Nueva cuenta' : 'Editar cuenta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombreController, decoration: const InputDecoration(labelText: 'Nombre')),
              DropdownButton<String>(
                value: tipo,
                items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setDialogState(() => tipo = v!),
              ),
              TextField(
                controller: saldoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Saldo inicial'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final saldo = double.tryParse(saldoController.text) ?? 0;
                if (account == null) {
                  await _repo.create(Account(
                    id: '',
                    userId: '',
                    nombre: nombreController.text.trim(),
                    tipo: tipo,
                    saldoInicial: saldo,
                    activo: true,
                  ));
                } else {
                  await _repo.update(account.id, {
                    'nombre': nombreController.text.trim(),
                    'tipo': tipo,
                    'saldo_inicial': saldo,
                  });
                }
                if (context.mounted) Navigator.pop(context);
                _reload();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Account>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final accounts = snapshot.data!;
          if (accounts.isEmpty) return const Center(child: Text('Sin cuentas todavia'));
          return ListView.builder(
            itemCount: accounts.length,
            itemBuilder: (context, i) {
              final a = accounts[i];
              return ListTile(
                title: Text(a.nombre),
                subtitle: Text(a.tipo),
                trailing: a.activo
                    ? IconButton(
                        icon: const Icon(Icons.archive_outlined),
                        tooltip: 'Desactivar',
                        onPressed: () async {
                          await _repo.update(a.id, {'activo': false});
                          _reload();
                        },
                      )
                    : const Text('inactiva'),
                onTap: () => _openForm(account: a),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Wire it into the app shell**

In `app/lib/main.dart`, add the import `import 'screens/accounts_screen.dart';` and replace `const Center(child: Text('Cuentas')), // replaced in Task 8` with `const AccountsScreen(),`.

- [ ] **Step 3: Manual verification**

Run: `flutter run --dart-define-from-file=env.json`, log in, go to the Cuentas tab, create an account (e.g. "Efectivo", tipo `efectivo`, saldo inicial `50000`).
Expected: account appears in the list; tapping it opens the edit dialog pre-filled; the archive icon deactivates it and it shows "inactiva".

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/accounts_screen.dart app/lib/main.dart
git commit -m "feat: add accounts screen with create/edit/deactivate"
```

---

## Task 9: Categories screen

**Files:**
- Create: `app/lib/screens/categories_screen.dart`
- Modify: `app/lib/main.dart` (import only — this tab is filled in Task 13 alongside budgets; see note below)

**Interfaces:**
- Consumes: `CategoryRepository` (Task 4), `Category` (Task 3).
- Produces: `CategoriesScreen` widget, reachable from the Cuentas tab's app bar via a button (categories are account-adjacent settings, not their own bottom-nav tab — keeps the 5-tab shell from Task 7 unchanged).

- [ ] **Step 1: Implement the screen**

Create `app/lib/screens/categories_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category.dart';
import '../repositories/category_repository.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _repo = CategoryRepository(Supabase.instance.client);
  late Future<List<Category>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAll();
  }

  void _reload() => setState(() => _future = _repo.fetchAll());

  Future<void> _openForm() async {
    final nombreController = TextEditingController();
    var tipo = 'gasto';

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva categoria'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombreController, decoration: const InputDecoration(labelText: 'Nombre')),
              DropdownButton<String>(
                value: tipo,
                items: const [
                  DropdownMenuItem(value: 'gasto', child: Text('Gasto')),
                  DropdownMenuItem(value: 'ingreso', child: Text('Ingreso')),
                ],
                onChanged: (v) => setDialogState(() => tipo = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                await _repo.create(Category(
                  id: '',
                  userId: '',
                  nombre: nombreController.text.trim(),
                  tipo: tipo,
                  icono: 'category',
                  predefinida: false,
                ));
                if (context.mounted) Navigator.pop(context);
                _reload();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Category>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final categories = snapshot.data!;
          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final c = categories[i];
              return ListTile(
                title: Text(c.nombre),
                subtitle: Text(c.tipo),
                trailing: c.predefinida ? const Chip(label: Text('predefinida')) : null,
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Add an entry point from Accounts screen**

In `app/lib/screens/accounts_screen.dart`, add the import `import 'categories_screen.dart';` and, in the `AppBar` of the `Scaffold` built in `build()`, add an actions list:

```dart
appBar: AppBar(
  title: const Text('Cuentas'),
  actions: [
    IconButton(
      icon: const Icon(Icons.label_outline),
      tooltip: 'Categorias',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CategoriesScreen()),
      ),
    ),
  ],
),
```

- [ ] **Step 3: Manual verification**

Run: `flutter run --dart-define-from-file=env.json`, log in, go to Cuentas, tap the label icon in the app bar.
Expected: Categorias screen opens showing the 8 seeded predefined categories (from Task 1's trigger) each tagged "predefinida"; adding a new one appears without the tag.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/categories_screen.dart app/lib/screens/accounts_screen.dart
git commit -m "feat: add categories screen reachable from accounts app bar"
```

---

## Task 10: New transaction form

**Files:**
- Create: `app/lib/screens/new_transaction_screen.dart`
- Test: `app/test/screens/new_transaction_screen_test.dart`

**Interfaces:**
- Consumes: `Account`, `Category`, `Transaction`, `TransactionType` (Task 3), `AccountRepository`, `CategoryRepository`, `TransactionRepository` (Task 4).
- Produces: `NewTransactionScreen` widget taking `accounts` and `categories` as constructor params (so it's testable without hitting Supabase) plus a `TransactionRepository` for submission. Used by Task 11's home screen FAB.

- [ ] **Step 1: Write the failing widget test**

Create `app/test/screens/new_transaction_screen_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/screens/new_transaction_screen_test.dart`
Expected: FAIL — `NewTransactionScreen` not found.

- [ ] **Step 3: Implement the screen**

Create `app/lib/screens/new_transaction_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';

class NewTransactionScreen extends StatefulWidget {
  const NewTransactionScreen({
    super.key,
    required this.accounts,
    required this.categories,
    required this.onSubmit,
  });

  final List<Account> accounts;
  final List<Category> categories;
  final Future<void> Function(Transaction) onSubmit;

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  TransactionType _tipo = TransactionType.gasto;
  String? _accountId;
  String? _accountDestinoId;
  String? _categoryId;
  DateTime _fecha = DateTime.now();
  final _montoController = TextEditingController();
  final _notaController = TextEditingController();
  String? _error;

  List<Category> get _categoriasFiltradas => widget.categories
      .where((c) => c.tipo == (_tipo == TransactionType.ingreso ? 'ingreso' : 'gasto'))
      .toList();

  @override
  void initState() {
    super.initState();
    if (widget.accounts.isNotEmpty) _accountId = widget.accounts.first.id;
    if (_categoriasFiltradas.isNotEmpty) _categoryId = _categoriasFiltradas.first.id;
  }

  Future<void> _submit() async {
    final monto = double.tryParse(_montoController.text);
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Monto invalido');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Selecciona una cuenta');
      return;
    }
    if (_tipo == TransactionType.transferencia) {
      if (_accountDestinoId == null || _accountDestinoId == _accountId) {
        setState(() => _error = 'Selecciona una cuenta destino distinta');
        return;
      }
    } else if (_categoryId == null) {
      setState(() => _error = 'Selecciona una categoria');
      return;
    }

    final transaction = Transaction(
      id: '',
      userId: '',
      accountId: _accountId!,
      categoryId: _tipo == TransactionType.transferencia ? null : _categoryId,
      accountDestinoId: _tipo == TransactionType.transferencia ? _accountDestinoId : null,
      tipo: _tipo,
      monto: monto,
      fecha: _fecha,
      nota: _notaController.text.trim().isEmpty ? null : _notaController.text.trim(),
    );

    await widget.onSubmit(transaction);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva transaccion')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(value: TransactionType.gasto, label: Text('Gasto')),
                ButtonSegment(value: TransactionType.ingreso, label: Text('Ingreso')),
                ButtonSegment(value: TransactionType.transferencia, label: Text('Transferencia')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() {
                _tipo = s.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('monto_field'),
              controller: _montoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _accountId,
              decoration: const InputDecoration(labelText: 'Cuenta'),
              items: widget.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))).toList(),
              onChanged: (v) => setState(() => _accountId = v),
            ),
            if (_tipo == TransactionType.transferencia) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _accountDestinoId,
                decoration: const InputDecoration(labelText: 'Cuenta destino'),
                items: widget.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))).toList(),
                onChanged: (v) => setState(() => _accountDestinoId = v),
              ),
            ] else ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: _categoriasFiltradas.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))).toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(controller: _notaController, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(onPressed: _submit, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/screens/new_transaction_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/new_transaction_screen.dart app/test/screens/new_transaction_screen_test.dart
git commit -m "feat: add new transaction form with widget tests"
```

---

## Task 11: Home screen

**Files:**
- Create: `app/lib/screens/home_screen.dart`
- Modify: `app/lib/main.dart` (replace Home tab placeholder)

**Interfaces:**
- Consumes: `AccountRepository`, `CategoryRepository`, `TransactionRepository` (Task 4), `calculateAccountBalance`/`calculateTotalBalance` (Task 5), `NewTransactionScreen` (Task 10).
- Produces: `HomeScreen` widget.

- [ ] **Step 1: Implement the screen**

Create `app/lib/screens/home_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/balance_calculator.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';
import 'new_transaction_screen.dart';

final _currency = NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _accountRepo = AccountRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);

  late Future<(List<Account>, List<Transaction>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Account>, List<Transaction>)> _load() async {
    final accounts = await _accountRepo.fetchAll();
    final transactions = await _transactionRepo.fetchAll();
    return (accounts, transactions);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openNewTransaction() async {
    final accounts = await _accountRepo.fetchAll();
    final categories = await _categoryRepo.fetchAll();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewTransactionScreen(
          accounts: accounts.where((a) => a.activo).toList(),
          categories: categories,
          onSubmit: (t) async {
            await _transactionRepo.create(t);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billetera')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewTransaction,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<(List<Account>, List<Transaction>)>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final (accounts, transactions) = snapshot.data!;
          final total = calculateTotalBalance(accounts: accounts, allTransactions: transactions);
          final recientes = transactions.take(10).toList();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Saldo total', style: Theme.of(context).textTheme.titleMedium),
                Text(_currency.format(total), style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: accounts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final a = accounts[i];
                      final balance = calculateAccountBalance(
                        saldoInicial: a.saldoInicial,
                        accountId: a.id,
                        transactions: transactions,
                      );
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(a.nombre, style: Theme.of(context).textTheme.labelLarge),
                              Text(_currency.format(balance)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Text('Transacciones recientes', style: Theme.of(context).textTheme.titleMedium),
                ...recientes.map((t) => ListTile(
                      leading: Icon(switch (t.tipo) {
                        TransactionType.ingreso => Icons.arrow_downward,
                        TransactionType.gasto => Icons.arrow_upward,
                        TransactionType.transferencia => Icons.swap_horiz,
                      }),
                      title: Text(_currency.format(t.monto)),
                      subtitle: Text(t.nota ?? t.tipo.name),
                      trailing: Text(DateFormat('dd/MM').format(t.fecha)),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Wire it into the app shell**

In `app/lib/main.dart`, add `import 'screens/home_screen.dart';` and replace `const Center(child: Text('Home')), // replaced in Task 11` with `const HomeScreen(),`.

- [ ] **Step 3: Manual verification**

Run: `flutter run --dart-define-from-file=env.json`, log in, on Home tap the FAB, create a gasto of `5000` against an existing account, save.
Expected: back on Home, the saldo total card and the account card both reflect the new balance, and the transaction appears in "Transacciones recientes".

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/home_screen.dart app/lib/main.dart
git commit -m "feat: add home screen with total/account balances and recent transactions"
```

---

## Task 12: History / filters screen

**Files:**
- Create: `app/lib/screens/history_screen.dart`
- Modify: `app/lib/main.dart` (replace Historial tab placeholder)

**Interfaces:**
- Consumes: `AccountRepository`, `CategoryRepository`, `TransactionRepository` (Task 4), `Transaction`/`TransactionType` (Task 3).
- Produces: `HistoryScreen` widget.

- [ ] **Step 1: Implement the screen**

Create `app/lib/screens/history_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';

final _currency = NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _accountRepo = AccountRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);

  List<Account> _accounts = [];
  List<Category> _categories = [];
  String? _accountFilter;
  String? _categoryFilter;
  TransactionType? _tipoFilter;
  late Future<List<Transaction>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _accountRepo.fetchAll().then((a) => setState(() => _accounts = a));
    _categoryRepo.fetchAll().then((c) => setState(() => _categories = c));
  }

  Future<List<Transaction>> _load() => _transactionRepo.fetchAll(
        accountId: _accountFilter,
        categoryId: _categoryFilter,
        tipo: _tipoFilter,
      );

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                DropdownButton<String?>(
                  hint: const Text('Cuenta'),
                  value: _accountFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    ..._accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))),
                  ],
                  onChanged: (v) {
                    _accountFilter = v;
                    _reload();
                  },
                ),
                DropdownButton<String?>(
                  hint: const Text('Categoria'),
                  value: _categoryFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))),
                  ],
                  onChanged: (v) {
                    _categoryFilter = v;
                    _reload();
                  },
                ),
                DropdownButton<TransactionType?>(
                  hint: const Text('Tipo'),
                  value: _tipoFilter,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Todos')),
                    DropdownMenuItem(value: TransactionType.ingreso, child: Text('Ingreso')),
                    DropdownMenuItem(value: TransactionType.gasto, child: Text('Gasto')),
                    DropdownMenuItem(value: TransactionType.transferencia, child: Text('Transferencia')),
                  ],
                  onChanged: (v) {
                    _tipoFilter = v;
                    _reload();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Transaction>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final transactions = snapshot.data!;
                if (transactions.isEmpty) return const Center(child: Text('Sin transacciones'));
                return ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, i) {
                    final t = transactions[i];
                    return ListTile(
                      title: Text(_currency.format(t.monto)),
                      subtitle: Text(t.nota ?? t.tipo.name),
                      trailing: Text(DateFormat('dd/MM/yyyy').format(t.fecha)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Wire it into the app shell**

In `app/lib/main.dart`, add `import 'screens/history_screen.dart';` and replace `const Center(child: Text('Historial')), // replaced in Task 12` with `const HistoryScreen(),`.

- [ ] **Step 3: Manual verification**

Run: `flutter run --dart-define-from-file=env.json`, log in, go to Historial, filter by an account and by tipo `gasto`.
Expected: list narrows to matching transactions only; picking "Todas"/"Todos" again shows everything.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/history_screen.dart app/lib/main.dart
git commit -m "feat: add history screen with account/category/tipo filters"
```

---

## Task 13: Budget progress logic + budgets screen

**Files:**
- Create: `app/lib/logic/budget_progress.dart`
- Test: `app/test/logic/budget_progress_test.dart`
- Create: `app/lib/screens/budgets_screen.dart`
- Modify: `app/lib/main.dart` (replace Presupuestos tab placeholder)

**Interfaces:**
- Consumes: `Budget` (Task 3), `Transaction`/`TransactionType` (Task 3), `BudgetRepository`, `CategoryRepository`, `TransactionRepository` (Task 4).
- Produces: `class BudgetProgress { final Budget budget; final double gastado; double get porcentaje; bool get excedido; }`, `calculateBudgetProgress({required List<Budget> budgets, required List<Transaction> transactions}) -> List<BudgetProgress>`, `BudgetsScreen` widget.

- [ ] **Step 1: Write the failing test**

Create `app/test/logic/budget_progress_test.dart`:

```dart
import 'package:billetera/logic/budget_progress.dart';
import 'package:billetera/models/budget.dart';
import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gastado sums only gasto transactions in the budget category and month; excedido flips over the limit', () {
    final budget = Budget(id: 'b1', userId: 'u', categoryId: 'comida', mes: DateTime(2026, 8, 1), montoLimite: 100);
    final transactions = [
      Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 60, fecha: DateTime(2026, 8, 5)),
      Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 50, fecha: DateTime(2026, 8, 10)),
      Transaction(id: '3', userId: 'u', accountId: 'a1', categoryId: 'transporte', tipo: TransactionType.gasto, monto: 999, fecha: DateTime(2026, 8, 10)),
      Transaction(id: '4', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 999, fecha: DateTime(2026, 7, 10)),
    ];

    final result = calculateBudgetProgress(budgets: [budget], transactions: transactions);

    expect(result.single.gastado, 110);
    expect(result.single.excedido, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/logic/budget_progress_test.dart`
Expected: FAIL — `calculateBudgetProgress` not defined.

- [ ] **Step 3: Implement the logic**

Create `app/lib/logic/budget_progress.dart`:

```dart
import '../models/budget.dart';
import '../models/transaction.dart';

class BudgetProgress {
  const BudgetProgress({required this.budget, required this.gastado});

  final Budget budget;
  final double gastado;

  double get porcentaje => budget.montoLimite <= 0 ? 0 : gastado / budget.montoLimite;
  bool get excedido => gastado > budget.montoLimite;
}

List<BudgetProgress> calculateBudgetProgress({
  required List<Budget> budgets,
  required List<Transaction> transactions,
}) {
  return budgets.map((b) {
    final gastado = transactions
        .where((t) =>
            t.tipo == TransactionType.gasto &&
            t.categoryId == b.categoryId &&
            t.fecha.year == b.mes.year &&
            t.fecha.month == b.mes.month)
        .fold(0.0, (sum, t) => sum + t.monto);
    return BudgetProgress(budget: b, gastado: gastado);
  }).toList();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/logic/budget_progress_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Implement the budgets screen**

Create `app/lib/screens/budgets_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/budget_progress.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../repositories/budget_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';

final _currency = NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0);

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  final _budgetRepo = BudgetRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);

  final _mesActual = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<Category> _categories = [];
  late Future<List<BudgetProgress>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _categoryRepo.fetchAll().then((c) => setState(() => _categories = c.where((c) => c.tipo == 'gasto').toList()));
  }

  Future<List<BudgetProgress>> _load() async {
    final budgets = await _budgetRepo.fetchForMonth(_mesActual);
    final transactions = await _transactionRepo.fetchAll(from: _mesActual, to: DateTime(_mesActual.year, _mesActual.month + 1, 0));
    return calculateBudgetProgress(budgets: budgets, transactions: transactions);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openForm() async {
    if (_categories.isEmpty) return;
    var categoryId = _categories.first.id;
    final montoController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Presupuesto del mes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: categoryId,
                items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))).toList(),
                onChanged: (v) => setDialogState(() => categoryId = v!),
              ),
              TextField(
                controller: montoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto limite'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final monto = double.tryParse(montoController.text) ?? 0;
                await _budgetRepo.upsert(Budget(
                  id: '',
                  userId: '',
                  categoryId: categoryId,
                  mes: _mesActual,
                  montoLimite: monto,
                ));
                if (context.mounted) Navigator.pop(context);
                _reload();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Presupuestos')),
      floatingActionButton: FloatingActionButton(onPressed: _openForm, child: const Icon(Icons.add)),
      body: FutureBuilder<List<BudgetProgress>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final progresos = snapshot.data!;
          if (progresos.isEmpty) return const Center(child: Text('Sin presupuestos este mes'));
          return ListView.builder(
            itemCount: progresos.length,
            itemBuilder: (context, i) {
              final p = progresos[i];
              final categoria = _categories.firstWhere(
                (c) => c.id == p.budget.categoryId,
                orElse: () => Category(id: '', userId: '', nombre: 'Categoria', tipo: 'gasto', icono: '', predefinida: false),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${categoria.nombre}: ${_currency.format(p.gastado)} / ${_currency.format(p.budget.montoLimite)}'),
                    LinearProgressIndicator(
                      value: p.porcentaje.clamp(0, 1),
                      color: p.excedido ? Colors.red : Colors.teal,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Wire it into the app shell**

In `app/lib/main.dart`, add `import 'screens/budgets_screen.dart';` and replace `const Center(child: Text('Presupuestos')), // replaced in Task 13` with `const BudgetsScreen(),`.

- [ ] **Step 7: Manual verification**

Run: `flutter run --dart-define-from-file=env.json`, log in, go to Presupuestos, create a budget for "Comida" with limit `50000`, then go register a gasto over that limit in Comida.
Expected: back on Presupuestos, the progress bar for Comida turns red and shows gastado > limite.

- [ ] **Step 8: Commit**

```bash
git add app/lib/logic/budget_progress.dart app/test/logic/budget_progress_test.dart app/lib/screens/budgets_screen.dart app/lib/main.dart
git commit -m "feat: add budget progress logic and budgets screen"
```

---

## Task 14: Charts screen

**Files:**
- Create: `app/lib/screens/charts_screen.dart`
- Modify: `app/lib/main.dart` (replace Graficas tab placeholder)

**Interfaces:**
- Consumes: `expensesByCategory`, `monthlyIncomeVsExpense`, `MonthlyTotals`, `balanceOverTime`, `BalancePoint` (Task 6), `calculateAccountBalance` (Task 5), `AccountRepository`, `CategoryRepository`, `TransactionRepository` (Task 4).
- Produces: `ChartsScreen` widget using `fl_chart`'s `PieChart`, `BarChart` (x2), `LineChart`.

- [ ] **Step 1: Implement the screen**

Create `app/lib/screens/charts_screen.dart`:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/balance_calculator.dart';
import '../logic/chart_aggregator.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';

const _palette = [Colors.teal, Colors.orange, Colors.purple, Colors.blue, Colors.pink, Colors.brown, Colors.green, Colors.indigo];

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  final _accountRepo = AccountRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);

  late Future<(List<Account>, List<Category>, List<Transaction>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Account>, List<Category>, List<Transaction>)> _load() async {
    final accounts = await _accountRepo.fetchAll();
    final categories = await _categoryRepo.fetchAll();
    final transactions = await _transactionRepo.fetchAll();
    return (accounts, categories, transactions);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Graficas')),
      body: FutureBuilder<(List<Account>, List<Category>, List<Transaction>)>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final (accounts, categories, transactions) = snapshot.data!;
          final now = DateTime.now();
          final categoryNames = {for (final c in categories) c.id: c.nombre};

          final gastosPorCategoria = expensesByCategory(
            transactions: transactions,
            categoryNamesById: categoryNames,
            year: now.year,
            month: now.month,
          );
          final mensual = monthlyIncomeVsExpense(transactions: transactions, monthsBack: 6, referenceDate: now);
          final saldoEnElTiempo = balanceOverTime(accounts: accounts, transactions: transactions);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Gasto por categoria (este mes)', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(
                height: 220,
                child: gastosPorCategoria.isEmpty
                    ? const Center(child: Text('Sin gastos este mes'))
                    : PieChart(PieChartData(sections: [
                        for (final (i, entry) in gastosPorCategoria.entries.indexed)
                          PieChartSectionData(
                            value: entry.value,
                            title: entry.key,
                            color: _palette[i % _palette.length],
                            radius: 80,
                          ),
                      ])),
              ),
              const SizedBox(height: 32),
              Text('Ingresos vs gastos (6 meses)', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(
                height: 220,
                child: BarChart(BarChartData(
                  barGroups: [
                    for (final (i, m) in mensual.indexed)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(toY: m.ingresos, color: Colors.teal, width: 8),
                        BarChartRodData(toY: m.gastos, color: Colors.red, width: 8),
                      ]),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= mensual.length) return const SizedBox.shrink();
                          return Text('${mensual[i].month}/${mensual[i].year % 100}');
                        },
                      ),
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 32),
              Text('Evolucion del saldo', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(
                height: 220,
                child: saldoEnElTiempo.isEmpty
                    ? const Center(child: Text('Sin datos'))
                    : LineChart(LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (final (i, p) in saldoEnElTiempo.indexed) FlSpot(i.toDouble(), p.saldo),
                            ],
                            isCurved: false,
                            color: Colors.teal,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      )),
              ),
              const SizedBox(height: 32),
              Text('Saldo por cuenta', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(
                height: 220,
                child: BarChart(BarChartData(
                  barGroups: [
                    for (final (i, a) in accounts.indexed)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: calculateAccountBalance(saldoInicial: a.saldoInicial, accountId: a.id, transactions: transactions),
                          color: _palette[i % _palette.length],
                          width: 16,
                        ),
                      ]),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= accounts.length) return const SizedBox.shrink();
                          return Text(accounts[i].nombre, style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
                )),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Wire it into the app shell**

In `app/lib/main.dart`, add `import 'screens/charts_screen.dart';` and replace `const Center(child: Text('Graficas')), // replaced in Task 14` with `const ChartsScreen(),`.

- [ ] **Step 3: Manual verification**

Run: `flutter run --dart-define-from-file=env.json`, log in with an account that already has a few transactions across categories and months (create some via the FAB if needed), go to Graficas.
Expected: all four charts render with real data; the pie chart matches the current month's gastos, the balance line ends at the same total shown on Home.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/charts_screen.dart app/lib/main.dart
git commit -m "feat: add charts screen with category pie, monthly bars and balance line"
```

---

## Task 15: Offline outbox and connectivity sync

**Files:**
- Create: `app/lib/services/outbox_service.dart`
- Modify: `app/lib/main.dart` (register the Hive box)
- Modify: `app/lib/screens/home_screen.dart` (route transaction creation through the outbox)

**Interfaces:**
- Consumes: `Transaction` (Task 3), `TransactionRepository` (Task 4), `Hive` (Task 2), `connectivity_plus`.
- Produces: `OutboxService.create(Transaction) -> Future<void>` (tries the network write; on failure, queues locally), `OutboxService.flush() -> Future<void>` (pushes every queued item, called automatically on reconnect), `OutboxService.pendingCount -> int`.

- [ ] **Step 1: Implement the outbox service**

Create `app/lib/services/outbox_service.dart`:

```dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/transaction.dart';
import '../repositories/transaction_repository.dart';

class OutboxService {
  OutboxService(this._repository) {
    _box = Hive.box<Map>('outbox');
    Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) flush();
    });
  }

  final TransactionRepository _repository;
  late final Box<Map> _box;
  final _uuid = const Uuid();

  int get pendingCount => _box.length;

  Future<void> create(Transaction transaction) async {
    try {
      await _repository.create(transaction);
    } catch (_) {
      await _box.put(_uuid.v4(), transaction.toInsertJson());
    }
  }

  Future<void> flush() async {
    for (final key in _box.keys.toList()) {
      final json = Map<String, dynamic>.from(_box.get(key)!);
      try {
        final transaction = Transaction(
          id: '',
          userId: '',
          accountId: json['account_id'] as String,
          categoryId: json['category_id'] as String?,
          accountDestinoId: json['account_destino_id'] as String?,
          tipo: transactionTypeFromString(json['tipo'] as String),
          monto: (json['monto'] as num).toDouble(),
          fecha: DateTime.parse(json['fecha'] as String),
          nota: json['nota'] as String?,
        );
        await _repository.create(transaction);
        await _box.delete(key);
      } catch (_) {
        // stays queued, retried on the next connectivity change
      }
    }
  }
}
```

- [ ] **Step 2: Register the Hive box at startup**

In `app/lib/main.dart`, inside `main()` after `await Hive.initFlutter();`, add:

```dart
  await Hive.openBox<Map>('outbox');
```

- [ ] **Step 3: Route transaction creation through the outbox**

In `app/lib/screens/home_screen.dart`, add the import `import '../services/outbox_service.dart';`, add a field `final _outbox = OutboxService(TransactionRepository(Supabase.instance.client));` next to the other repo fields, and change the `onSubmit` callback inside `_openNewTransaction` from `await _transactionRepo.create(t);` to `await _outbox.create(t);`.

- [ ] **Step 4: Manual verification**

Run: `flutter run --dart-define-from-file=env.json`, log in. Turn on airplane mode on the device/emulator, create a gasto via the FAB.
Expected: no crash, the form closes normally. Turn airplane mode off.
Expected within a few seconds: the queued transaction appears in Supabase (check via `mcp__supabase__execute_sql` on the `transactions` table, or pull-to-refresh Home and see the balance updated).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/outbox_service.dart app/lib/main.dart app/lib/screens/home_screen.dart
git commit -m "feat: queue transaction writes offline and flush automatically on reconnect"
```

---

## Task 16: Release build and manual QA pass

**Files:**
- Create: `app/README.md`

**Interfaces:**
- Consumes: the whole app.
- Produces: a signed-or-debug release APK for installing on the personal device, and a written QA checklist confirming the spec's golden paths work end-to-end.

- [ ] **Step 1: Write setup/build instructions**

Create `app/README.md`:

```markdown
# Billetera

App personal de registro de ingresos, gastos, transferencias, cuentas y graficas.

## Setup

1. Copiar `env.json.example` a `env.json` y completar con la URL y anon key del proyecto Supabase (ver `supabase/migrations/0001_init.sql`).
2. `flutter pub get`
3. Crear tu usuario en el dashboard de Supabase (Authentication > Users > Add user), o habilitar signup y registrarte desde la app si se agrega esa pantalla mas adelante.

## Correr en desarrollo

```bash
flutter run --dart-define-from-file=env.json
```

## Build de release (APK para instalar en el celular)

```bash
flutter build apk --release --dart-define-from-file=env.json
```

APK queda en `build/app/outputs/flutter-apk/app-release.apk`. Se instala transfiriendolo al telefono y abriendolo (requiere permitir "instalar apps de origenes desconocidos" para el instalador usado).

## Tests

```bash
flutter test
```
```

- [ ] **Step 2: Build the release APK**

Run: `cd app && flutter build apk --release --dart-define-from-file=env.json`
Expected: BUILD SUCCESSFUL, `build/app/outputs/flutter-apk/app-release.apk` exists.

- [ ] **Step 3: Run the full test suite**

Run: `cd app && flutter test`
Expected: all tests pass (model, logic, and widget tests from Tasks 3, 5, 6, 10, 13).

- [ ] **Step 4: Manual QA checklist on device**

Install the APK on the personal phone (or run via `flutter run --release --dart-define-from-file=env.json` on a connected device) and walk through:

- [ ] Login with real credentials works; wrong password shows an error without crashing.
- [ ] Create one account of each tipo (efectivo, banco, credito, billetera_digital).
- [ ] Register one ingreso, one gasto, one transferencia between two of those accounts.
- [ ] Home shows correct saldo total and per-account balances after the above.
- [ ] Historial filters by cuenta, categoria and tipo correctly.
- [ ] Create a budget for a category already exceeded by a gasto; the progress bar shows red.
- [ ] Graficas: all four charts render and match the data entered.
- [ ] Turn on airplane mode, create a transaction, turn it back off — transaction shows up in Supabase within a few seconds.

- [ ] **Step 5: Commit**

```bash
git add app/README.md
git commit -m "docs: add setup, build and manual QA instructions"
```
