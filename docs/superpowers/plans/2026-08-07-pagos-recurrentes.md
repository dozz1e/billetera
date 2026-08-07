# Pagos recurrentes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user mark a gasto as "repeats every month" (e.g. a debt due the same day each month), and have the app auto-generate the real transaction each month when it becomes due, with no manual confirmation.

**Architecture:** A new `recurring_payments` table stores templates (account, category, monto, day-of-month), separate from `transactions` (the real ledger) — same split already used for `debts`/`goals` vs transactions. A pure function `computeDueOccurrences` decides which months are owed; a `RecurringPaymentService` (built on two narrow abstract interfaces so it's unit-testable with fakes, same pattern as `GooglePayListenerService`) turns those into real `Transaction` rows via the existing offline-first `OutboxService`. Generation runs once per app open, from `HomeScreen.initState`, mirroring the existing Google Pay listener wiring.

**Tech Stack:** Flutter, Supabase (Postgres + RLS), Hive (offline outbox, untouched by this feature), `flutter_test`.

## Global Constraints

- Spanish-language UI strings throughout (matches the rest of the app).
- RLS policy pattern: `for all using (auth.uid() = user_id) with check (auth.uid() = user_id)` — copied verbatim from every existing table.
- FK convention: references to `accounts`/`categories` use `on delete restrict` (spec: "mismo patrón que `debts`/`goals`" plus existing `transactions` table precedent in `0001_init.sql:23-25`).
- Only `tipo == gasto` can be recurring (spec, explicit).
- Recurrence is monthly only, indefinite (no end date, no cuota count) — spec, explicit "Fuera de alcance".
- Backfill capped at 12 months (spec, approved in brainstorming).
- No widget test for the new screen or the new tab — matches this codebase's existing convention (no test file exists for `AccountsScreen`, `DebtsScreen`, `GoalsScreen`, or the `BudgetsScreen`/`GoalsScreen` tab split).
- Repositories are never unit-tested directly in this codebase (confirmed: no test file for any existing `*_repository.dart`) — don't add one here either.

---

### Task 1: Database migration

**Files:**
- Create: `supabase/migrations/0004_recurring_payments.sql`

**Interfaces:**
- Produces: table `recurring_payments` (`id`, `user_id`, `account_id`, `category_id`, `monto`, `dia_mes`, `nota`, `fecha_inicio`, `ultima_generada`, `activo`, `created_at`) and a new nullable column `transactions.recurring_payment_id`. Every later task's SQL/model/repository code depends on these exact column names.

This task requires live Supabase DB credentials (`supabase db push`) — same as migration `0003_debts.sql`, applied directly by the controller rather than through the subagent task-review cycle. No unit test is possible for a migration in this codebase; verification is a manual `select` against `information_schema`.

- [ ] **Step 1: Write the migration**

```sql
create table recurring_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references accounts(id) on delete restrict,
  category_id uuid not null references categories(id) on delete restrict,
  monto numeric not null check (monto > 0),
  dia_mes integer not null check (dia_mes between 1 and 31),
  nota text,
  fecha_inicio date not null,
  ultima_generada date,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create index recurring_payments_user_activo_idx on recurring_payments(user_id, activo);

alter table recurring_payments enable row level security;

create policy "recurring_payments_owner" on recurring_payments
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

alter table transactions
  add column recurring_payment_id uuid references recurring_payments(id) on delete set null;
```

- [ ] **Step 2: Apply the migration**

Run: `cd /run/media/Respaldo/Trabajo/claude/billetera && supabase db push`
Expected: output confirms `0004_recurring_payments.sql` applied, no errors.

- [ ] **Step 3: Verify the schema**

Run (via `supabase db push` output or `psql`/Supabase SQL editor):
```sql
select column_name from information_schema.columns where table_name = 'recurring_payments' order by ordinal_position;
select column_name from information_schema.columns where table_name = 'transactions' and column_name = 'recurring_payment_id';
```
Expected: first query lists all 11 columns from Step 1; second returns one row.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0004_recurring_payments.sql
git commit -m "feat: add recurring_payments table and transactions.recurring_payment_id"
```

---

### Task 2: RecurringPayment model

**Files:**
- Create: `app/lib/models/recurring_payment.dart`
- Test: `app/test/models/recurring_payment_test.dart`

**Interfaces:**
- Consumes: nothing (leaf model, same tier as `Transaction`/`Debt`).
- Produces: `class RecurringPayment { id, userId, accountId, categoryId, monto (double), diaMes (int), fechaInicio (DateTime), nota (String?), activo (bool), ultimaGenerada (DateTime?) }`, `factory RecurringPayment.fromJson(Map<String, dynamic>)`, `Map<String, dynamic> toInsertJson()`. Every later task (repository, service, form, screen, tests) constructs/reads this exact shape.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/recurring_payment_test.dart
import 'package:billetera/models/recurring_payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RecurringPayment.fromJson parses a full row correctly', () {
    final json = {
      'id': 'r1',
      'user_id': 'u1',
      'account_id': 'a1',
      'category_id': 'c1',
      'monto': 15000.0,
      'dia_mes': 5,
      'nota': 'Arriendo',
      'fecha_inicio': '2026-01-05',
      'ultima_generada': '2026-03-05',
      'activo': true,
    };

    final r = RecurringPayment.fromJson(json);

    expect(r.id, 'r1');
    expect(r.accountId, 'a1');
    expect(r.categoryId, 'c1');
    expect(r.monto, 15000.0);
    expect(r.diaMes, 5);
    expect(r.nota, 'Arriendo');
    expect(r.fechaInicio, DateTime(2026, 1, 5));
    expect(r.ultimaGenerada, DateTime(2026, 3, 5));
    expect(r.activo, isTrue);
  });

  test('RecurringPayment.fromJson parses a null ultima_generada and nota', () {
    final json = {
      'id': 'r2',
      'user_id': 'u1',
      'account_id': 'a1',
      'category_id': 'c1',
      'monto': 5000.0,
      'dia_mes': 20,
      'nota': null,
      'fecha_inicio': '2026-06-20',
      'ultima_generada': null,
      'activo': false,
    };

    final r = RecurringPayment.fromJson(json);

    expect(r.nota, isNull);
    expect(r.ultimaGenerada, isNull);
    expect(r.activo, isFalse);
  });

  test('toInsertJson formats dates as yyyy-MM-dd and omits ultima_generada', () {
    final r = RecurringPayment(
      id: '',
      userId: '',
      accountId: 'a1',
      categoryId: 'c1',
      monto: 15000,
      diaMes: 5,
      fechaInicio: DateTime(2026, 1, 5),
      activo: true,
    );

    final json = r.toInsertJson();

    expect(json['fecha_inicio'], '2026-01-05');
    expect(json['account_id'], 'a1');
    expect(json['dia_mes'], 5);
    expect(json.containsKey('ultima_generada'), isFalse);
    expect(json.containsKey('id'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/recurring_payment_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'billetera/models/recurring_payment.dart'` (file doesn't exist yet).

- [ ] **Step 3: Write the model**

```dart
// app/lib/models/recurring_payment.dart
class RecurringPayment {
  const RecurringPayment({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.categoryId,
    required this.monto,
    required this.diaMes,
    required this.fechaInicio,
    this.nota,
    required this.activo,
    this.ultimaGenerada,
  });

  final String id;
  final String userId;
  final String accountId;
  final String categoryId;
  final double monto;
  final int diaMes;
  final DateTime fechaInicio;
  final String? nota;
  final bool activo;
  final DateTime? ultimaGenerada;

  factory RecurringPayment.fromJson(Map<String, dynamic> json) =>
      RecurringPayment(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        accountId: json['account_id'] as String,
        categoryId: json['category_id'] as String,
        monto: (json['monto'] as num).toDouble(),
        diaMes: json['dia_mes'] as int,
        fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
        nota: json['nota'] as String?,
        activo: json['activo'] as bool,
        ultimaGenerada: json['ultima_generada'] == null
            ? null
            : DateTime.parse(json['ultima_generada'] as String),
      );

  Map<String, dynamic> toInsertJson() => {
        'account_id': accountId,
        'category_id': categoryId,
        'monto': monto,
        'dia_mes': diaMes,
        'nota': nota,
        'fecha_inicio': fechaInicio.toIso8601String().split('T').first,
        'activo': activo,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/recurring_payment_test.dart`
Expected: `00:00 +3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/recurring_payment.dart app/test/models/recurring_payment_test.dart
git commit -m "feat: add RecurringPayment model"
```

---

### Task 3: RecurringPaymentRepository

**Files:**
- Create: `app/lib/repositories/recurring_payment_repository.dart`

**Interfaces:**
- Consumes: `RecurringPayment` (Task 2).
- Produces: `class RecurringPaymentRepository { fetchAll(), fetchActive(), create(RecurringPayment), setActivo(String id, bool activo), updateUltimaGenerada(String id, DateTime fecha), delete(String id) }`. Task 6 (`RecurringPaymentService`) calls `fetchActive`/`updateUltimaGenerada`; Task 8 (form) calls `create`; Task 9 (screen) calls `fetchAll`/`setActivo`/`delete`.

No test — matches this codebase's convention of leaving Supabase-backed repositories untested (see `DebtRepository`, `AccountRepository`, none of which have a test file).

- [ ] **Step 1: Write the repository**

```dart
// app/lib/repositories/recurring_payment_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/recurring_payment.dart';

class RecurringPaymentRepository {
  RecurringPaymentRepository(this._client);

  final SupabaseClient _client;

  Future<List<RecurringPayment>> fetchAll() async {
    final rows = await _client
        .from('recurring_payments')
        .select()
        .order('created_at');
    return (rows as List)
        .map((r) => RecurringPayment.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<RecurringPayment>> fetchActive() async {
    final rows = await _client
        .from('recurring_payments')
        .select()
        .eq('activo', true)
        .order('created_at');
    return (rows as List)
        .map((r) => RecurringPayment.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<RecurringPayment> create(RecurringPayment payment) async {
    final row = await _client
        .from('recurring_payments')
        .insert({
          ...payment.toInsertJson(),
          'user_id': _client.auth.currentUser!.id,
        })
        .select()
        .single();
    return RecurringPayment.fromJson(row);
  }

  Future<void> setActivo(String id, bool activo) async {
    await _client
        .from('recurring_payments')
        .update({'activo': activo})
        .eq('id', id);
  }

  Future<void> updateUltimaGenerada(String id, DateTime fecha) async {
    await _client
        .from('recurring_payments')
        .update({'ultima_generada': fecha.toIso8601String().split('T').first})
        .eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('recurring_payments').delete().eq('id', id);
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd app && flutter analyze lib/repositories/recurring_payment_repository.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/repositories/recurring_payment_repository.dart
git commit -m "feat: add RecurringPaymentRepository"
```

---

### Task 4: Transaction model + OutboxService gain `recurringPaymentId`

**Files:**
- Modify: `app/lib/models/transaction.dart`
- Modify: `app/lib/services/outbox_service.dart:48-58` (the manual reconstruction inside `_flushOnce`)
- Test: `app/test/models/transaction_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Transaction` gains a nullable `recurringPaymentId` field, read/written by `fromJson`/`toInsertJson`. Task 6 (`RecurringPaymentService`) sets this field when it builds a generated `Transaction`; the offline outbox path must preserve it too, or a queued-then-flushed generated transaction would silently lose its `recurring_payment_id` on retry.

- [ ] **Step 1: Write the failing test**

Add to `app/test/models/transaction_test.dart` (existing file — append inside `main()`, after the existing two tests):

```dart
  test('Transaction.fromJson parses recurring_payment_id', () {
    final json = {
      'id': 't1',
      'user_id': 'u1',
      'account_id': 'a1',
      'category_id': 'c1',
      'account_destino_id': null,
      'tipo': 'gasto',
      'monto': 15000.0,
      'fecha': '2026-08-01',
      'nota': null,
      'recurring_payment_id': 'r1',
    };

    final t = Transaction.fromJson(json);

    expect(t.recurringPaymentId, 'r1');
  });

  test('toInsertJson includes a null recurring_payment_id when absent', () {
    final t = Transaction(
      id: 't1',
      userId: 'u1',
      accountId: 'a1',
      categoryId: 'c1',
      tipo: TransactionType.gasto,
      monto: 1000.0,
      fecha: DateTime(2026, 8, 1),
    );

    expect(t.toInsertJson()['recurring_payment_id'], isNull);
  });

  test('toInsertJson round-trips a set recurring_payment_id', () {
    final t = Transaction(
      id: 't1',
      userId: 'u1',
      accountId: 'a1',
      categoryId: 'c1',
      tipo: TransactionType.gasto,
      monto: 1000.0,
      fecha: DateTime(2026, 8, 1),
      recurringPaymentId: 'r1',
    );

    expect(t.toInsertJson()['recurring_payment_id'], 'r1');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/transaction_test.dart`
Expected: FAIL — `The named parameter 'recurringPaymentId' isn't defined` / `The getter 'recurringPaymentId' isn't defined for the class 'Transaction'`.

- [ ] **Step 3: Add the field to Transaction**

In `app/lib/models/transaction.dart`, modify the constructor and fields:

```dart
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
    this.recurringPaymentId,
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
  final String? recurringPaymentId;

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
        recurringPaymentId: json['recurring_payment_id'] as String?,
      );

  Map<String, dynamic> toInsertJson() => {
        'account_id': accountId,
        'category_id': categoryId,
        'account_destino_id': accountDestinoId,
        'tipo': transactionTypeToString(tipo),
        'monto': monto,
        'fecha': fecha.toIso8601String().split('T').first,
        'nota': nota,
        'recurring_payment_id': recurringPaymentId,
      };
}
```

- [ ] **Step 4: Preserve the field through the offline outbox**

In `app/lib/services/outbox_service.dart`, inside `_flushOnce()`, the manual `Transaction(...)` reconstruction (currently lines 48-58) must also read `recurring_payment_id` back out of the queued JSON:

```dart
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
          recurringPaymentId: json['recurring_payment_id'] as String?,
        );
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/models/transaction_test.dart`
Expected: `00:00 +5: All tests passed!`

- [ ] **Step 6: Run the full suite to check nothing else broke**

Run: `cd app && flutter test`
Expected: `All tests passed!` (the pre-existing count plus 3 new ones).

- [ ] **Step 7: Commit**

```bash
git add app/lib/models/transaction.dart app/lib/services/outbox_service.dart app/test/models/transaction_test.dart
git commit -m "feat: add recurringPaymentId to Transaction and preserve it through the offline outbox"
```

---

### Task 5: `computeDueOccurrences` pure logic

**Files:**
- Create: `app/lib/logic/recurring_payment_generator.dart`
- Test: `app/test/logic/recurring_payment_generator_test.dart`

**Interfaces:**
- Consumes: nothing (pure function, no model dependency).
- Produces: `List<DateTime> computeDueOccurrences({required int diaMes, required DateTime fechaInicio, required DateTime? ultimaGenerada, required DateTime hoy, int maxBackfill = 12})`. Task 6 (`RecurringPaymentService`) calls this exact signature.

- [ ] **Step 1: Write the failing tests**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/logic/recurring_payment_generator_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'billetera/logic/recurring_payment_generator.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// app/lib/logic/recurring_payment_generator.dart
DateTime _occurrenceForMonth(int year, int month, int diaMes) {
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final day = diaMes > daysInMonth ? daysInMonth : diaMes;
  return DateTime(year, month, day);
}

/// Returns one due date per month owed between the last generated month
/// (or [fechaInicio]'s month if [ultimaGenerada] is null) and [hoy],
/// inclusive, skipping any month whose occurrence date is still in the
/// future relative to [hoy]. If more than [maxBackfill] months are owed,
/// only the most recent [maxBackfill] are returned — older ones are
/// silently dropped rather than generating years of backlog at once.
List<DateTime> computeDueOccurrences({
  required int diaMes,
  required DateTime fechaInicio,
  required DateTime? ultimaGenerada,
  required DateTime hoy,
  int maxBackfill = 12,
}) {
  var cursorMonth = ultimaGenerada == null
      ? DateTime(fechaInicio.year, fechaInicio.month)
      : DateTime(ultimaGenerada.year, ultimaGenerada.month + 1);
  final lastMonth = DateTime(hoy.year, hoy.month);

  final due = <DateTime>[];
  while (!cursorMonth.isAfter(lastMonth)) {
    final occurrence = _occurrenceForMonth(
      cursorMonth.year,
      cursorMonth.month,
      diaMes,
    );
    if (!occurrence.isAfter(hoy)) {
      due.add(occurrence);
    }
    cursorMonth = DateTime(cursorMonth.year, cursorMonth.month + 1);
  }

  if (due.length > maxBackfill) {
    return due.sublist(due.length - maxBackfill);
  }
  return due;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/logic/recurring_payment_generator_test.dart`
Expected: `00:00 +6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/logic/recurring_payment_generator.dart app/test/logic/recurring_payment_generator_test.dart
git commit -m "feat: add computeDueOccurrences for recurring payment scheduling"
```

---

### Task 6: RecurringPaymentService

**Files:**
- Create: `app/lib/services/recurring_payment_service.dart`
- Modify: `app/lib/repositories/recurring_payment_repository.dart` (add `implements RecurringPaymentSource`)
- Modify: `app/lib/services/outbox_service.dart` (add `implements TransactionSink`)
- Test: `app/test/services/recurring_payment_service_test.dart`

**Interfaces:**
- Consumes: `RecurringPayment` (Task 2), `computeDueOccurrences` (Task 5), `Transaction` with `recurringPaymentId` (Task 4), `Account`/`Category` models (existing).
- Produces: `abstract class RecurringPaymentSource { fetchActive(); updateUltimaGenerada(id, fecha); }`, `abstract class TransactionSink { create(Transaction); }`, `class RecurringPaymentService { RecurringPaymentService(RecurringPaymentSource, TransactionSink, List<Account>, List<Category>); Future<int> generateDue({DateTime? today}); }`. Task 7 (HomeScreen wiring) instantiates this exact constructor and calls `generateDue()`.

`RecurringPaymentSource`/`TransactionSink` exist so this service is testable with fakes instead of a live Supabase client and Hive box — same reason `GooglePayListenerService` depends on the abstract `GooglePayNotificationSource` rather than a concrete plugin class.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/services/recurring_payment_service_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/recurring_payment_service_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'billetera/services/recurring_payment_service.dart'`.

- [ ] **Step 3: Write the service**

```dart
// app/lib/services/recurring_payment_service.dart
import 'package:flutter/foundation.dart' show debugPrint;

import '../logic/recurring_payment_generator.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/recurring_payment.dart';
import '../models/transaction.dart';

/// Narrow read/write surface RecurringPaymentService needs from
/// RecurringPaymentRepository — lets tests substitute a fake instead of a
/// live Supabase-backed repository.
abstract class RecurringPaymentSource {
  Future<List<RecurringPayment>> fetchActive();
  Future<void> updateUltimaGenerada(String id, DateTime fecha);
}

/// Narrow write surface RecurringPaymentService needs from OutboxService —
/// lets tests substitute a fake instead of a live Hive/Supabase-backed
/// outbox.
abstract class TransactionSink {
  Future<void> create(Transaction transaction);
}

class RecurringPaymentService {
  RecurringPaymentService(
    this._source,
    this._sink,
    this._accounts,
    this._categories,
  );

  final RecurringPaymentSource _source;
  final TransactionSink _sink;
  final List<Account> _accounts;
  final List<Category> _categories;

  /// Generates every Transaction due for the active recurring payments, up
  /// to [today] (defaults to `DateTime.now()`). Returns how many were
  /// generated. Never throws — a failure (e.g. no network) is logged and
  /// treated as "generated 0" so it never blocks HomeScreen from loading.
  Future<int> generateDue({DateTime? today}) async {
    final hoy = today ?? DateTime.now();
    try {
      final templates = await _source.fetchActive();
      var generated = 0;

      for (final template in templates) {
        final accountExists = _accounts.any((a) => a.id == template.accountId);
        final categoryExists = _categories.any((c) => c.id == template.categoryId);
        if (!accountExists || !categoryExists) continue;

        final due = computeDueOccurrences(
          diaMes: template.diaMes,
          fechaInicio: template.fechaInicio,
          ultimaGenerada: template.ultimaGenerada,
          hoy: hoy,
        );
        if (due.isEmpty) continue;

        for (final fecha in due) {
          await _sink.create(
            Transaction(
              id: '',
              userId: '',
              accountId: template.accountId,
              categoryId: template.categoryId,
              tipo: TransactionType.gasto,
              monto: template.monto,
              fecha: fecha,
              nota: template.nota,
              recurringPaymentId: template.id,
            ),
          );
          generated++;
        }
        await _source.updateUltimaGenerada(template.id, due.last);
      }
      return generated;
    } catch (e) {
      debugPrint('RecurringPaymentService: failed to generate due payments: $e');
      return 0;
    }
  }
}
```

- [ ] **Step 4: Wire the concrete classes into the interfaces**

In `app/lib/repositories/recurring_payment_repository.dart`, add the import and `implements` clause:

```dart
import '../services/recurring_payment_service.dart';
```

```dart
class RecurringPaymentRepository implements RecurringPaymentSource {
```

In `app/lib/services/outbox_service.dart`, add the import and `implements` clause:

```dart
import 'recurring_payment_service.dart';
```

```dart
class OutboxService implements TransactionSink {
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/services/recurring_payment_service_test.dart`
Expected: `00:00 +5: All tests passed!`

- [ ] **Step 6: Run the full suite and analyze**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` then `All tests passed!`.

- [ ] **Step 7: Commit**

```bash
git add app/lib/services/recurring_payment_service.dart app/lib/repositories/recurring_payment_repository.dart app/lib/services/outbox_service.dart app/test/services/recurring_payment_service_test.dart
git commit -m "feat: add RecurringPaymentService with testable source/sink interfaces"
```

---

### Task 7: Wire generation into HomeScreen

**Files:**
- Modify: `app/lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: `RecurringPaymentRepository` (Task 3, now `implements RecurringPaymentSource`), `RecurringPaymentService` (Task 6), the existing `_outbox` field (now `implements TransactionSink`), existing `_accountRepo`/`_categoryRepo`.
- Produces: nothing new consumed by later tasks — Task 8 modifies this same file's `_openNewTransaction`, so re-read the file after this task lands rather than relying on the snippet below going stale.

No new test file — matches this codebase's convention (no `home_screen_test.dart` exists; the equivalent Google Pay listener wiring in this same file has no dedicated test either). Verified via `flutter analyze` + full suite + a manual read-through of the diff.

- [ ] **Step 1: Add the repository field and a generation method**

In `app/lib/screens/home_screen.dart`, add the import:

```dart
import '../repositories/recurring_payment_repository.dart';
import '../services/recurring_payment_service.dart';
```

Add a field next to the existing repositories (after `_transactionRepo`):

```dart
  final _recurringRepo = RecurringPaymentRepository(Supabase.instance.client);
```

Add a new private method, placed after `_load()`:

```dart
  Future<void> _generateDueRecurringPayments() async {
    try {
      final accounts = await _accountRepo.fetchAll();
      final categories = await _categoryRepo.fetchAll();
      if (!mounted) return;
      final service = RecurringPaymentService(
        _recurringRepo,
        _outbox,
        accounts,
        categories,
      );
      final count = await service.generateDue();
      if (count > 0 && mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Se generaron $count pago(s) recurrente(s) pendiente(s).',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('HomeScreen: failed to generate due recurring payments: $e');
    }
  }
```

- [ ] **Step 2: Call it from initState**

In `app/lib/screens/home_screen.dart`, `initState()` currently ends with the Google Pay listener's `.onError(...)` call. Add the new call right after it, still inside `initState()`:

```dart
  @override
  void initState() {
    super.initState();
    _future = _load();
    // Started only once categories are available (needed to resolve the
    // suggested category id) — non-fatal if this fails, same pattern as the
    // account/category prefetch in HistoryScreen.initState.
    _categoryRepo.fetchAll().then((categories) {
      if (!mounted) return;
      _googlePayListener = GooglePayListenerService(
        PluginGooglePayNotificationSource(),
        Hive.box<Map>(googlePayPendingBoxName),
        categories,
      )..start();
    }).onError((e, st) {
      debugPrint('HomeScreen: failed to start Google Pay listener: $e');
    });
    _generateDueRecurringPayments();
  }
```

- [ ] **Step 3: Verify it compiles and existing tests still pass**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` then `All tests passed!` (this task adds no test, so the count is unchanged from Task 6's run).

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/home_screen.dart
git commit -m "feat: generate due recurring payments when HomeScreen loads"
```

---

### Task 8: "Repetir cada mes" checkbox in TransactionFormScreen

**Files:**
- Modify: `app/lib/screens/transaction_form_screen.dart`
- Modify: `app/lib/screens/home_screen.dart` (`_openNewTransaction`)
- Test: `app/test/screens/transaction_form_screen_test.dart`

**Interfaces:**
- Consumes: `RecurringPayment` (Task 2), `RecurringPaymentRepository.create` (Task 3), `_generateDueRecurringPayments()` (Task 7, called again here so a same-day recurring template generates its first occurrence immediately instead of waiting for the next app restart).
- Produces: `TransactionFormScreen` gains an optional `onSubmitRecurring: Future<void> Function(RecurringPayment)?` constructor parameter. No later task depends on this.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/screens/transaction_form_screen_test.dart`. First add the import at the top of the file:

```dart
import 'package:billetera/models/recurring_payment.dart';
```

Then add these three tests inside `main()`, after the existing tests:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/screens/transaction_form_screen_test.dart`
Expected: FAIL — `No named parameter with the name 'onSubmitRecurring'`.

- [ ] **Step 3: Add the constructor parameter and state**

In `app/lib/screens/transaction_form_screen.dart`, add the import:

```dart
import '../models/recurring_payment.dart';
```

Modify the widget's constructor and fields:

```dart
class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({
    super.key,
    required this.accounts,
    required this.categories,
    required this.onSubmit,
    this.onSubmitRecurring,
    this.initial,
  });

  final List<Account> accounts;
  final List<Category> categories;
  final Future<void> Function(Transaction) onSubmit;
  final Future<void> Function(RecurringPayment)? onSubmitRecurring;
  final Transaction? initial;

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}
```

Add state, alongside the existing `_error` field:

```dart
  bool _recurrente = false;
```

- [ ] **Step 4: Reset the flag when tipo changes away from gasto**

Modify the `SegmentedButton`'s `onSelectionChanged`:

```dart
              onSelectionChanged: (s) => setState(() {
                _tipo = s.first;
                _categoryId = null;
                if (_tipo != TransactionType.gasto) _recurrente = false;
              }),
```

- [ ] **Step 5: Add the checkbox to the form**

In the `build()` method, insert this right after the `fecha` `Row` (the one with `_pickFecha`/`Cambiar`), before the `if (_error != null)` block:

```dart
            if (!_isEditing &&
                _tipo == TransactionType.gasto &&
                widget.onSubmitRecurring != null) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('recurrente_checkbox'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Repetir cada mes'),
                value: _recurrente,
                onChanged: (v) => setState(() => _recurrente = v ?? false),
              ),
            ],
```

- [ ] **Step 6: Branch _submit() on the recurrente flag**

Replace `_submit()` with:

```dart
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

    if (_recurrente) {
      final recurring = RecurringPayment(
        id: '',
        userId: '',
        accountId: _accountId!,
        categoryId: _categoryId!,
        monto: monto,
        diaMes: _fecha.day,
        fechaInicio: _fecha,
        nota: _notaController.text.trim().isEmpty ? null : _notaController.text.trim(),
        activo: true,
      );
      try {
        await widget.onSubmitRecurring!(recurring);
      } catch (e) {
        if (mounted) {
          setState(() => _error = 'No se pudo guardar el pago recurrente. Revisa tu conexion e intenta de nuevo.');
        }
      }
      return;
    }

    final transaction = Transaction(
      id: widget.initial?.id ?? '',
      userId: widget.initial?.userId ?? '',
      accountId: _accountId!,
      categoryId: _tipo == TransactionType.transferencia ? null : _categoryId,
      accountDestinoId: _tipo == TransactionType.transferencia ? _accountDestinoId : null,
      tipo: _tipo,
      monto: monto,
      fecha: _fecha,
      nota: _notaController.text.trim().isEmpty ? null : _notaController.text.trim(),
    );

    try {
      await widget.onSubmit(transaction);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo guardar la transaccion. Revisa tu conexion e intenta de nuevo.');
      }
    }
  }
```

- [ ] **Step 7: Run test to verify it passes**

Run: `cd app && flutter test test/screens/transaction_form_screen_test.dart`
Expected: `00:00 +8: All tests passed!` (5 existing + 3 new).

- [ ] **Step 8: Wire HomeScreen to pass onSubmitRecurring**

In `app/lib/screens/home_screen.dart`, `_openNewTransaction()`, add `onSubmitRecurring` to the `TransactionFormScreen(...)` call, alongside the existing `onSubmit`:

```dart
        builder: (context) => TransactionFormScreen(
          accounts: accounts.where((a) => a.activo).toList(),
          categories: categories,
          // OutboxService.create() deliberately swallows network-failure
          // exceptions and queues the transaction locally instead of
          // rethrowing (offline-first by design, see outbox_service.dart).
          // So unlike the old direct _transactionRepo.create(t) call, a
          // network failure here will NOT reach
          // TransactionFormScreen._submit()'s error-surfacing catch: it
          // queues silently and the form closes normally below, same as a
          // successful write. The pendingCount check after this screen
          // closes is what tells the user their transaction was queued
          // rather than actually saved.
          onSubmit: (t) async {
            await _outbox.create(t);
            if (context.mounted) Navigator.pop(context);
          },
          onSubmitRecurring: (r) async {
            await _recurringRepo.create(r);
            if (context.mounted) Navigator.pop(context);
            // Unlike a normal transaction, creating a template alone doesn't
            // put anything in the ledger — if fechaInicio is today or past,
            // this generates that first occurrence immediately instead of
            // leaving it stuck until the next full app restart (initState
            // already ran once before this FAB was tapped).
            await _generateDueRecurringPayments();
          },
        ),
```

- [ ] **Step 9: Run the full suite and analyze**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` then `All tests passed!`.

- [ ] **Step 10: Commit**

```bash
git add app/lib/screens/transaction_form_screen.dart app/lib/screens/home_screen.dart app/test/screens/transaction_form_screen_test.dart
git commit -m "feat: add repeat-monthly checkbox to the transaction form"
```

---

### Task 9: "Recurrentes" sub-tab in BudgetsScreen

**Files:**
- Create: `app/lib/screens/recurring_payments_screen.dart`
- Modify: `app/lib/screens/budgets_screen.dart`

**Interfaces:**
- Consumes: `RecurringPaymentRepository` (Task 3), `RecurringPayment` (Task 2), `CategoryRepository` (existing), `confirmDelete` (existing, `app/lib/core/dialogs.dart`).
- Produces: `class RecurringPaymentsScreen extends StatefulWidget`. Nothing later depends on it — it's a leaf screen.

No test — matches this codebase's convention (no test file for `GoalsScreen`, `DebtsScreen`, or the tab wiring in `BudgetsScreen`).

- [ ] **Step 1: Write RecurringPaymentsScreen**

```dart
// app/lib/screens/recurring_payments_screen.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/dialogs.dart';
import '../models/recurring_payment.dart';
import '../repositories/category_repository.dart';
import '../repositories/recurring_payment_repository.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤ #,##0',
);

class RecurringPaymentsScreen extends StatefulWidget {
  const RecurringPaymentsScreen({super.key});

  @override
  State<RecurringPaymentsScreen> createState() =>
      _RecurringPaymentsScreenState();
}

class _RecurringPaymentsScreenState extends State<RecurringPaymentsScreen> {
  final _repo = RecurringPaymentRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  late Future<List<RecurringPayment>> _future;
  Map<String, String> _categoryNames = {};

  @override
  void initState() {
    super.initState();
    _reload();
    _categoryRepo.fetchAll().then((categories) {
      if (mounted) {
        setState(
          () => _categoryNames = {for (final c in categories) c.id: c.nombre},
        );
      }
    }).onError((e, st) {
      debugPrint('RecurringPaymentsScreen: failed to load categories: $e');
    });
  }

  void _reload() => setState(() {
    _future = _repo.fetchAll();
  });

  Future<void> _togglePausa(RecurringPayment payment) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.setActivo(payment.id, !payment.activo);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            payment.activo
                ? 'No se pudo pausar el pago recurrente. Revisa tu conexion e intenta de nuevo.'
                : 'No se pudo reanudar el pago recurrente. Revisa tu conexion e intenta de nuevo.',
          ),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }

  Future<void> _delete(RecurringPayment payment) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Eliminar pago recurrente',
      message:
          'Vas a eliminar este pago recurrente. Las transacciones ya generadas no se borran.',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.delete(payment.id);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar el pago recurrente. Revisa tu conexion e intenta de nuevo.',
          ),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<RecurringPayment>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final payments = snapshot.data!;
        if (payments.isEmpty) {
          return const Center(child: Text('Sin pagos recurrentes'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  for (final (i, p) in payments.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.primary.withValues(
                          alpha: p.activo ? 0.16 : 0.06,
                        ),
                        child: Icon(
                          Icons.repeat,
                          color: p.activo
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(_categoryNames[p.categoryId] ?? 'Categoria'),
                      subtitle: Text(
                        '${_currency.format(p.monto)} · dia ${p.diaMes}'
                        '${p.activo ? '' : ' · pausado'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              p.activo
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                            ),
                            tooltip: p.activo ? 'Pausar' : 'Reanudar',
                            onPressed: () => _togglePausa(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Eliminar',
                            color: scheme.error,
                            onPressed: () => _delete(p),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd app && flutter analyze lib/screens/recurring_payments_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Register it as the third sub-tab in BudgetsScreen**

In `app/lib/screens/budgets_screen.dart`, add the import:

```dart
import 'recurring_payments_screen.dart';
```

Modify the `build()` method's `DefaultTabController`/`TabBar`/`TabBarView` (currently `length: 2` with two tabs/children):

```dart
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Presupuestos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Presupuestos'),
              Tab(text: 'Metas'),
              Tab(text: 'Recurrentes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
```

...(the existing `Scaffold(...presupuestos tab body...)` stays as-is)...

```dart
            const GoalsScreen(),
            const RecurringPaymentsScreen(),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the full suite and analyze**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` then `All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/recurring_payments_screen.dart app/lib/screens/budgets_screen.dart
git commit -m "feat: add Recurrentes sub-tab to manage recurring payments"
```

---

### Task 10: Rebuild the debug APK and manual smoke test

**Files:** none (build + manual verification only).

**Interfaces:** none — terminal task.

- [ ] **Step 1: Rebuild**

Run: `cd app && flutter build apk --debug --dart-define-from-file=env.json && cp build/app/outputs/flutter-apk/app-debug.apk dist/billetera-debug.apk`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 2: Manual smoke test (emulator or device)**

1. Open a gasto transaction, check "Repetir cada mes", pick today's date, save. Confirm it does **not** appear twice — HomeScreen's `_generateDueRecurringPayments()` should generate exactly one transaction for today immediately (SnackBar "Se generaron 1 pago(s)...").
2. Go to Presupuestos → Recurrentes tab, confirm the new template is listed with the right categoria/monto/dia.
3. Tap "Pausar", confirm it's marked pausado and no longer regenerates.
4. Tap "Reanudar", then "Eliminar", confirm `confirmDelete` gates it and the row disappears after confirming.

- [ ] **Step 3: Commit (if the smoke test surfaced fixes)**

Only if Step 2 required code changes — otherwise this task ends at Step 2 with no commit.
