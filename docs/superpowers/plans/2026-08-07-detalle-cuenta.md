# Detalle de cuenta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping an account (HomeScreen card or AccountsScreen row) opens a detail screen showing current balance, a period-filtered balance-over-time line chart, a Día/Semana/Mes/6-meses selector, and the % variation of the balance across the selected period. Separately, give each bottom-nav icon a distinct color.

**Architecture:** A pure function `accountBalanceForPeriod` (mirrors the existing `calculateAccountBalance` sign logic) computes the chart points, starting balance, ending balance, and % variation for an arbitrary date window. `AccountDetailScreen` is a new leaf screen (same shape as the existing `GoalDetailScreen`) that owns the period-selector state and fetches its own transactions. The account edit dialog already living in `AccountsScreen._openForm` is extracted to a top-level, reusable function so both `HomeScreen` and `AccountsScreen` can open it from the detail screen's edit button.

**Tech Stack:** Flutter, `fl_chart` (already a dependency, used by `ChartsScreen`), `flutter_test`.

## Global Constraints

- Spanish-language UI strings throughout (matches the rest of the app).
- % variation formula: `(saldoFinal - saldoInicio) / saldoInicio * 100`; `null` (rendered as "—") when `saldoInicio == 0` — spec, explicit, to avoid divide-by-zero.
- Transfers count on both sides of an account, same sign convention as `calculateAccountBalance` in `app/lib/logic/balance_calculator.dart`.
- Period boundaries (`hasta` is always "now"): Día = midnight today; Semana = now − 7 days; Mes = day 1 of current month; 6 meses = `DateTime(hoy.year, hoy.month - 6, 1)` (same calculation already used by `monthlyIncomeVsExpense` in `app/lib/logic/chart_aggregator.dart`).
- Chart type: line chart of balance over time, same visual style as "Evolucion del saldo" in `ChartsScreen` (straight lines, no dots, `colorScheme.primary`).
- No widget test for `AccountDetailScreen` — matches this codebase's convention (`GoalDetailScreen`, `PersonDebtsScreen`, etc. have no screen test).
- Editing moves out of "tap the row" and into an edit icon inside the detail screen; `AccountsScreen`'s FAB (create) and toggle-active/delete icons are unaffected.

---

### Task 1: `accountBalanceForPeriod` pure logic

**Files:**
- Create: `app/lib/logic/account_period_summary.dart`
- Test: `app/test/logic/account_period_summary_test.dart`

**Interfaces:**
- Consumes: `Account`, `Transaction`, `TransactionType` (existing models, `app/lib/models/account.dart`, `app/lib/models/transaction.dart`).
- Produces: `class AccountBalancePoint { fecha: DateTime, saldo: double }`, `class AccountPeriodSummary { points: List<AccountBalancePoint>, saldoInicio: double, saldoFinal: double, variacionPorcentual: double? }`, `AccountPeriodSummary accountBalanceForPeriod({required Account account, required List<Transaction> transactions, required DateTime from, required DateTime hasta})`. Task 3 (`AccountDetailScreen`) calls this exact signature.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/logic/account_period_summary_test.dart
import 'package:billetera/logic/account_period_summary.dart';
import 'package:billetera/models/account.dart';
import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = Account(
  id: 'a1',
  userId: 'u',
  nombre: 'Cuenta',
  tipo: 'banco',
  saldoInicial: 1000,
  activo: true,
);

Transaction _t({
  String accountId = 'a1',
  String? accountDestinoId,
  required TransactionType tipo,
  required double monto,
  required DateTime fecha,
}) => Transaction(
  id: 't',
  userId: 'u',
  accountId: accountId,
  accountDestinoId: accountDestinoId,
  categoryId: accountDestinoId == null ? 'c1' : null,
  tipo: tipo,
  monto: monto,
  fecha: fecha,
);

void main() {
  group('accountBalanceForPeriod', () {
    test('saldoInicio accumulates only transactions strictly before "from"', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 500, fecha: DateTime(2026, 1, 1)),
          _t(tipo: TransactionType.gasto, monto: 200, fecha: DateTime(2026, 1, 15)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoInicio, 1300); // 1000 + 500 - 200
      expect(result.points.first.saldo, 1300);
      expect(result.points.length, 1); // only the anchor point, nothing in-window
      expect(result.saldoFinal, 1300);
    });

    test('an incoming transfer to this account adds, regardless of accountId', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(
            accountId: 'other',
            accountDestinoId: 'a1',
            tipo: TransactionType.transferencia,
            monto: 300,
            fecha: DateTime(2026, 2, 10),
          ),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoFinal, 1300); // 1000 + 300
      expect(result.points.length, 2); // anchor + the transfer
    });

    test('an outgoing transfer from this account subtracts', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(
            accountId: 'a1',
            accountDestinoId: 'other',
            tipo: TransactionType.transferencia,
            monto: 300,
            fecha: DateTime(2026, 2, 10),
          ),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoFinal, 700); // 1000 - 300
    });

    test('variacionPorcentual is null when saldoInicio is 0', () {
      const zeroAccount = Account(
        id: 'a2',
        userId: 'u',
        nombre: 'Cuenta cero',
        tipo: 'efectivo',
        saldoInicial: 0,
        activo: true,
      );

      final result = accountBalanceForPeriod(
        account: zeroAccount,
        transactions: [
          _t(
            accountId: 'a2',
            tipo: TransactionType.ingreso,
            monto: 500,
            fecha: DateTime(2026, 2, 10),
          ),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoInicio, 0);
      expect(result.variacionPorcentual, isNull);
    });

    test('variacionPorcentual is computed correctly when saldoInicio is non-zero', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 500, fecha: DateTime(2026, 2, 10)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      // saldoInicio 1000, saldoFinal 1500 -> +50%
      expect(result.variacionPorcentual, 50.0);
    });

    test('boundaries are inclusive: a transaction exactly on "from" or "hasta" counts', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 100, fecha: DateTime(2026, 2, 1)),
          _t(tipo: TransactionType.gasto, monto: 50, fecha: DateTime(2026, 2, 28)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoInicio, 1000); // neither counted yet at the anchor
      expect(result.saldoFinal, 1050); // 1000 + 100 - 50
      expect(result.points.length, 3); // anchor + both transactions
    });

    test('a transaction after "hasta" is ignored entirely', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 999, fecha: DateTime(2026, 3, 5)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoFinal, 1000);
      expect(result.points.length, 1);
    });

    test('transactions belonging to another account are ignored', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(
            accountId: 'other',
            tipo: TransactionType.ingreso,
            monto: 999,
            fecha: DateTime(2026, 2, 10),
          ),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoFinal, 1000);
      expect(result.points.length, 1);
    });

    test('points are in chronological order regardless of input order', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 10, fecha: DateTime(2026, 2, 20)),
          _t(tipo: TransactionType.ingreso, monto: 10, fecha: DateTime(2026, 2, 5)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.points[1].fecha, DateTime(2026, 2, 5));
      expect(result.points[2].fecha, DateTime(2026, 2, 20));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/logic/account_period_summary_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'billetera/logic/account_period_summary.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// app/lib/logic/account_period_summary.dart
import '../models/account.dart';
import '../models/transaction.dart';

class AccountBalancePoint {
  const AccountBalancePoint({required this.fecha, required this.saldo});

  final DateTime fecha;
  final double saldo;
}

class AccountPeriodSummary {
  const AccountPeriodSummary({
    required this.points,
    required this.saldoInicio,
    required this.saldoFinal,
    required this.variacionPorcentual,
  });

  final List<AccountBalancePoint> points;
  final double saldoInicio;
  final double saldoFinal;
  final double? variacionPorcentual;
}

/// Computes the balance-over-time chart data for one account within
/// [from, hasta] (inclusive both ends), plus the % change across that
/// window. Mirrors the sign convention of `calculateAccountBalance` in
/// balance_calculator.dart: this account's own ingreso/gasto/transferencia
/// rows apply directly, and an incoming transferencia from another account
/// (accountDestinoId == account.id) adds instead.
AccountPeriodSummary accountBalanceForPeriod({
  required Account account,
  required List<Transaction> transactions,
  required DateTime from,
  required DateTime hasta,
}) {
  final relevant =
      transactions
          .where(
            (t) =>
                t.accountId == account.id || t.accountDestinoId == account.id,
          )
          .toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));

  var running = account.saldoInicial;

  void apply(Transaction t) {
    switch (t.tipo) {
      case TransactionType.ingreso:
        if (t.accountId == account.id) running += t.monto;
      case TransactionType.gasto:
        if (t.accountId == account.id) running -= t.monto;
      case TransactionType.transferencia:
        if (t.accountId == account.id) running -= t.monto;
        if (t.accountDestinoId == account.id) running += t.monto;
    }
  }

  var i = 0;
  while (i < relevant.length && relevant[i].fecha.isBefore(from)) {
    apply(relevant[i]);
    i++;
  }
  final saldoInicio = running;

  final points = <AccountBalancePoint>[
    AccountBalancePoint(fecha: from, saldo: saldoInicio),
  ];

  while (i < relevant.length && !relevant[i].fecha.isAfter(hasta)) {
    apply(relevant[i]);
    points.add(AccountBalancePoint(fecha: relevant[i].fecha, saldo: running));
    i++;
  }

  final saldoFinal = running;
  final variacionPorcentual = saldoInicio == 0
      ? null
      : (saldoFinal - saldoInicio) / saldoInicio * 100;

  return AccountPeriodSummary(
    points: points,
    saldoInicio: saldoInicio,
    saldoFinal: saldoFinal,
    variacionPorcentual: variacionPorcentual,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/logic/account_period_summary_test.dart`
Expected: `00:00 +9: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/logic/account_period_summary.dart app/test/logic/account_period_summary_test.dart
git commit -m "feat: add accountBalanceForPeriod for account detail chart data"
```

---

### Task 2: Extract `showAccountFormDialog` from `AccountsScreen`

**Files:**
- Modify: `app/lib/screens/accounts_screen.dart`

**Interfaces:**
- Consumes: `Account`, `AccountRepository` (existing).
- Produces: top-level `Future<Account?> showAccountFormDialog(BuildContext context, AccountRepository repo, {Account? account})` — returns the created/updated `Account` on success, `null` if the dialog was cancelled or closed without saving. Task 4 (HomeScreen wiring) and Task 5 (AccountsScreen wiring) both call this exact function; Task 3's `AccountDetailScreen.onEdit` is typed to match its return type.

This is a pure refactor — `AccountsScreen`'s existing behavior (create via FAB, edit via row tap, error handling, reload-after-save) must be identical afterward. No test file exists for `AccountsScreen` today; verify via `flutter analyze` and the full test suite (nothing in it should reference this screen, so an unchanged pass count confirms no regression).

- [ ] **Step 1: Move the dialog body out of `_openForm` into a top-level function**

In `app/lib/screens/accounts_screen.dart`, replace the current `_openForm` method (the one containing the full `showDialog` call) with:

```dart
Future<Account?> showAccountFormDialog(
  BuildContext context,
  AccountRepository repo, {
  Account? account,
}) async {
  final nombreController = TextEditingController(text: account?.nombre ?? '');
  final saldoController = TextEditingController(
    text: account?.saldoInicial.toString() ?? '0',
  );
  var tipo = account?.tipo ?? _tipos.first;
  String? error;
  Account? result;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        insetPadding: kDialogInsetPadding,
        title: Text(account == null ? 'Nueva cuenta' : 'Editar cuenta'),
        content: wideDialogContent([
          TextField(
            controller: nombreController,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: tipo,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: _tipos
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setDialogState(() => tipo = v!),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: saldoController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(labelText: 'Saldo inicial'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          dialogActions(
            onCancel: () => Navigator.pop(context),
            onConfirm: () async {
              final saldo = double.tryParse(saldoController.text) ?? 0;
              try {
                if (account == null) {
                  result = await repo.create(
                    Account(
                      id: '',
                      userId: '',
                      nombre: nombreController.text.trim(),
                      tipo: tipo,
                      saldoInicial: saldo,
                      activo: true,
                    ),
                  );
                } else {
                  result = await repo.update(account.id, {
                    'nombre': nombreController.text.trim(),
                    'tipo': tipo,
                    'saldo_inicial': saldo,
                  });
                }
              } catch (e) {
                setDialogState(
                  () => error =
                      'No se pudo guardar la cuenta. Revisa tu conexion e intenta de nuevo.',
                );
                return;
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ]),
      ),
    ),
  );
  return result;
}
```

Note this is a top-level function (not inside `_AccountsScreenState`) — place it after the `_tipos` constant and before the `AccountsScreen` class, since it uses `_tipos`.

- [ ] **Step 2: Replace the two call sites inside `_AccountsScreenState` with a thin wrapper**

Add this method back inside `_AccountsScreenState` (it's what the FAB's `onPressed: () => _openForm()` and the row's `onTap: () => _openForm(account: a)` still call — Task 5 changes the row's `onTap` separately, so leave both call sites as-is for this task):

```dart
  Future<void> _openForm({Account? account}) async {
    await showAccountFormDialog(context, _repo, account: account);
    if (mounted) _reload();
  }
```

- [ ] **Step 3: Verify it compiles and the full suite still passes**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` then `All tests passed!` (same count as before this task — no test references `AccountsScreen`).

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/accounts_screen.dart
git commit -m "refactor: extract showAccountFormDialog so it can be reused outside AccountsScreen"
```

---

### Task 3: `AccountDetailScreen`

**Files:**
- Create: `app/lib/screens/account_detail_screen.dart`

**Interfaces:**
- Consumes: `Account`, `Transaction` (existing models), `TransactionRepository.fetchAll()` (existing, no args = no filter), `calculateAccountBalance` (`app/lib/logic/balance_calculator.dart`), `accountVisual` (`app/lib/core/colors.dart`), `accountBalanceForPeriod`/`AccountPeriodSummary` (Task 1).
- Produces: `class AccountDetailScreen extends StatefulWidget` with constructor `{required Account account, required Future<Account?> Function() onEdit}`. Task 4 and Task 5 both construct this exact widget and pass `onEdit` as `() => showAccountFormDialog(context, <repo>, account: a)` (Task 2's function).

No test — matches this codebase's convention for detail/leaf screens (`GoalDetailScreen`, `PersonDebtsScreen`).

- [ ] **Step 1: Write the screen**

```dart
// app/lib/screens/account_detail_screen.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../logic/account_period_summary.dart';
import '../logic/balance_calculator.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../repositories/transaction_repository.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤ #,##0',
);

enum _Periodo { dia, semana, mes, seisMeses }

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({
    super.key,
    required this.account,
    required this.onEdit,
  });

  final Account account;
  final Future<Account?> Function() onEdit;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  final _transactionRepo = TransactionRepository(Supabase.instance.client);
  late Account _account;
  late Future<List<Transaction>> _future;
  _Periodo _periodo = _Periodo.mes;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _future = _transactionRepo.fetchAll();
  }

  DateTime _from(DateTime hoy) => switch (_periodo) {
    _Periodo.dia => DateTime(hoy.year, hoy.month, hoy.day),
    _Periodo.semana => hoy.subtract(const Duration(days: 7)),
    _Periodo.mes => DateTime(hoy.year, hoy.month, 1),
    _Periodo.seisMeses => DateTime(hoy.year, hoy.month - 6, 1),
  };

  Future<void> _edit() async {
    final updated = await widget.onEdit();
    if (updated != null && mounted) setState(() => _account = updated);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_account.nombre),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: _edit,
          ),
        ],
      ),
      body: FutureBuilder<List<Transaction>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final transactions = snapshot.data!;
          final saldoActual = calculateAccountBalance(
            saldoInicial: _account.saldoInicial,
            accountId: _account.id,
            transactions: transactions,
          );
          final visual = accountVisual(_account.tipo, scheme.primary);
          final hoy = DateTime.now();
          final resumen = accountBalanceForPeriod(
            account: _account,
            transactions: transactions,
            from: _from(hoy),
            hasta: hoy,
          );
          final variacion = resumen.variacionPorcentual;
          final variacionColor = variacion == null
              ? scheme.onSurfaceVariant
              : variacion >= 0
              ? AppColors.ingreso
              : AppColors.gasto;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: visual.color.withValues(alpha: 0.16),
                        child: Icon(visual.icon, color: visual.color),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saldo actual',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            _currency.format(saldoActual),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<_Periodo>(
                segments: const [
                  ButtonSegment(value: _Periodo.dia, label: Text('Dia')),
                  ButtonSegment(value: _Periodo.semana, label: Text('Semana')),
                  ButtonSegment(value: _Periodo.mes, label: Text('Mes')),
                  ButtonSegment(
                    value: _Periodo.seisMeses,
                    label: Text('6 meses'),
                  ),
                ],
                selected: {_periodo},
                onSelectionChanged: (s) => setState(() => _periodo = s.first),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Variacion del periodo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    variacion == null
                        ? '—'
                        : '${variacion >= 0 ? '+' : ''}${variacion.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: variacionColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: resumen.points.length <= 1
                      ? const SizedBox(
                          height: 220,
                          child: Center(
                            child: Text('Sin movimientos en este periodo'),
                          ),
                        )
                      : SizedBox(
                          height: 220,
                          child: LineChart(
                            LineChartData(
                              lineBarsData: [
                                LineChartBarData(
                                  spots: [
                                    for (final (i, p) in resumen.points.indexed)
                                      FlSpot(i.toDouble(), p.saldo),
                                  ],
                                  isCurved: false,
                                  color: scheme.primary,
                                  dotData: const FlDotData(show: false),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd app && flutter analyze lib/screens/account_detail_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/screens/account_detail_screen.dart
git commit -m "feat: add AccountDetailScreen with period selector, balance chart, and variation"
```

---

### Task 4: Wire account taps in `HomeScreen`

**Files:**
- Modify: `app/lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: `AccountDetailScreen` (Task 3), `showAccountFormDialog` (Task 2, exported from `accounts_screen.dart`).
- Produces: nothing consumed by later tasks.

No new test — matches convention (no `home_screen_test.dart` exists; this file's only prior tests were exercised indirectly, none exist here either).

- [ ] **Step 1: Add the import**

In `app/lib/screens/home_screen.dart`, add:

```dart
import 'account_detail_screen.dart';
import 'accounts_screen.dart' show showAccountFormDialog;
```

- [ ] **Step 2: Wrap each account card in an `InkWell` that pushes the detail screen**

In the `build()` method's `Wrap`, the entire `for (final a in accounts) Builder(builder: (context) { ... })` block currently reads:

```dart
                    for (final a in accounts)
                      Builder(
                        builder: (context) {
                          final balance = calculateAccountBalance(
                            saldoInicial: a.saldoInicial,
                            accountId: a.id,
                            transactions: transactions,
                          );
                          final visual = accountVisual(a.tipo, scheme.primary);
                          return SizedBox(
                            width:
                                (MediaQuery.of(context).size.width - 16 * 2 - 12) /
                                2,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          visual.icon,
                                          size: 22,
                                          color: visual.color,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            a.nombre,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _currency.format(balance),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
```

Replace it in full with:

```dart
                    for (final a in accounts)
                      Builder(
                        builder: (context) {
                          final balance = calculateAccountBalance(
                            saldoInicial: a.saldoInicial,
                            accountId: a.id,
                            transactions: transactions,
                          );
                          final visual = accountVisual(a.tipo, scheme.primary);
                          return SizedBox(
                            width:
                                (MediaQuery.of(context).size.width - 16 * 2 - 12) /
                                2,
                            child: Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AccountDetailScreen(
                                        account: a,
                                        onEdit: () => showAccountFormDialog(
                                          context,
                                          _accountRepo,
                                          account: a,
                                        ),
                                      ),
                                    ),
                                  );
                                  if (mounted) _reload();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            visual.icon,
                                            size: 22,
                                            color: visual.color,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              a.nombre,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _currency.format(balance),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
```

`16` matches `CardThemeData.shape`'s `BorderRadius.circular(16)` in `app/lib/core/theme.dart:20`, so the ripple stays clipped to the card's rounded corners.

- [ ] **Step 3: Run analyze and the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` then `All tests passed!` (unchanged count).

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/home_screen.dart
git commit -m "feat: open AccountDetailScreen when tapping an account card on Home"
```

---

### Task 5: Wire account taps in `AccountsScreen`

**Files:**
- Modify: `app/lib/screens/accounts_screen.dart`

**Interfaces:**
- Consumes: `AccountDetailScreen` (Task 3), `showAccountFormDialog` (Task 2, same file).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the import**

In `app/lib/screens/accounts_screen.dart`, add:

```dart
import 'account_detail_screen.dart';
```

- [ ] **Step 2: Change the row's `onTap`**

Find the `ListTile`'s `onTap: () => _openForm(account: a),` (at the end of the `ListTile` inside the `Builder` in `build()`) and replace it with:

```dart
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AccountDetailScreen(
                                    account: a,
                                    onEdit: () => showAccountFormDialog(
                                      context,
                                      _repo,
                                      account: a,
                                    ),
                                  ),
                                ),
                              );
                              if (mounted) _reload();
                            },
```

- [ ] **Step 3: Run analyze and the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` then `All tests passed!` (unchanged count).

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/accounts_screen.dart
git commit -m "feat: open AccountDetailScreen when tapping an account row in Cuentas"
```

---

### Task 6: Colored bottom-nav icons

**Files:**
- Modify: `app/lib/screens/app_shell.dart`

**Interfaces:**
- Consumes: `AppColors.chartPalette` (existing, `app/lib/core/colors.dart` — an 8-entry `List<Color>`).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the import and color each destination's icon**

In `app/lib/screens/app_shell.dart`, add:

```dart
import '../core/colors.dart';
```

Replace the `destinations:` list:

```dart
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Cuentas'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Presupuestos'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Graficas'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Deudas'),
        ],
```

The list drops its outer `const` (the individual `Icon`/`NavigationDestination` widgets are no longer const either) — indexing a `static const List<Color>` still works fine at runtime, it just isn't being const-folded, which doesn't matter here:

```dart
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home, color: AppColors.chartPalette[0]),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.account_balance_wallet,
              color: AppColors.chartPalette[1],
            ),
            label: 'Cuentas',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.pie_chart_outline,
              color: AppColors.chartPalette[2],
            ),
            label: 'Presupuestos',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart, color: AppColors.chartPalette[3]),
            label: 'Graficas',
          ),
          NavigationDestination(
            icon: Icon(Icons.history, color: AppColors.chartPalette[4]),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline, color: AppColors.chartPalette[5]),
            label: 'Deudas',
          ),
        ],
```

- [ ] **Step 2: Run analyze and the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` then `All tests passed!` (unchanged count).

- [ ] **Step 3: Commit**

```bash
git add app/lib/screens/app_shell.dart
git commit -m "feat: give each bottom-nav icon a distinct color"
```

---

### Task 7: Rebuild and manual smoke test

**Files:** none (build + manual verification only).

**Interfaces:** none — terminal task.

- [ ] **Step 1: Rebuild**

Run: `cd app && flutter build apk --debug --dart-define-from-file=env.json && cp build/app/outputs/flutter-apk/app-debug.apk dist/billetera-debug.apk`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 2: Manual smoke test (emulator or device)**

1. On Home, tap an account card. Confirm the detail screen opens showing the correct saldo, and the bottom nav icons are now each a different color.
2. Change the period selector through all four options (Día, Semana, Mes, 6 meses) — confirm the chart and % variation update each time, and neither crashes when a period has no movements ("Sin movimientos en este periodo").
3. Tap the edit icon in the detail screen's AppBar, change the account's nombre, save — confirm the AppBar title and header update immediately without leaving the screen.
4. Go back to Home — confirm the account card reflects the renamed account.
5. Go to Cuentas, tap a row — confirm it opens the detail screen (not the old edit dialog). Edit from there, go back — confirm the Cuentas list reflects the change.

- [ ] **Step 3: Commit (if the smoke test surfaced fixes)**

Only if Step 2 required code changes — otherwise this task ends at Step 2 with no commit.
