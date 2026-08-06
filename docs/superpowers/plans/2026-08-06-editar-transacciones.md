# Editar / eliminar transacciones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user edit and delete transactions from `HistoryScreen`, matching the edit/delete pattern already used on Accounts, Categories, Budgets and Goals.

**Architecture:** `TransactionRepository` gains `update`/`delete` (mirrors `AccountRepository`). `NewTransactionScreen` is generalized into `TransactionFormScreen` with an optional `initial` transaction (edit mode) and a new date field. `HistoryScreen` adds edit/delete `IconButton`s per row that open the form / confirm-and-delete, reusing the account and category lists it already loads for its filters.

**Tech Stack:** Flutter, Supabase (`supabase_flutter`), `flutter_test`.

## Global Constraints

- UI strings stay accent-free ASCII, matching the rest of the app (e.g. "transaccion", "Categoria" — not "transacción", "Categoría").
- Edit/delete apply only to transactions already returned by `TransactionRepository.fetchAll()` (server-synced). Transactions still queued in the offline outbox (`OutboxService`) are out of scope — untouched by this plan.
- No balance-reconciliation logic is added. `calculateAccountBalance()` (`lib/logic/balance_calculator.dart`) recomputes from the live transaction list on every load, so edits/deletes propagate automatically.
- Date picker bounds: `firstDate: DateTime(2000)`, `lastDate: DateTime.now()` — transactions are never future-dated.
- Screens that build their repositories directly from `Supabase.instance.client` in `initState` (`HistoryScreen`, like `AccountsScreen`) have no widget test today — that's an existing codebase convention (Supabase isn't mocked in tests), not something this plan changes. `TransactionFormScreen` takes its data via constructor params, so it stays testable and keeps its test coverage.

---

### Task 1: Add `update`/`delete` to `TransactionRepository`

**Files:**
- Modify: `app/lib/repositories/transaction_repository.dart`

**Interfaces:**
- Produces: `Future<Transaction> update(String id, Map<String, dynamic> changes)`, `Future<void> delete(String id)` — both used by Task 4 (`HistoryScreen`).

No new test file: mirrors `AccountRepository.update`/`delete` (`app/lib/repositories/account_repository.dart:29-38`), which also has no dedicated unit test — coverage comes from the screens that call it. Verified here via `flutter analyze`.

- [ ] **Step 1: Add `update` and `delete` methods**

In `app/lib/repositories/transaction_repository.dart`, add after `create`:

```dart
  Future<Transaction> update(String id, Map<String, dynamic> changes) async {
    final row = await _client
        .from('transactions')
        .update(changes)
        .eq('id', id)
        .select()
        .single();
    return Transaction.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('transactions').delete().eq('id', id);
  }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd app && flutter analyze lib/repositories/transaction_repository.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/repositories/transaction_repository.dart
git commit -m "feat: add update/delete to TransactionRepository"
```

---

### Task 2: Generalize `NewTransactionScreen` into `TransactionFormScreen` (edit mode + date field)

**Files:**
- Rename: `app/lib/screens/new_transaction_screen.dart` → `app/lib/screens/transaction_form_screen.dart`
- Rename: `app/test/screens/new_transaction_screen_test.dart` → `app/test/screens/transaction_form_screen_test.dart`

**Interfaces:**
- Consumes: `Account`, `Category`, `Transaction`, `TransactionType` from `app/lib/models/*` (unchanged).
- Produces: `TransactionFormScreen({required accounts, required categories, required onSubmit, Transaction? initial})` — widget used by Task 3 (`HomeScreen`) and Task 4 (`HistoryScreen`).

- [ ] **Step 1: Rename the screen and test files**

```bash
cd app
git mv lib/screens/new_transaction_screen.dart lib/screens/transaction_form_screen.dart
git mv test/screens/new_transaction_screen_test.dart test/screens/transaction_form_screen_test.dart
```

- [ ] **Step 2: Write the failing tests (edit prefill + date picker)**

Replace the contents of `app/test/screens/transaction_form_screen_test.dart` with:

```dart
import 'package:billetera/models/account.dart';
import 'package:billetera/models/category.dart';
import 'package:billetera/models/transaction.dart';
import 'package:billetera/screens/transaction_form_screen.dart';
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
      home: TransactionFormScreen(accounts: _accounts, categories: _categories, onSubmit: (_) async {}),
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
      home: TransactionFormScreen(
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

  testWidgets('prefills fields from initial transaction and shows edit title', (tester) async {
    final initial = Transaction(
      id: 't1',
      userId: 'u1',
      accountId: 'a2',
      categoryId: 'c1',
      tipo: TransactionType.gasto,
      monto: 2500,
      fecha: DateTime(2026, 5, 10),
      nota: 'Super',
    );

    await tester.pumpWidget(MaterialApp(
      home: TransactionFormScreen(
        accounts: _accounts,
        categories: _categories,
        onSubmit: (_) async {},
        initial: initial,
      ),
    ));

    expect(find.text('Editar transaccion'), findsOneWidget);
    expect(find.text('2500.0'), findsOneWidget);
    expect(find.text('Super'), findsOneWidget);
    expect(find.text('10/05/2026'), findsOneWidget);
  });

  testWidgets('changing the date via the date picker updates the submitted transaction', (tester) async {
    Transaction? submitted;
    final today = DateTime.now();

    await tester.pumpWidget(MaterialApp(
      home: TransactionFormScreen(
        accounts: _accounts,
        categories: _categories,
        onSubmit: (t) async {
          submitted = t;
        },
      ),
    ));

    // Day 1 is always <= today regardless of what day the suite runs on,
    // so it's always selectable under lastDate: DateTime.now().
    await tester.tap(find.byKey(const Key('fecha_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('monto_field')), '1000');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.fecha, DateTime(today.year, today.month, 1));
  });
}
```

- [ ] **Step 3: Run tests to verify the new ones fail**

Run: `cd app && flutter test test/screens/transaction_form_screen_test.dart`
Expected: FAIL — `TransactionFormScreen` doesn't exist yet (compile error), or (once the class exists but before the edit/date changes) the two new tests fail while the two renamed ones pass.

- [ ] **Step 4: Rewrite `transaction_form_screen.dart`**

Replace the full contents of `app/lib/screens/transaction_form_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({
    super.key,
    required this.accounts,
    required this.categories,
    required this.onSubmit,
    this.initial,
  });

  final List<Account> accounts;
  final List<Category> categories;
  final Future<void> Function(Transaction) onSubmit;
  final Transaction? initial;

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  late TransactionType _tipo;
  String? _accountId;
  String? _accountDestinoId;
  String? _categoryId;
  late DateTime _fecha;
  final _montoController = TextEditingController();
  final _notaController = TextEditingController();
  String? _error;

  bool get _isEditing => widget.initial != null;

  List<Category> get _categoriasFiltradas => widget.categories
      .where((c) => c.tipo == (_tipo == TransactionType.ingreso ? 'ingreso' : 'gasto'))
      .toList();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _tipo = initial?.tipo ?? TransactionType.gasto;
    _fecha = initial?.fecha ?? DateTime.now();
    _accountDestinoId = initial?.accountDestinoId;
    if (initial != null) {
      _montoController.text = initial.monto.toString();
      _notaController.text = initial.nota ?? '';
      _accountId = initial.accountId;
      _categoryId = initial.categoryId;
    } else {
      if (widget.accounts.isNotEmpty) _accountId = widget.accounts.first.id;
      if (_categoriasFiltradas.isNotEmpty) _categoryId = _categoriasFiltradas.first.id;
    }
  }

  @override
  void dispose() {
    _montoController.dispose();
    _notaController.dispose();
    super.dispose();
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

  Future<void> _pickFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar transaccion' : 'Nueva transaccion')),
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
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Cuenta'),
              items: widget.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))).toList(),
              onChanged: (v) => setState(() => _accountId = v),
            ),
            if (_tipo == TransactionType.transferencia) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _accountDestinoId,
                decoration: const InputDecoration(labelText: 'Cuenta destino'),
                items: widget.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))).toList(),
                onChanged: (v) => setState(() => _accountDestinoId = v),
              ),
            ] else ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: _categoriasFiltradas.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))).toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(controller: _notaController, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fecha: ${_dateFormat.format(_fecha)}'),
                TextButton(
                  key: const Key('fecha_button'),
                  onPressed: _pickFecha,
                  child: const Text('Cambiar'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton(onPressed: _submit, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/screens/transaction_form_screen_test.dart`
Expected: `00:0X +4: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/transaction_form_screen.dart app/test/screens/transaction_form_screen_test.dart
git commit -m "feat: generalize NewTransactionScreen into TransactionFormScreen with edit mode and date field"
```

(`git mv` in Step 1 already staged the rename; the old paths no longer exist on disk, so only the new paths are addressable here. `git status` will show clean renames, not add+delete pairs.)

---

### Task 3: Update `HomeScreen` to use `TransactionFormScreen`

**Files:**
- Modify: `app/lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: `TransactionFormScreen` from Task 2 (same constructor shape as the old `NewTransactionScreen`, so this is a pure rename — no behavior change).

- [ ] **Step 1: Update the import and the widget reference**

In `app/lib/screens/home_screen.dart:13`, change:

```dart
import 'new_transaction_screen.dart';
```

to:

```dart
import 'transaction_form_screen.dart';
```

In `app/lib/screens/home_screen.dart:71`, change:

```dart
        builder: (context) => NewTransactionScreen(
```

to:

```dart
        builder: (context) => TransactionFormScreen(
```

- [ ] **Step 2: Verify it compiles**

Run: `cd app && flutter analyze lib/screens/home_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run the full test suite to check nothing else references the old name**

Run: `cd app && flutter test`
Expected: all tests pass (same count as before this plan, plus the 2 new ones from Task 2).

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/home_screen.dart
git commit -m "refactor: HomeScreen uses renamed TransactionFormScreen"
```

---

### Task 4: Add edit/delete actions to `HistoryScreen`

**Files:**
- Modify: `app/lib/screens/history_screen.dart`

**Interfaces:**
- Consumes: `TransactionFormScreen` (Task 2), `TransactionRepository.update`/`.delete` (Task 1), `confirmDelete` (`app/lib/core/dialogs.dart:59`).

No new automated test — `HistoryScreen` builds its repositories from `Supabase.instance.client` in `initState`, same as `AccountsScreen`, which also has no widget test (see Global Constraints). Verified via `flutter analyze` plus a manual smoke test on the emulator.

- [ ] **Step 1: Add imports and the edit/delete methods**

In `app/lib/screens/history_screen.dart`, add to the imports (after the existing `transaction_repository.dart` import):

```dart
import '../core/dialogs.dart';
import 'transaction_form_screen.dart';
```

Add these methods to `_HistoryScreenState`, right after `_reload()`:

```dart
  Future<void> _openEdit(Transaction t) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionFormScreen(
          accounts: _accounts,
          categories: _categories,
          initial: t,
          onSubmit: (updated) async {
            await _transactionRepo.update(t.id, updated.toInsertJson());
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _delete(Transaction t) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Eliminar transaccion',
      message: 'Vas a eliminar esta transaccion. Esta accion no se puede deshacer.',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _transactionRepo.delete(t.id);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo eliminar la transaccion. Revisa tu conexion e intenta de nuevo.'),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }
```

`_accounts` passed to `TransactionFormScreen` here is the screen's full unfiltered list (used today for the filter dropdown), so a transaction against a since-deactivated account still finds its account in the dropdown — unlike `HomeScreen._openNewTransaction`, which filters to active accounts only for *new* transactions.

- [ ] **Step 2: Wire the trailing buttons on each transaction row**

In `app/lib/screens/history_screen.dart`, inside the `ListTile` builder (around line 171), change:

```dart
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: visual.color.withValues(
                                      alpha: 0.16,
                                    ),
                                    child: Icon(
                                      visual.icon,
                                      color: visual.color,
                                    ),
                                  ),
                                  title: Text(_currency.format(t.monto)),
                                  subtitle: Text(t.nota ?? t.tipo.name),
                                  trailing: Text(
                                    DateFormat('dd/MM/yyyy').format(t.fecha),
                                  ),
                                );
```

to:

```dart
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: visual.color.withValues(
                                      alpha: 0.16,
                                    ),
                                    child: Icon(
                                      visual.icon,
                                      color: visual.color,
                                    ),
                                  ),
                                  title: Text(_currency.format(t.monto)),
                                  subtitle: Text(t.nota ?? t.tipo.name),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(DateFormat('dd/MM/yyyy').format(t.fecha)),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: 'Editar',
                                        onPressed: () => _openEdit(t),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: 'Eliminar',
                                        color: Theme.of(context).colorScheme.error,
                                        onPressed: () => _delete(t),
                                      ),
                                    ],
                                  ),
                                );
```

- [ ] **Step 3: Verify it compiles**

Run: `cd app && flutter analyze lib/screens/history_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the full test suite**

Run: `cd app && flutter test`
Expected: all tests pass (same set as after Task 3 — this task adds no new automated tests).

- [ ] **Step 5: Manual smoke test on the emulator**

Use the `run` skill (or `flutter run` against a running emulator/device) to launch the app, go to Historial, and confirm:
- Tapping the pencil icon on a transaction opens the form pre-filled with its data (including the correct date), and saving updates the row and the account balance shown on Home.
- Tapping the trash icon shows the "Eliminar transaccion" confirmation, and confirming removes the row and updates the account balance.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/history_screen.dart
git commit -m "feat: add edit and delete actions to HistoryScreen"
```
