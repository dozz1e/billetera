# Metas de ahorro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar metas de ahorro vinculadas a una cuenta existente, con progreso calculado (no guardado) y transición automática a "alcanzado", dentro de la pantalla Presupuestos como un tab nuevo.

**Architecture:** Tabla nueva `goals` en Supabase (RLS por `user_id`, igual que el resto). Modelo `Goal` + `GoalRepository` siguiendo el patrón exacto de `Budget`/`BudgetRepository`. El "ahorrado" de una meta se calcula en runtime reusando `calculateAccountBalance()` (ya existe, sin cambios) contra la cuenta vinculada — no se guarda en la base. Una función pura `nextGoalState()` decide si una meta pasa a "alcanzado"; se llama al cargar la pantalla y, si cambia, se persiste con un `UPDATE`. `BudgetsScreen` pasa a tener un `TabBar` de 2 tabs (Presupuestos | Metas); `GoalsScreen` (nueva) tiene su propio `TabBar` anidado de 3 tabs (Activo | Pausado | Alcanzado). Tap en una meta abre `GoalDetailScreen` con el detalle y el botón pausar/reactivar.

**Tech Stack:** Flutter/Dart, Supabase (Postgres + RLS), `intl` para formato de moneda y fecha (ya en uso), `showDatePicker` (Flutter built-in, primer uso en este proyecto).

## Global Constraints

- Tabla `goals`: `id uuid pk`, `user_id uuid fk`, `nombre text`, `account_id uuid fk -> accounts`, `monto_objetivo numeric`, `fecha_objetivo date`, `estado text default 'activo' check (estado in ('activo','pausado','alcanzado'))`, `created_at timestamptz`. RLS: `auth.uid() = user_id`, igual patrón que `accounts`/`categories`/`transactions`/`budgets`.
- El "ahorrado" de una meta **nunca se guarda** — se calcula con `calculateAccountBalance()` (`lib/logic/balance_calculator.dart`, sin modificar).
- Transición a `alcanzado`: automática cuando `ahorrado >= monto_objetivo` y el estado actual no es `pausado`, y se **persiste** (no se recalcula en cada render). `pausado` es un toggle manual. Ninguna meta "alcanzado" vuelve a `activo` automáticamente aunque el saldo baje después.
- Navegación: `BudgetsScreen` (`lib/screens/budgets_screen.dart`) pasa a tener `TabBar` "Presupuestos" | "Metas" — la pestaña Presupuestos existente no cambia de comportamiento, solo se mueve dentro del `TabBarView`. `GoalsScreen` tiene su propio `TabBar` anidado Activo/Pausado/Alcanzado.
- Sin selector de ícono — ícono fijo (`Icons.flag`), mismo criterio que categorías hoy.
- Testing: solo `nextGoalState()` lleva unit test (función pura, TDD). Sin test de modelo nuevo (sigue el patrón mayoritario: `Account`, `Category` y `Budget` no tienen test dedicado; solo `Transaction` lo tiene). Sin widget test nuevo (sigue el patrón de `budgets_screen.dart`/`categories_screen.dart`, que tampoco tienen).
- Estilo de diálogos: usar `DropdownButton<String>` (no `DropdownButtonFormField`) dentro de diálogos `AlertDialog`, igual que `accounts_screen.dart` y `budgets_screen.dart` — `DropdownButtonFormField` se usa solo en pantallas completas como `new_transaction_screen.dart`.
- Manejo de errores en acciones async: siempre `try/catch` con mensaje de error inline (rojo) + `if (mounted)`/`if (context.mounted)` antes de `setState`/`Navigator.pop` — patrón ya establecido en todo el proyecto (ver `accounts_screen.dart`, `budgets_screen.dart`).

---

### Task 1: Migración de base de datos — tabla `goals`

**Files:**
- Create: `supabase/migrations/0002_goals.sql`

**Interfaces:**
- Produces: tabla `goals` con las columnas exactas de Global Constraints, accesible vía `_client.from('goals')` en Dart. Task 3 (`GoalRepository`) depende de estos nombres de columna exactos.

- [ ] **Step 1: Crear el archivo de migración**

Crear `supabase/migrations/0002_goals.sql`:

```sql
create table goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null,
  account_id uuid not null references accounts(id) on delete cascade,
  monto_objetivo numeric not null check (monto_objetivo > 0),
  fecha_objetivo date not null,
  estado text not null default 'activo' check (estado in ('activo', 'pausado', 'alcanzado')),
  created_at timestamptz not null default now()
);

create index goals_user_estado_idx on goals(user_id, estado);

alter table goals enable row level security;

create policy "goals_owner" on goals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- [ ] **Step 2: Aplicar la migración**

**Nota para quien ejecute este plan:** este paso requiere credenciales del proyecto Supabase (contraseña de base de datos o token de servicio). Por precedente del proyecto (ver `.superpowers/sdd/progress.md`, Task 1 del plan original), este paso lo ejecuta el controller directamente — nunca se le pasan credenciales de base de datos a un subagente.

Aplicar con Supabase CLI (ya vinculado al proyecto en sesiones anteriores):
```bash
supabase db push
```

- [ ] **Step 3: Verificar**

Verificar que la tabla existe y RLS está activo con una llamada REST autenticada, o con:
```bash
supabase db diff
```
Expected: sin diferencias pendientes (la migración ya aplicada coincide con el archivo local).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0002_goals.sql
git commit -m "feat: add goals table with RLS"
```

---

### Task 2: Modelo `Goal`

**Files:**
- Create: `app/lib/models/goal.dart`

**Interfaces:**
- Produces: clase `Goal` con constructor `Goal({required id, required userId, required nombre, required accountId, required montoObjetivo, required fechaObjetivo, required estado})`, `Goal.fromJson(Map<String, dynamic>)`, y método `toInsertJson()` que devuelve `{'nombre', 'account_id', 'monto_objetivo', 'fecha_objetivo'}` (sin `id`, `user_id` ni `estado` — igual patrón que `Budget.toInsertJson()`). Tasks 3, 5 y 6 consumen esta clase.

- [ ] **Step 1: Crear `app/lib/models/goal.dart`**

```dart
class Goal {
  const Goal({
    required this.id,
    required this.userId,
    required this.nombre,
    required this.accountId,
    required this.montoObjetivo,
    required this.fechaObjetivo,
    required this.estado,
  });

  final String id;
  final String userId;
  final String nombre;
  final String accountId;
  final double montoObjetivo;
  final DateTime fechaObjetivo;
  final String estado; // 'activo' | 'pausado' | 'alcanzado'

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        nombre: json['nombre'] as String,
        accountId: json['account_id'] as String,
        montoObjetivo: (json['monto_objetivo'] as num).toDouble(),
        fechaObjetivo: DateTime.parse(json['fecha_objetivo'] as String),
        estado: json['estado'] as String,
      );

  Map<String, dynamic> toInsertJson() => {
        'nombre': nombre,
        'account_id': accountId,
        'monto_objetivo': montoObjetivo,
        'fecha_objetivo': fechaObjetivo.toIso8601String().split('T').first,
      };
}
```

- [ ] **Step 2: Verificar que compila**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/models/goal.dart
git commit -m "feat: add Goal model"
```

---

### Task 3: `GoalRepository`

**Files:**
- Create: `app/lib/repositories/goal_repository.dart`

**Interfaces:**
- Consumes: `Goal` (Task 2).
- Produces: `GoalRepository(SupabaseClient)` con `Future<List<Goal>> fetchAll()`, `Future<Goal> create(Goal goal)`, `Future<Goal> updateEstado(String id, String estado)`. Tasks 5 y 6 consumen esta clase.

- [ ] **Step 1: Crear `app/lib/repositories/goal_repository.dart`**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/goal.dart';

class GoalRepository {
  GoalRepository(this._client);

  final SupabaseClient _client;

  Future<List<Goal>> fetchAll() async {
    final rows = await _client.from('goals').select().order('created_at');
    return (rows as List)
        .map((r) => Goal.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Goal> create(Goal goal) async {
    final row = await _client
        .from('goals')
        .insert({
          ...goal.toInsertJson(),
          'user_id': _client.auth.currentUser!.id,
        })
        .select()
        .single();
    return Goal.fromJson(row);
  }

  Future<Goal> updateEstado(String id, String estado) async {
    final row = await _client
        .from('goals')
        .update({'estado': estado})
        .eq('id', id)
        .select()
        .single();
    return Goal.fromJson(row);
  }
}
```

- [ ] **Step 2: Verificar que compila**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/repositories/goal_repository.dart
git commit -m "feat: add GoalRepository"
```

---

### Task 4: Lógica pura `nextGoalState`

**Files:**
- Create: `app/lib/logic/goal_state.dart`
- Test: `app/test/logic/goal_state_test.dart`

**Interfaces:**
- Produces: `String nextGoalState({required double ahorrado, required double montoObjetivo, required String estadoActual})`. Task 5 la consume con esta firma exacta.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/logic/goal_state_test.dart`:

```dart
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
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `cd app && flutter test test/logic/goal_state_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'billetera' in 'package:billetera/logic/goal_state.dart'` (el archivo todavía no existe).

- [ ] **Step 3: Implementar `app/lib/logic/goal_state.dart`**

```dart
String nextGoalState({
  required double ahorrado,
  required double montoObjetivo,
  required String estadoActual,
}) {
  if (estadoActual == 'pausado' || estadoActual == 'alcanzado') return estadoActual;
  if (ahorrado >= montoObjetivo) return 'alcanzado';
  return estadoActual;
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `cd app && flutter test test/logic/goal_state_test.dart`
Expected: PASS — 4 tests OK.

- [ ] **Step 5: Commit**

```bash
git add app/lib/logic/goal_state.dart app/test/logic/goal_state_test.dart
git commit -m "feat: add nextGoalState transition logic"
```

---

### Task 5: `GoalsScreen`

**Files:**
- Create: `app/lib/screens/goals_screen.dart`

**Interfaces:**
- Consumes: `Goal`, `GoalRepository` (Task 3), `nextGoalState` (Task 4), `Account`/`AccountRepository` (ya existen), `TransactionRepository`/`calculateAccountBalance` (ya existen), `GoalDetailScreen` (Task 6 — este archivo importa `goal_detail_screen.dart`, que debe existir antes de compilar este task; si se ejecuta Task 5 antes que Task 6, crear un `GoalDetailScreen` mínimo primero o ejecutar Task 6 inmediatamente después sin commit intermedio roto — ver nota en Task 6).
- Produces: widget `GoalsScreen` (sin parámetros), usable como `const GoalsScreen()`. Task 7 lo consume.

**Nota de orden:** este task importa `goal_detail_screen.dart` (Task 6). Ejecutar Task 6 inmediatamente a continuación de este task, antes de dar por cerrado el ciclo de review de Task 5 si se requiere que cada task compile de forma aislada — o fusionar la revisión de Tasks 5 y 6 en una sola pasada. Cualquiera de las dos formas es válida; no dejar Task 5 mergeado sin Task 6 en el mismo lote de trabajo.

- [ ] **Step 1: Crear `app/lib/screens/goals_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/balance_calculator.dart';
import '../logic/goal_state.dart';
import '../models/account.dart';
import '../models/goal.dart';
import '../repositories/account_repository.dart';
import '../repositories/goal_repository.dart';
import '../repositories/transaction_repository.dart';
import 'goal_detail_screen.dart';

final _currency = NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0);
final _date = DateFormat('dd/MM/yyyy');

class GoalWithProgress {
  const GoalWithProgress({required this.goal, required this.ahorrado, required this.account});

  final Goal goal;
  final double ahorrado;
  final Account account;
}

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _goalRepo = GoalRepository(Supabase.instance.client);
  final _accountRepo = AccountRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);

  List<Account> _accounts = [];
  late Future<List<GoalWithProgress>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<GoalWithProgress>> _load() async {
    final goals = await _goalRepo.fetchAll();
    final accounts = await _accountRepo.fetchAll();
    final transactions = await _transactionRepo.fetchAll();
    _accounts = accounts;

    final result = <GoalWithProgress>[];
    for (final goal in goals) {
      final account = accounts.firstWhere(
        (a) => a.id == goal.accountId,
        orElse: () => const Account(id: '', userId: '', nombre: 'Cuenta', tipo: 'efectivo', saldoInicial: 0, activo: false),
      );
      final ahorrado = calculateAccountBalance(
        saldoInicial: account.saldoInicial,
        accountId: goal.accountId,
        transactions: transactions,
      );
      final nuevoEstado = nextGoalState(ahorrado: ahorrado, montoObjetivo: goal.montoObjetivo, estadoActual: goal.estado);

      var goalActual = goal;
      if (nuevoEstado != goal.estado) {
        goalActual = await _goalRepo.updateEstado(goal.id, nuevoEstado);
      }
      result.add(GoalWithProgress(goal: goalActual, ahorrado: ahorrado, account: account));
    }
    return result;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openForm() async {
    final cuentasActivas = _accounts.where((a) => a.activo).toList();
    if (cuentasActivas.isEmpty) return;

    final nombreController = TextEditingController();
    final montoController = TextEditingController();
    var accountId = cuentasActivas.first.id;
    var fecha = DateTime.now().add(const Duration(days: 30));
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva meta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombreController, decoration: const InputDecoration(labelText: 'Nombre')),
              DropdownButton<String>(
                value: accountId,
                items: cuentasActivas.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))).toList(),
                onChanged: (v) => setDialogState(() => accountId = v!),
              ),
              TextField(
                controller: montoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto objetivo'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Fecha objetivo: ${_date.format(fecha)}'),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fecha,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setDialogState(() => fecha = picked);
                    },
                    child: const Text('Cambiar'),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final monto = double.tryParse(montoController.text) ?? 0;
                try {
                  await _goalRepo.create(Goal(
                    id: '',
                    userId: '',
                    nombre: nombreController.text.trim(),
                    accountId: accountId,
                    montoObjetivo: monto,
                    fechaObjetivo: fecha,
                    estado: 'activo',
                  ));
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) _reload();
                } catch (e) {
                  setDialogState(() => error = 'No se pudo guardar la meta. Revisa tu conexion e intenta de nuevo.');
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirDetalle(GoalWithProgress gp) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GoalDetailScreen(
          goal: gp.goal,
          ahorrado: gp.ahorrado,
          cuentaNombre: gp.account.nombre,
          onTogglePausado: () async {
            final nuevoEstado = gp.goal.estado == 'pausado' ? 'activo' : 'pausado';
            await _goalRepo.updateEstado(gp.goal.id, nuevoEstado);
          },
        ),
      ),
    );
    if (mounted) _reload();
  }

  Widget _lista(List<GoalWithProgress> metas, String estado) {
    final filtradas = metas.where((m) => m.goal.estado == estado).toList();
    if (filtradas.isEmpty) return const Center(child: Text('Sin metas en este estado'));
    return ListView.builder(
      itemCount: filtradas.length,
      itemBuilder: (context, i) {
        final gp = filtradas[i];
        final porcentaje = gp.goal.montoObjetivo <= 0 ? 0.0 : gp.ahorrado / gp.goal.montoObjetivo;
        return ListTile(
          leading: const Icon(Icons.flag),
          title: Text(gp.goal.nombre),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: porcentaje.clamp(0, 1)),
              Text('${_currency.format(gp.ahorrado)} / ${_currency.format(gp.goal.montoObjetivo)}'),
            ],
          ),
          onTap: () => _abrirDetalle(gp),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<GoalWithProgress>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final metas = snapshot.data!;
          return DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  tabs: [Tab(text: 'Activo'), Tab(text: 'Pausado'), Tab(text: 'Alcanzado')],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _lista(metas, 'activo'),
                      _lista(metas, 'pausado'),
                      _lista(metas, 'alcanzado'),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _openForm, child: const Icon(Icons.add)),
    );
  }
}
```

- [ ] **Step 2: No compilar todavía de forma aislada**

Este archivo importa `goal_detail_screen.dart`, que se crea en Task 6. Continuar directamente con Task 6 antes de correr `flutter analyze`.

---

### Task 6: `GoalDetailScreen`

**Files:**
- Create: `app/lib/screens/goal_detail_screen.dart`

**Interfaces:**
- Consumes: `Goal` (Task 2).
- Produces: widget `GoalDetailScreen({required Goal goal, required double ahorrado, required String cuentaNombre, required Future<void> Function() onTogglePausado})`. Consumido por `GoalsScreen` (Task 5) con esta firma exacta.

- [ ] **Step 1: Crear `app/lib/screens/goal_detail_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/goal.dart';

final _currency = NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0);
final _date = DateFormat('dd/MM/yyyy');

class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({
    super.key,
    required this.goal,
    required this.ahorrado,
    required this.cuentaNombre,
    required this.onTogglePausado,
  });

  final Goal goal;
  final double ahorrado;
  final String cuentaNombre;
  final Future<void> Function() onTogglePausado;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _toggle() async {
    setState(() => _loading = true);
    try {
      await widget.onTogglePausado();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo actualizar la meta. Revisa tu conexion e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final porcentaje = goal.montoObjetivo <= 0 ? 0.0 : widget.ahorrado / goal.montoObjetivo;
    final pausada = goal.estado == 'pausado';
    final alcanzada = goal.estado == 'alcanzado';

    return Scaffold(
      appBar: AppBar(title: Text(goal.nombre)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cuenta: ${widget.cuentaNombre}'),
            const SizedBox(height: 8),
            Text('Fecha objetivo: ${_date.format(goal.fechaObjetivo)}'),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: porcentaje.clamp(0, 1), minHeight: 12),
            const SizedBox(height: 12),
            Text('Ahorrado: ${_currency.format(widget.ahorrado)}'),
            Text('Objetivo: ${_currency.format(goal.montoObjetivo)}'),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (!alcanzada)
              FilledButton(
                onPressed: _loading ? null : _toggle,
                child: Text(pausada ? 'Reactivar' : 'Pausar'),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verificar que Tasks 5 y 6 compilan juntos**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit (Tasks 5 y 6 juntos, se necesitan mutuamente para compilar)**

```bash
git add app/lib/screens/goals_screen.dart app/lib/screens/goal_detail_screen.dart
git commit -m "feat: add GoalsScreen and GoalDetailScreen"
```

---

### Task 7: Enganchar Metas en `BudgetsScreen`

**Files:**
- Modify: `app/lib/screens/budgets_screen.dart`

**Interfaces:**
- Consumes: `GoalsScreen` (Tasks 5+6).

- [ ] **Step 1: Agregar el import**

En `app/lib/screens/budgets_screen.dart`, agregar después de `import '../repositories/transaction_repository.dart';`:

```dart
import 'goals_screen.dart';
```

- [ ] **Step 2: Reemplazar el método `build()`**

Cambiar el `build()` actual (desde `@override\n  Widget build(BuildContext context) {` hasta el `}` que lo cierra, incluyendo todo el `Scaffold` con `appBar`, `floatingActionButton` y `body: FutureBuilder<List<BudgetProgress>>(...)`) por:

```dart
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Presupuestos'),
          bottom: const TabBar(tabs: [Tab(text: 'Presupuestos'), Tab(text: 'Metas')]),
        ),
        body: TabBarView(
          children: [
            Scaffold(
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
                        orElse: () => const Category(id: '', userId: '', nombre: 'Categoria', tipo: 'gasto', icono: '', predefinida: false),
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
            ),
            const GoalsScreen(),
          ],
        ),
      ),
    );
  }
```

Nota: el cuerpo del `FutureBuilder` es el mismo que ya existía — solo se movió dentro de un `Scaffold` anidado (para que Presupuestos y Metas tengan cada uno su propio FAB) y ese `Scaffold` anidado quedó dentro de un `TabBarView` dentro de un `Scaffold`/`DefaultTabController` externo nuevo. También se agregó `const` al `orElse` de `Category(...)` (mejora menor, coherente con que ese objeto es inmutable — no altera comportamiento).

- [ ] **Step 3: Verificar**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: todos los tests existentes en PASS, 0 fallos nuevos (mismo baseline que antes de este task).

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/budgets_screen.dart
git commit -m "feat: add Metas tab to BudgetsScreen"
```

---

### Task 8: QA manual en emulador

**Files:** ninguno (verificación funcional, sin cambios de código salvo que el QA encuentre un bug puntual).

**Interfaces:** ninguna — task terminal, no produce nada para tasks siguientes.

**Nota:** este task requiere credenciales de login del usuario (Supabase Auth) — igual que Task 3 del plan de tema oscuro, lo ejecuta el controller directamente, no un subagente.

- [ ] **Step 1: Compilar e instalar el debug APK**

Run (desde `app/`):
```bash
flutter build apk --debug --dart-define-from-file=env.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
Si no hay emulador corriendo, levantarlo primero (ver Task 3 del plan de tema oscuro para el comando exacto).

- [ ] **Step 2: Verificar que existe al menos una cuenta con saldo conocido**

Login en la app. Ir a Cuentas. Si no hay ninguna cuenta con transacciones registradas, crear una cuenta "Ahorro test" con saldo inicial `100000` y registrar una transacción de ingreso de `50000` contra ella (saldo esperado: `150000`).

- [ ] **Step 3: Crear una meta por debajo del saldo actual**

Ir a Presupuestos → tab Metas. Crear meta "Test bajo objetivo": cuenta "Ahorro test", monto objetivo `200000`, fecha objetivo cualquiera futura. Guardar.

Verificar: aparece en el tab Activo, con progreso `150000 / 200000` (75%), barra de progreso a 3/4.

- [ ] **Step 4: Crear una meta por debajo del saldo, para forzar "alcanzado"**

Crear meta "Test alcanzado": misma cuenta "Ahorro test", monto objetivo `100000` (menor al saldo actual de 150000). Guardar.

Cambiar de tab (salir de Metas y volver, o cambiar a Presupuestos y volver a Metas) para forzar un reload de `_load()`.

Verificar: "Test alcanzado" ya no está en el tab Activo — aparece directamente en el tab Alcanzado (la transición ocurrió al cargar).

- [ ] **Step 5: Probar pausar/reactivar**

Tap en "Test bajo objetivo" (tab Activo) para abrir el detalle. Tap en "Pausar". Verificar que vuelve a la lista y la meta ahora aparece en el tab Pausado.

Volver a abrir el detalle desde el tab Pausado, tap en "Reactivar". Verificar que vuelve a aparecer en el tab Activo.

- [ ] **Step 6: Capturar y revisar contraste en tema oscuro**

```bash
adb exec-out screencap -p > /tmp/qa_metas_lista.png
```
Abrir el detalle de una meta y capturar:
```bash
adb exec-out screencap -p > /tmp/qa_metas_detalle.png
```
Revisar ambas capturas (leer con Read): texto legible sobre fondo oscuro, barra de progreso visible, tabs (Presupuestos/Metas y Activo/Pausado/Alcanzado) legibles y con indicador de selección visible.

- [ ] **Step 7: Reportar resultado**

Si todo lo anterior se cumple: QA pasa, no hay commit adicional (Tasks 1-7 ya cerraron el cambio de código).

Si algo falla (cálculo de progreso incorrecto, transición de estado que no ocurre, contraste roto): anotar el paso exacto y el comportamiento observado, y decidir si amerita reabrir una task anterior o crear un fix puntual.

---

## Self-Review

**Cobertura del spec:** meta vinculada a cuenta existente, ahorrado calculado vía `calculateAccountBalance` (Task 5) ✓. Estados activo/pausado/alcanzado con transición automática persistida a alcanzado y toggle manual de pausado, sin des-alcanzar automático (Task 4 + Task 5) ✓. Tabla `goals` con columnas y RLS exactas del spec (Task 1) ✓. Navegación como sub-tab de Presupuestos con tabs anidados Activo/Pausado/Alcanzado (Tasks 5 y 7) ✓. Formulario con nombre/cuenta/monto/fecha, sin selector de ícono (Task 5) ✓. Detalle de meta con progreso y pausar/reactivar (Task 6) ✓. Testing: solo `nextGoalState` con unit test, sin test de modelo ni widget test nuevo (Task 4) ✓.

**Placeholders:** ninguno — todos los steps tienen código o comandos completos.

**Consistencia de tipos:** `Goal` (Task 2) se consume igual en `GoalRepository` (Task 3), `GoalsScreen` (Task 5) y `GoalDetailScreen` (Task 6) — mismos nombres de campo (`accountId`, `montoObjetivo`, `fechaObjetivo`, `estado`) en los tres. `nextGoalState({required double ahorrado, required double montoObjetivo, required String estadoActual})` (Task 4) se llama en `GoalsScreen._load()` (Task 5) con los mismos nombres de parámetro. `GoalDetailScreen` (Task 6) se instancia en `GoalsScreen._abrirDetalle()` (Task 5) con los 4 parámetros exactos que `GoalDetailScreen` declara como `required`.
