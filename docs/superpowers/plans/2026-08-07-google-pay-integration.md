# Integración Google Pay (registro semi-automático vía notificaciones) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App escucha notificaciones de Google Wallet en Android, arma una cola local de "registros pendientes" (monto + comercio + categoría sugerida), y el usuario los inserta o descarta como transacciones reales desde una card en Historial.

**Architecture:** Lógica pura (parser de notificación, matcher de categoría) vive en `lib/logic/`, testeable sin Flutter/Hive/plugin. Un adaptador (`GooglePayNotificationSource`) aísla la dependencia del plugin nativo detrás de una interfaz — el orquestador (`GooglePayListenerService`) y sus tests usan un fake; solo la implementación concreta del plugin queda fuera de test automatizado (no practicable en CI). La cola pendiente vive en un Hive box local (`google_pay_pending`), nunca en Supabase — un registro solo se vuelve un `transactions` row real cuando el usuario lo inserta.

**Tech Stack:** Flutter, Hive (`hive`/`hive_flutter`, ya en el proyecto), plugin `notification_listener_service` (nuevo), Supabase (`supabase_flutter`, ya en el proyecto).

## Global Constraints

- Solo se procesan notificaciones con `packageName == 'com.google.android.apps.walletnfcrel'` (Google Wallet) — ninguna otra app.
- La cola pendiente (`PendingGooglePayRecord`) es 100% local (Hive), nunca se escribe en Supabase. Solo al insertarse se crea un `transactions` row normal.
- Sin cambios al esquema de Supabase — no hay migración nueva en este plan.
- Cuenta destino de un registro insertado = la "cuenta por defecto Google Pay" configurada por el usuario (guardada local), no una cuenta elegida notificación por notificación.
- Categoría sin match por palabra clave cae en la categoría predefinida `'Otros gastos'` (`tipo = 'gasto'`) — no existe "Gasto desconocido" como categoría real en este esquema (esa etiqueta era de la app de referencia).
- Deduplicación por `notificationKey` nativa: una vez que un registro existe en el box (en cualquier estado, incluido `'descartado'`), una notificación repetida con la misma key se ignora — así "descartado" no reaparece si Android re-postea.
- Sin soporte iOS — Android-only, igual que el resto de la app.
- Moneda CLP, formato `NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0, customPattern: '¤ #,##0')` — mismo patrón usado en `home_screen.dart`/`history_screen.dart` para cualquier UI nueva que muestre montos.

---

### Task 1: Modelo `PendingGooglePayRecord`

**Files:**
- Create: `app/lib/models/pending_google_pay_record.dart`
- Test: `app/test/models/pending_google_pay_record_test.dart`

**Interfaces:**
- Produces: `PendingGooglePayRecord` class con campos `id`, `monto` (double), `comercioTexto` (String), `categoriaSugeridaId` (String?), `fecha` (DateTime), `estado` (String, `'pendiente'` | `'descartado'`), `createdAt` (DateTime). Métodos `toMap() -> Map<String, dynamic>`, `factory PendingGooglePayRecord.fromMap(Map map)`, `copyWith({String? estado})`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/pending_google_pay_record_test.dart
import 'package:billetera/models/pending_google_pay_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap round-trips all fields', () {
    final record = PendingGooglePayRecord(
      id: 'notif-1',
      monto: 8574.0,
      comercioTexto: 'MERCADOPAGO *ARIZMEND',
      categoriaSugeridaId: 'cat-1',
      fecha: DateTime(2026, 8, 7),
      estado: 'pendiente',
      createdAt: DateTime(2026, 8, 7, 10, 30),
    );

    final restored = PendingGooglePayRecord.fromMap(record.toMap());

    expect(restored.id, 'notif-1');
    expect(restored.monto, 8574.0);
    expect(restored.comercioTexto, 'MERCADOPAGO *ARIZMEND');
    expect(restored.categoriaSugeridaId, 'cat-1');
    expect(restored.fecha, DateTime(2026, 8, 7));
    expect(restored.estado, 'pendiente');
    expect(restored.createdAt, DateTime(2026, 8, 7, 10, 30));
  });

  test('fromMap handles a null categoriaSugeridaId', () {
    final record = PendingGooglePayRecord(
      id: 'notif-2',
      monto: 1800.0,
      comercioTexto: 'STA ISABEL VINA DEL MA',
      categoriaSugeridaId: null,
      fecha: DateTime(2026, 8, 6),
      estado: 'pendiente',
      createdAt: DateTime(2026, 8, 6, 9, 0),
    );

    final restored = PendingGooglePayRecord.fromMap(record.toMap());

    expect(restored.categoriaSugeridaId, isNull);
  });

  test('copyWith replaces estado and keeps every other field', () {
    final record = PendingGooglePayRecord(
      id: 'notif-3',
      monto: 4230.0,
      comercioTexto: 'LUCY VENEGAS',
      categoriaSugeridaId: 'cat-2',
      fecha: DateTime(2026, 8, 5),
      estado: 'pendiente',
      createdAt: DateTime(2026, 8, 5, 8, 0),
    );

    final discarded = record.copyWith(estado: 'descartado');

    expect(discarded.estado, 'descartado');
    expect(discarded.id, record.id);
    expect(discarded.monto, record.monto);
    expect(discarded.comercioTexto, record.comercioTexto);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/pending_google_pay_record_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'billetera' in 'package:billetera/models/pending_google_pay_record.dart'` (file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/models/pending_google_pay_record.dart
class PendingGooglePayRecord {
  const PendingGooglePayRecord({
    required this.id,
    required this.monto,
    required this.comercioTexto,
    required this.categoriaSugeridaId,
    required this.fecha,
    required this.estado,
    required this.createdAt,
  });

  final String id;
  final double monto;
  final String comercioTexto;
  final String? categoriaSugeridaId;
  final DateTime fecha;
  final String estado; // 'pendiente' | 'descartado'
  final DateTime createdAt;

  factory PendingGooglePayRecord.fromMap(Map map) => PendingGooglePayRecord(
        id: map['id'] as String,
        monto: (map['monto'] as num).toDouble(),
        comercioTexto: map['comercio_texto'] as String,
        categoriaSugeridaId: map['categoria_sugerida_id'] as String?,
        fecha: DateTime.parse(map['fecha'] as String),
        estado: map['estado'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'monto': monto,
        'comercio_texto': comercioTexto,
        'categoria_sugerida_id': categoriaSugeridaId,
        'fecha': fecha.toIso8601String(),
        'estado': estado,
        'created_at': createdAt.toIso8601String(),
      };

  PendingGooglePayRecord copyWith({String? estado}) => PendingGooglePayRecord(
        id: id,
        monto: monto,
        comercioTexto: comercioTexto,
        categoriaSugeridaId: categoriaSugeridaId,
        fecha: fecha,
        estado: estado ?? this.estado,
        createdAt: createdAt,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/pending_google_pay_record_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/models/pending_google_pay_record.dart test/models/pending_google_pay_record_test.dart
git commit -m "feat: add PendingGooglePayRecord model"
```

---

### Task 2: Parser de notificación Google Pay

**Files:**
- Create: `app/lib/logic/google_pay_notification_parser.dart`
- Test: `app/test/logic/google_pay_notification_parser_test.dart`

**Interfaces:**
- Produces: `class ParsedGooglePayNotification { final double monto; final String comercioTexto; }` y `ParsedGooglePayNotification? parseGooglePayNotification({required String? title, required String? text})`.

**Nota de riesgo (heredada del spec):** el formato exacto de la notificación de Google Wallet en Chile no está confirmado. Este parser cubre dos formatos asumidos (español "Pagaste $X en COMERCIO" con separador decimal coma estilo CL, e inglés "You paid $X at MERCHANT" con separador decimal punto estilo US) y normaliza el monto detectando cuál de `,`/`.` es el separador decimal según cuál aparece más a la derecha del número. Validar y ajustar con una notificación real en dispositivo antes de dar el parser por definitivo.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/logic/google_pay_notification_parser_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/logic/google_pay_notification_parser_test.dart`
Expected: FAIL — file `lib/logic/google_pay_notification_parser.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/logic/google_pay_notification_parser.dart
class ParsedGooglePayNotification {
  const ParsedGooglePayNotification({required this.monto, required this.comercioTexto});

  final double monto;
  final String comercioTexto;
}

final _esPattern = RegExp(r'Pagaste\s+\$?\s*([\d.,]+)\s+en\s+(.+)', caseSensitive: false);
final _enPattern = RegExp(r'You paid\s+\$?\s*([\d.,]+)\s+at\s+(.+)', caseSensitive: false);

ParsedGooglePayNotification? parseGooglePayNotification({
  required String? title,
  required String? text,
}) {
  if (text == null) return null;

  final match = _esPattern.firstMatch(text) ?? _enPattern.firstMatch(text);
  if (match == null) return null;

  final monto = _parseMonto(match.group(1)!);
  if (monto == null) return null;

  final comercioTexto = match.group(2)!.trim();
  if (comercioTexto.isEmpty) return null;

  return ParsedGooglePayNotification(monto: monto, comercioTexto: comercioTexto);
}

/// Handles both decimal conventions since the real device format isn't
/// confirmed yet (see risk note in the Google Pay design spec): CL-style
/// ("8.574,00", comma decimal) and US-style ("8,574.00", point decimal).
/// Whichever of `,`/`.` appears last in the string is treated as the
/// decimal separator; the other is stripped as a thousands separator.
double? _parseMonto(String raw) {
  final trimmed = raw.trim();
  final lastComma = trimmed.lastIndexOf(',');
  final lastDot = trimmed.lastIndexOf('.');

  String normalized;
  if (lastComma > lastDot) {
    normalized = trimmed.replaceAll('.', '').replaceAll(',', '.');
  } else if (lastDot > lastComma) {
    normalized = trimmed.replaceAll(',', '');
  } else {
    normalized = trimmed;
  }
  return double.tryParse(normalized);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/logic/google_pay_notification_parser_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/logic/google_pay_notification_parser.dart test/logic/google_pay_notification_parser_test.dart
git commit -m "feat: add Google Pay notification text parser"
```

---

### Task 3: Matcher de categoría por palabra clave

**Files:**
- Create: `app/lib/logic/google_pay_category_matcher.dart`
- Test: `app/test/logic/google_pay_category_matcher_test.dart`

**Interfaces:**
- Consumes: `Category` (`lib/models/category.dart`, campos `id`, `nombre`, `tipo`).
- Produces: `String? matchCategoryId({required String comercioTexto, required List<Category> categories})`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/logic/google_pay_category_matcher_test.dart
import 'package:billetera/logic/google_pay_category_matcher.dart';
import 'package:billetera/models/category.dart';
import 'package:flutter_test/flutter_test.dart';

const _categories = [
  Category(id: 'c-comida', userId: 'u', nombre: 'Comida', tipo: 'gasto', icono: 'restaurant', predefinida: true),
  Category(id: 'c-transporte', userId: 'u', nombre: 'Transporte', tipo: 'gasto', icono: 'directions_car', predefinida: true),
  Category(id: 'c-otros', userId: 'u', nombre: 'Otros gastos', tipo: 'gasto', icono: 'category', predefinida: true),
];

void main() {
  group('matchCategoryId', () {
    test('matches a food-related keyword', () {
      final id = matchCategoryId(comercioTexto: 'MERCADOPAGO *ARIZMEND', categories: _categories);
      expect(id, 'c-comida');
    });

    test('matches a transport-related keyword', () {
      final id = matchCategoryId(comercioTexto: 'UBER *TRIP HELP.UBER.COM', categories: _categories);
      expect(id, 'c-transporte');
    });

    test('is case-insensitive', () {
      final id = matchCategoryId(comercioTexto: 'starbucks providencia', categories: _categories);
      expect(id, 'c-comida');
    });

    test('falls back to Otros gastos when nothing matches', () {
      final id = matchCategoryId(comercioTexto: 'HIPER VINA CENTRO', categories: _categories);
      expect(id, 'c-otros');
    });

    test('returns null when even Otros gastos is missing from categories', () {
      final id = matchCategoryId(comercioTexto: 'HIPER VINA CENTRO', categories: const []);
      expect(id, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/logic/google_pay_category_matcher_test.dart`
Expected: FAIL — file `lib/logic/google_pay_category_matcher.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/logic/google_pay_category_matcher.dart
import '../models/category.dart';

/// Keyword -> nombre de categoría predefinida (ver `supabase/migrations/0001_init.sql`).
/// Editable solo en código en este alcance — sin UI de reglas custom (YAGNI).
const _keywordRules = <String, String>{
  'restaurant': 'Comida',
  'mercadopago': 'Comida',
  'cafe': 'Comida',
  'starbucks': 'Comida',
  'bar': 'Comida',
  'mcdonalds': 'Comida',
  'pizza': 'Comida',
  'uber': 'Transporte',
  'cabify': 'Transporte',
  'taxi': 'Transporte',
  'metro': 'Transporte',
  'bip': 'Transporte',
  'farmacia': 'Salud',
  'cruz verde': 'Salud',
  'salcobrand': 'Salud',
  'clinica': 'Salud',
  'cine': 'Entretenimiento',
  'netflix': 'Entretenimiento',
  'spotify': 'Entretenimiento',
};

const _fallbackNombre = 'Otros gastos';

String? matchCategoryId({required String comercioTexto, required List<Category> categories}) {
  final lower = comercioTexto.toLowerCase();

  var nombre = _fallbackNombre;
  for (final entry in _keywordRules.entries) {
    if (lower.contains(entry.key)) {
      nombre = entry.value;
      break;
    }
  }

  for (final category in categories) {
    if (category.nombre == nombre && category.tipo == 'gasto') return category.id;
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/logic/google_pay_category_matcher_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/logic/google_pay_category_matcher.dart test/logic/google_pay_category_matcher_test.dart
git commit -m "feat: add Google Pay merchant keyword category matcher"
```

---

### Task 4: `GooglePaySettings` (cuenta por defecto) + registro de Hive boxes

**Files:**
- Create: `app/lib/services/google_pay_settings.dart`
- Modify: `app/lib/main.dart`

**Interfaces:**
- Produces: `class GooglePaySettings { GooglePaySettings(Box box); String? get defaultAccountId; Future<void> setDefaultAccountId(String? accountId); }`. Box name constants `googlePayPendingBoxName = 'google_pay_pending'` and `googlePaySettingsBoxName = 'google_pay_settings'` exported from this file for reuse by later tasks.

No dedicated unit test for this task — it's a thin Hive wrapper with no branching logic, same as the existing `OutboxService` (also untested at the Hive-box level in this codebase; see `lib/services/outbox_service.dart`). Verified manually via `flutter analyze` and by exercising it end-to-end once wired into the UI in Task 8.

- [ ] **Step 1: Write `GooglePaySettings`**

```dart
// app/lib/services/google_pay_settings.dart
import 'package:hive/hive.dart';

const googlePayPendingBoxName = 'google_pay_pending';
const googlePaySettingsBoxName = 'google_pay_settings';

class GooglePaySettings {
  GooglePaySettings(this._box);

  final Box _box;
  static const _keyDefaultAccountId = 'default_account_id';

  String? get defaultAccountId => _box.get(_keyDefaultAccountId) as String?;

  Future<void> setDefaultAccountId(String? accountId) => _box.put(_keyDefaultAccountId, accountId);
}
```

- [ ] **Step 2: Register both Hive boxes at startup**

In `app/lib/main.dart`, add the two new box opens next to the existing `outbox` one:

```dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/theme.dart';
import 'screens/accounts_screen.dart';
import 'screens/app_shell.dart';
import 'screens/budgets_screen.dart';
import 'screens/charts_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/google_pay_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<Map>('outbox');
  await Hive.openBox<Map>(googlePayPendingBoxName);
  await Hive.openBox(googlePaySettingsBoxName);
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  runApp(const BilleteraApp());
}
```

(Rest of `main.dart` — the `BilleteraApp` widget — stays unchanged.)

- [ ] **Step 3: Verify analyzer is clean**

Run: `cd app && flutter analyze lib/services/google_pay_settings.dart lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd app && git add lib/services/google_pay_settings.dart lib/main.dart
git commit -m "feat: add GooglePaySettings and register Google Pay Hive boxes"
```

---

### Task 5: Abstracción de la fuente de notificaciones

**Files:**
- Create: `app/lib/services/google_pay_notification_source.dart`

**Interfaces:**
- Produces: `class RawNotification { final String packageName; final String notificationKey; final String? title; final String? text; }`, `const googleWalletPackageName = 'com.google.android.apps.walletnfcrel'`, `abstract class GooglePayNotificationSource { Stream<RawNotification> get events; Future<bool> hasPermission(); Future<void> requestPermission(); }`.

This is a pure interface (no plugin dependency yet) so `GooglePayListenerService` (Task 6) can be built and tested against a fake before the real plugin is wired in (Task 7). No test file for this task — it's data classes and an abstract declaration with no logic to exercise; it's exercised indirectly by the fake implementation in Task 6's test.

- [ ] **Step 1: Write the interface**

```dart
// app/lib/services/google_pay_notification_source.dart
/// Package name Android assigns to the Google Wallet app — the only source
/// GooglePayListenerService acts on (see Global Constraints in the design spec).
const googleWalletPackageName = 'com.google.android.apps.walletnfcrel';

class RawNotification {
  const RawNotification({
    required this.packageName,
    required this.notificationKey,
    required this.title,
    required this.text,
  });

  final String packageName;

  /// Native notification key, unique per posted notification. Used for
  /// dedupe when Android re-posts the same notification.
  final String notificationKey;
  final String? title;
  final String? text;
}

/// Isolates GooglePayListenerService from the concrete notification-listener
/// plugin so the orchestration logic can be unit tested with a fake. The
/// real, plugin-backed implementation is `PluginGooglePayNotificationSource`
/// (see google_pay_plugin_notification_source.dart, Task 7) — untested by
/// nature, since it wraps a native Android service not practicable in CI.
abstract class GooglePayNotificationSource {
  Stream<RawNotification> get events;
  Future<bool> hasPermission();
  Future<void> requestPermission();
}
```

- [ ] **Step 2: Verify analyzer is clean**

Run: `cd app && flutter analyze lib/services/google_pay_notification_source.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd app && git add lib/services/google_pay_notification_source.dart
git commit -m "feat: add GooglePayNotificationSource abstraction"
```

---

### Task 6: `GooglePayListenerService` (orquestación)

**Files:**
- Create: `app/lib/services/google_pay_listener_service.dart`
- Test: `app/test/services/google_pay_listener_service_test.dart`

**Interfaces:**
- Consumes: `GooglePayNotificationSource`/`RawNotification`/`googleWalletPackageName` (Task 5), `parseGooglePayNotification` (Task 2), `matchCategoryId` (Task 3), `PendingGooglePayRecord` (Task 1), `Category` (`lib/models/category.dart`).
- Produces: `class GooglePayListenerService { GooglePayListenerService(GooglePayNotificationSource source, Box<Map> box, List<Category> categories); void start(); void dispose(); }`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/services/google_pay_listener_service_test.dart
import 'dart:async';
import 'dart:io';

import 'package:billetera/models/category.dart';
import 'package:billetera/services/google_pay_listener_service.dart';
import 'package:billetera/services/google_pay_notification_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeSource implements GooglePayNotificationSource {
  final _controller = StreamController<RawNotification>();

  @override
  Stream<RawNotification> get events => _controller.stream;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> requestPermission() async {}

  void emit(RawNotification notification) => _controller.add(notification);

  Future<void> close() => _controller.close();
}

const _categories = [
  Category(id: 'c-comida', userId: 'u', nombre: 'Comida', tipo: 'gasto', icono: 'restaurant', predefinida: true),
  Category(id: 'c-otros', userId: 'u', nombre: 'Otros gastos', tipo: 'gasto', icono: 'category', predefinida: true),
];

void main() {
  late Directory tempDir;
  late Box<Map> box;
  late _FakeSource source;
  late GooglePayListenerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('google_pay_listener_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<Map>('google_pay_pending_test');
    source = _FakeSource();
    service = GooglePayListenerService(source, box, _categories);
    service.start();
  });

  tearDown(() async {
    service.dispose();
    await source.close();
    await box.close();
    await tempDir.delete(recursive: true);
  });

  test('stores a parseable Google Wallet notification as a pending record', () async {
    source.emit(const RawNotification(
      packageName: googleWalletPackageName,
      notificationKey: 'notif-1',
      title: 'Google Wallet',
      text: 'Pagaste \$8.574,00 en MERCADOPAGO *ARIZMEND',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(box.length, 1);
    final stored = box.get('notif-1')!;
    expect(stored['monto'], 8574.0);
    expect(stored['comercio_texto'], 'MERCADOPAGO *ARIZMEND');
    expect(stored['categoria_sugerida_id'], 'c-comida');
    expect(stored['estado'], 'pendiente');
  });

  test('ignores notifications from other packages', () async {
    source.emit(const RawNotification(
      packageName: 'com.some.bank.app',
      notificationKey: 'notif-2',
      title: 'Banco',
      text: 'Pagaste \$1.000,00 en ALGUN COMERCIO',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(box.length, 0);
  });

  test('ignores a notification body it cannot parse', () async {
    source.emit(const RawNotification(
      packageName: googleWalletPackageName,
      notificationKey: 'notif-3',
      title: 'Google Wallet',
      text: 'Tu tarjeta fue agregada correctamente',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(box.length, 0);
  });

  test('does not duplicate a notification key already stored, even if discarded', () async {
    source.emit(const RawNotification(
      packageName: googleWalletPackageName,
      notificationKey: 'notif-4',
      title: 'Google Wallet',
      text: 'Pagaste \$500,00 en HIPER VINA CENTRO',
    ));
    await Future<void>.delayed(Duration.zero);
    await box.put('notif-4', {...box.get('notif-4')!, 'estado': 'descartado'});

    source.emit(const RawNotification(
      packageName: googleWalletPackageName,
      notificationKey: 'notif-4',
      title: 'Google Wallet',
      text: 'Pagaste \$500,00 en HIPER VINA CENTRO',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(box.length, 1);
    expect(box.get('notif-4')!['estado'], 'descartado');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/google_pay_listener_service_test.dart`
Expected: FAIL — file `lib/services/google_pay_listener_service.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/services/google_pay_listener_service.dart
import 'dart:async';

import 'package:hive/hive.dart';

import '../logic/google_pay_category_matcher.dart';
import '../logic/google_pay_notification_parser.dart';
import '../models/category.dart';
import '../models/pending_google_pay_record.dart';
import 'google_pay_notification_source.dart';

class GooglePayListenerService {
  GooglePayListenerService(this._source, this._box, this._categories);

  final GooglePayNotificationSource _source;
  final Box<Map> _box;
  final List<Category> _categories;
  StreamSubscription<RawNotification>? _subscription;

  void start() {
    _subscription = _source.events.listen(_handle);
  }

  void _handle(RawNotification notification) {
    if (notification.packageName != googleWalletPackageName) return;
    if (_box.containsKey(notification.notificationKey)) return;

    final parsed = parseGooglePayNotification(
      title: notification.title,
      text: notification.text,
    );
    if (parsed == null) return;

    final categoriaId = matchCategoryId(
      comercioTexto: parsed.comercioTexto,
      categories: _categories,
    );

    final now = DateTime.now();
    final record = PendingGooglePayRecord(
      id: notification.notificationKey,
      monto: parsed.monto,
      comercioTexto: parsed.comercioTexto,
      categoriaSugeridaId: categoriaId,
      fecha: now,
      estado: 'pendiente',
      createdAt: now,
    );
    _box.put(record.id, record.toMap());
  }

  void dispose() {
    _subscription?.cancel();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/google_pay_listener_service_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/services/google_pay_listener_service.dart test/services/google_pay_listener_service_test.dart
git commit -m "feat: add GooglePayListenerService orchestration"
```

---

### Task 7: Plugin real + integración en `HomeScreen`

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/lib/services/google_pay_plugin_notification_source.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: `GooglePayNotificationSource`, `RawNotification` (Task 5), `GooglePayListenerService` (Task 6), `googlePayPendingBoxName` (Task 4).
- Produces: `class PluginGooglePayNotificationSource implements GooglePayNotificationSource`, wired into `HomeScreen`'s lifecycle.

**Riesgo de esta tarea (heredado del spec):** implementa el único punto donde el código depende de la API real del plugin `notification_listener_service`, que no es practicable de testear en CI (requiere el `NotificationListenerService` real de Android). El código de abajo refleja la API pública documentada del paquete al momento de escribir este plan — **antes de darla por buena, confirmá contra el `README`/`example/` del paquete instalado** (`flutter pub add` puede resolver una versión con nombres ligeramente distintos) y ajustá si hace falta. Esto es trabajo de verificación manual, no un placeholder: el resto del plan no depende de que esta tarea sea perfecta a la primera, porque Tasks 1-6 ya están cubiertas por tests que no tocan el plugin.

- [ ] **Step 1: Add the plugin dependency**

Run: `cd app && flutter pub add notification_listener_service`

Expected: `pubspec.yaml` gains a `notification_listener_service: ^<version>` line under `dependencies`, and `flutter pub get` runs automatically.

- [ ] **Step 2: Implement the plugin-backed source**

```dart
// app/lib/services/google_pay_plugin_notification_source.dart
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import 'google_pay_notification_source.dart';

/// Real, plugin-backed `GooglePayNotificationSource`. Wraps the
/// `notification_listener_service` package's static API. Verify method/field
/// names below against the installed version's README before relying on
/// this in a release build — see the risk note on this task in the plan.
class PluginGooglePayNotificationSource implements GooglePayNotificationSource {
  @override
  Stream<RawNotification> get events => NotificationListenerService.notificationsStream
      // Filtered here, at the earliest point in Dart, rather than only in
      // GooglePayListenerService — keeps the orchestration layer from
      // processing noise from every other app's notifications (see the
      // design spec's native-filter rationale). GooglePayListenerService
      // still re-checks the package name defensively (and that's what its
      // unit test covers), so this filter isn't load-bearing for either
      // correctness or test coverage — only for reducing unnecessary work.
      .where((event) => event.packageName == googleWalletPackageName)
      .map(
        (event) => RawNotification(
          packageName: event.packageName!,
          notificationKey: event.uniqueId?.toString() ?? '${event.packageName}-${event.title}-${event.content}',
          title: event.title,
          text: event.content,
        ),
      );

  @override
  Future<bool> hasPermission() => NotificationListenerService.isPermissionGranted();

  @override
  Future<void> requestPermission() => NotificationListenerService.requestPermission();
}
```

- [ ] **Step 3: Declare the notification listener service in the Android manifest**

The plugin needs a `<service>` entry with `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE` inside `<application>` in `app/android/app/src/main/AndroidManifest.xml`. **Copy the exact `<service>` block from the installed plugin's own example app** (`~/.pub-cache/hosted/pub.dev/notification_listener_service-<version>/example/android/app/src/main/AndroidManifest.xml`, or the package's GitHub README) rather than retyping it from memory — the service's fully-qualified class name is plugin-internal and must match exactly or the permission screen (Task 8) will have nothing to grant access to. Add it right after the existing `<activity>` block, before the `flutterEmbedding` `<meta-data>`.

- [ ] **Step 4: Start the listener from `HomeScreen`**

In `app/lib/screens/home_screen.dart`, add the import and wire the service into the existing state lifecycle (mirrors how `_outbox` is already created and disposed there):

```dart
import '../services/google_pay_listener_service.dart';
import '../services/google_pay_plugin_notification_source.dart';
import '../services/google_pay_settings.dart';
import 'package:hive/hive.dart';
```

```dart
  GooglePayListenerService? _googlePayListener;
```

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
  }
```

```dart
  @override
  void dispose() {
    _outbox.dispose();
    _googlePayListener?.dispose();
    super.dispose();
  }
```

(`_categoryRepo` already exists in `_HomeScreenState` — see the field declared alongside `_accountRepo`/`_transactionRepo`.)

- [ ] **Step 5: Verify analyzer and existing tests are clean**

Run: `cd app && flutter analyze lib/services/google_pay_plugin_notification_source.dart lib/screens/home_screen.dart`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: All existing tests still PASS (this task doesn't change any tested logic, only wiring).

- [ ] **Step 6: Commit**

```bash
cd app && git add pubspec.yaml pubspec.lock lib/services/google_pay_plugin_notification_source.dart android/app/src/main/AndroidManifest.xml lib/screens/home_screen.dart
git commit -m "feat: wire notification_listener_service plugin into HomeScreen"
```

---

### Task 8: `GooglePaySettingsScreen` (permiso + cuenta por defecto)

**Files:**
- Create: `app/lib/screens/google_pay_settings_screen.dart`
- Modify: `app/lib/screens/accounts_screen.dart`

**Interfaces:**
- Consumes: `GooglePayNotificationSource` (Task 5), `PluginGooglePayNotificationSource` (Task 7), `GooglePaySettings`/`googlePaySettingsBoxName` (Task 4), `Account` (`lib/models/account.dart`).
- Produces: `class GooglePaySettingsScreen extends StatefulWidget { const GooglePaySettingsScreen({required List<Account> accounts}); }`, reachable from a new AppBar action in `AccountsScreen`.

Combina en una sola pantalla lo que el spec describe como "pantalla de permiso" + "cuenta configurable desde pantalla Cuentas" — dos piezas pequeñas (un botón de activar permiso, un dropdown), separarlas en dos pantallas hubiera sido más navegación por nada. Sin widget test dedicado — sigue el patrón de `AccountsScreen`/`BudgetsScreen` (repos/servicios instanciados directo en `initState`, sin test de pantalla en este codebase).

- [ ] **Step 1: Implement the screen**

```dart
// app/lib/screens/google_pay_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/account.dart';
import '../services/google_pay_notification_source.dart';
import '../services/google_pay_plugin_notification_source.dart';
import '../services/google_pay_settings.dart';

class GooglePaySettingsScreen extends StatefulWidget {
  const GooglePaySettingsScreen({super.key, required this.accounts});

  final List<Account> accounts;

  @override
  State<GooglePaySettingsScreen> createState() => _GooglePaySettingsScreenState();
}

class _GooglePaySettingsScreenState extends State<GooglePaySettingsScreen> {
  final GooglePayNotificationSource _source = PluginGooglePayNotificationSource();
  late final GooglePaySettings _settings = GooglePaySettings(Hive.box(googlePaySettingsBoxName));

  bool _hasPermission = false;
  String? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _selectedAccountId = _settings.defaultAccountId;
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final granted = await _source.hasPermission();
    if (mounted) setState(() => _hasPermission = granted);
  }

  Future<void> _save() async {
    await _settings.setDefaultAccountId(_selectedAccountId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final activeAccounts = widget.accounts.where((a) => a.activo).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Google Pay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acceso a notificaciones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La app necesita leer las notificaciones de Google Wallet para armar la cola de registros pendientes. Se activa en Ajustes del sistema.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _hasPermission ? Icons.check_circle : Icons.cancel_outlined,
                        color: _hasPermission ? Colors.green : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(_hasPermission ? 'Activado' : 'No activado'),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await _source.requestPermission();
                          _refreshPermission();
                        },
                        child: const Text('Activar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cuenta por defecto',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Los registros pendientes de Google Pay se insertan en esta cuenta.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedAccountId,
                    decoration: const InputDecoration(labelText: 'Cuenta'),
                    items: activeAccounts
                        .map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Guardar')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add the entry point in `AccountsScreen`**

In `app/lib/screens/accounts_screen.dart`, add the import:

```dart
import 'google_pay_settings_screen.dart';
```

Add a second `IconButton` to the existing `actions` list in the `AppBar` (next to the "Categorias" one):

```dart
      appBar: AppBar(
        title: const Text('Cuentas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Google Pay',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GooglePaySettingsScreen(accounts: _accountsSnapshot),
              ),
            ),
          ),
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

`_AccountsScreenState` doesn't currently keep a synchronous snapshot of the loaded accounts (only the `Future<List<Account>>` used by `FutureBuilder`) — add one so the button has a list to pass without an extra fetch:

```dart
  List<Account> _accountsSnapshot = [];
```

And update `_reload`/`initState` to populate it once the future resolves:

```dart
  void _reload() => setState(() {
    _future = _repo.fetchAll()..then((a) {
      if (mounted) setState(() => _accountsSnapshot = a);
    });
  });
```

```dart
  @override
  void initState() {
    super.initState();
    _reload();
  }
```

(This replaces the current `_future = _repo.fetchAll();` direct assignment in both `initState` and `_reload` with the version above, so `_accountsSnapshot` stays in sync every time the list reloads.)

- [ ] **Step 3: Verify analyzer is clean**

Run: `cd app && flutter analyze lib/screens/google_pay_settings_screen.dart lib/screens/accounts_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd app && git add lib/screens/google_pay_settings_screen.dart lib/screens/accounts_screen.dart
git commit -m "feat: add GooglePaySettingsScreen for permission and default account"
```

---

### Task 9: Card de registros pendientes en `HistoryScreen`

**Files:**
- Modify: `app/lib/screens/history_screen.dart`
- Test: `app/test/screens/history_screen_google_pay_card_test.dart`

**Interfaces:**
- Consumes: `PendingGooglePayRecord` (Task 1), `googlePayPendingBoxName`/`GooglePaySettings`/`googlePaySettingsBoxName` (Task 4), `Category`/`Account`/`Transaction` (existing models), `TransactionRepository.create` (existing).

- [ ] **Step 1: Write the failing widget test**

```dart
// app/test/screens/history_screen_google_pay_card_test.dart
import 'dart:io';

import 'package:billetera/models/pending_google_pay_record.dart';
import 'package:billetera/services/google_pay_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<Map> pendingBox;
  late Box settingsBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('history_google_pay_test');
    Hive.init(tempDir.path);
    pendingBox = await Hive.openBox<Map>(googlePayPendingBoxName);
    settingsBox = await Hive.openBox(googlePaySettingsBoxName);
  });

  tearDown(() async {
    await pendingBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  test('a pendiente record is visible through the box and an estado change persists', () async {
    final record = PendingGooglePayRecord(
      id: 'notif-1',
      monto: 8574.0,
      comercioTexto: 'MERCADOPAGO *ARIZMEND',
      categoriaSugeridaId: 'c-comida',
      fecha: DateTime(2026, 8, 7),
      estado: 'pendiente',
      createdAt: DateTime(2026, 8, 7),
    );
    await pendingBox.put(record.id, record.toMap());

    final pendientes = pendingBox.values
        .map((m) => PendingGooglePayRecord.fromMap(m))
        .where((r) => r.estado == 'pendiente')
        .toList();
    expect(pendientes, hasLength(1));

    final discarded = pendientes.first.copyWith(estado: 'descartado');
    await pendingBox.put(discarded.id, discarded.toMap());

    final stillPending = pendingBox.values
        .map((m) => PendingGooglePayRecord.fromMap(m))
        .where((r) => r.estado == 'pendiente')
        .toList();
    expect(stillPending, isEmpty);
  });

  test('GooglePaySettings default account id round-trips through the settings box', () async {
    final settings = GooglePaySettings(settingsBox);
    expect(settings.defaultAccountId, isNull);

    await settings.setDefaultAccountId('acc-1');
    expect(settings.defaultAccountId, 'acc-1');
  });
}
```

This test exercises the Hive-level data flow the `HistoryScreen` card relies on (list-only-pendientes, discard-keeps-the-key, settings round-trip) without needing a live Supabase client — the existing codebase has no precedent for widget-testing screens that hit `Supabase.instance.client` directly in `initState` (see the note on `DebtsScreen`/`PersonDebtsScreen` in `docs/superpowers/plans/2026-08-06-deudas.md`), so the UI wiring itself is verified manually in Step 4 below instead of through `flutter test`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/screens/history_screen_google_pay_card_test.dart`
Expected: FAIL — `googlePayPendingBoxName`/`googlePaySettingsBoxName` resolve fine (Task 4 already landed), but this specific test file doesn't exist yet, so `flutter test` reports no tests found until the file is created — write it as Step 1 above did, then this run should already PASS since Task 4/1 are already implemented. Treat this as a regular regression check rather than a red-then-green cycle.

- [ ] **Step 3: Add the pending-records card to `HistoryScreen`**

In `app/lib/screens/history_screen.dart`, add imports:

```dart
import 'package:hive/hive.dart';

import '../models/pending_google_pay_record.dart';
import '../services/google_pay_settings.dart';
```

Add state fields to `_HistoryScreenState`:

```dart
  final _pendingBox = Hive.box<Map>(googlePayPendingBoxName);
  late final _googlePaySettings = GooglePaySettings(Hive.box(googlePaySettingsBoxName));
```

Add the insert/discard logic (methods on `_HistoryScreenState`):

```dart
  Future<void> _insertPending(PendingGooglePayRecord record) async {
    final accountId = _googlePaySettings.defaultAccountId;
    if (accountId == null) return;

    await _transactionRepo.create(
      Transaction(
        id: '',
        userId: '',
        accountId: accountId,
        categoryId: record.categoriaSugeridaId,
        tipo: TransactionType.gasto,
        monto: record.monto,
        fecha: record.fecha,
        nota: record.comercioTexto,
      ),
    );
    await _pendingBox.delete(record.id);
    if (mounted) _reload();
  }

  Future<void> _discardPending(PendingGooglePayRecord record) async {
    await _pendingBox.put(record.id, record.copyWith(estado: 'descartado').toMap());
  }

  Future<void> _insertAllPending(List<PendingGooglePayRecord> records) async {
    for (final record in records) {
      await _insertPending(record);
    }
  }
```

Add the card widget as a method:

```dart
  Widget _buildGooglePayCard() {
    return ValueListenableBuilder<Box<Map>>(
      valueListenable: _pendingBox.listenable(),
      builder: (context, box, _) {
        final pendientes = box.values
            .map((m) => PendingGooglePayRecord.fromMap(m))
            .where((r) => r.estado == 'pendiente')
            .toList();
        if (pendientes.isEmpty) return const SizedBox.shrink();

        final accountId = _googlePaySettings.defaultAccountId;

        return Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registros de Google Pay',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('${pendientes.length} registros pendientes de insertar'),
                if (accountId == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Configura una cuenta por defecto para Google Pay en Cuentas.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 8),
                for (final record in pendientes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_currency.format(record.monto)),
                    subtitle: Text(record.comercioTexto),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check),
                          tooltip: 'Insertar',
                          onPressed: accountId == null ? null : () => _insertPending(record),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Descartar',
                          onPressed: () => _discardPending(record),
                        ),
                      ],
                    ),
                  ),
                if (accountId != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _insertAllPending(pendientes),
                      child: const Text('Insertar todos'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
```

Wire it into `build()`, right above the existing filters `Card` (inside the `Column`'s `children`):

```dart
      body: Column(
        children: [
          _buildGooglePayCard(),
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
```

- [ ] **Step 4: Manual verification pass**

This is the point the plan's automated coverage stops (see note in Step 1) — run through it by hand once on a device/emulator with the app logged in:
1. `flutter analyze lib/screens/history_screen.dart` — expect `No issues found!`.
2. Launch the app, go to Cuentas, tap the new "Google Pay" icon, activate the permission and pick a default account.
3. From another app (or `adb shell cmd notification post`, or by waiting for a real Google Wallet payment), trigger a notification and confirm a card appears in Historial with the expected monto/comercio.
4. Tap Insertar — confirm a new transaction shows up in Historial's list and the card entry disappears.
5. Tap Descartar on another pending entry — confirm it disappears and doesn't reappear after restarting the app.

- [ ] **Step 5: Run the full test suite**

Run: `cd app && flutter test`
Expected: All tests PASS, including the new `test/screens/history_screen_google_pay_card_test.dart`.

- [ ] **Step 6: Commit**

```bash
cd app && git add lib/screens/history_screen.dart test/screens/history_screen_google_pay_card_test.dart
git commit -m "feat: add Google Pay pending records card to HistoryScreen"
```

---

## Fuera de alcance (heredado del spec — no hay tasks para esto)

- Notificaciones de apps bancarias u otras billeteras digitales.
- Sincronización de la cola pendiente entre dispositivos o respaldo en la nube antes de insertar.
- UI para editar/agregar reglas de categorización por palabra clave.
- Detección automática de cambios de formato en las notificaciones de Google Wallet.
- Soporte iOS.
