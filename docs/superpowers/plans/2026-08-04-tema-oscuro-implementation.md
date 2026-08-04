# Tema oscuro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar el tema claro fijo de la app (`colorSchemeSeed: Colors.teal`, Material3 default) por un tema oscuro fijo con superficies planas tipo Wallet (BudgetBakers), sin agregar pantallas ni cambiar lógica.

**Architecture:** Un solo archivo nuevo `lib/core/theme.dart` exporta una constante `appTheme` (`ThemeData`) construida con `ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark)` más overrides planos de `scaffoldBackgroundColor` y `cardColor`. `main.dart` importa y usa `appTheme` en vez de construir el `ThemeData` inline. Ninguna otra pantalla cambia código — todas heredan del tema global.

**Tech Stack:** Flutter/Dart, Material3 (`useMaterial3: true`, ya en uso).

## Global Constraints

- Fondo (`scaffoldBackgroundColor`): `#121212` — valor exacto del spec.
- Superficie de cards (`cardColor`): `#1E1E1E` — valor exacto del spec.
- Color semilla: `Colors.teal` (sin cambios) — el spec descarta adoptar el azul de Wallet.
- Modo oscuro fijo — sin toggle, sin `ThemeMode.system`.
- No tocar `charts_screen.dart` (paleta de gráficas) ni los usos de `Colors.red` para errores/gastos — el spec los deja fuera de alcance explícitamente.

---

### Task 1: Crear `lib/core/theme.dart` con `appTheme`

**Files:**
- Create: `app/lib/core/theme.dart`
- Test: `app/test/core/theme_test.dart`

**Interfaces:**
- Produces: `appTheme` — `ThemeData` constante, importable como `import 'core/theme.dart';` y usable como `theme: appTheme`. Task 2 depende de este nombre exacto.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/core/theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billetera/core/theme.dart';

void main() {
  test('appTheme usa fondo y superficie de card planos, oscuros', () {
    expect(appTheme.scaffoldBackgroundColor, const Color(0xFF121212));
    expect(appTheme.cardColor, const Color(0xFF1E1E1E));
  });

  test('appTheme usa brightness oscuro con semilla teal', () {
    expect(appTheme.brightness, Brightness.dark);
    expect(appTheme.colorScheme.brightness, Brightness.dark);
  });

  test('appTheme usa Material3', () {
    expect(appTheme.useMaterial3, true);
  });
}
```

Nota: revisar el nombre del paquete en `app/pubspec.yaml` (campo `name:`) antes de escribir el import — si no es `billetera`, ajustar el import a `package:<nombre_real>/core/theme.dart`.

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `cd app && flutter test test/core/theme_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'billetera' in 'package:billetera/core/theme.dart'` (o similar, porque `theme.dart` todavía no existe).

- [ ] **Step 3: Implementar `lib/core/theme.dart`**

```dart
import 'package:flutter/material.dart';

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: const Color(0xFF121212),
  cardColor: const Color(0xFF1E1E1E),
  cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
);
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `cd app && flutter test test/core/theme_test.dart`
Expected: PASS — 3 tests OK.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/theme.dart app/test/core/theme_test.dart
git commit -m "feat: add dark theme definition"
```

---

### Task 2: Usar `appTheme` en `main.dart`

**Files:**
- Modify: `app/lib/main.dart:1-32`

**Interfaces:**
- Consumes: `appTheme` de `lib/core/theme.dart` (Task 1).

- [ ] **Step 1: Agregar el import**

En `app/lib/main.dart`, después de la línea `import 'core/env.dart';` (línea 5), agregar:

```dart
import 'core/theme.dart';
```

- [ ] **Step 2: Reemplazar la línea del theme**

Cambiar la línea 32 de:

```dart
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
```

a:

```dart
      theme: appTheme,
```

- [ ] **Step 3: Verificar que compila y los tests existentes siguen pasando**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: todos los tests existentes más los 3 nuevos de `theme_test.dart` en PASS, 0 fallos.

- [ ] **Step 4: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat: wire dark theme into MaterialApp"
```

---

### Task 3: QA manual en emulador

**Files:** ninguno (verificación visual, sin cambios de código).

**Interfaces:** ninguna — task terminal, no produce nada para tasks siguientes.

- [ ] **Step 1: Compilar e instalar el debug APK con el tema nuevo**

Run (desde `app/`):
```bash
flutter build apk --debug --dart-define-from-file=env.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk` y `Success` del install.

Si no hay emulador corriendo, levantarlo primero:
```bash
nohup /home/dozzie/Android/Sdk/emulator/emulator -avd billetera_test -no-snapshot-load -no-boot-anim > /tmp/emulator_qa.log 2>&1 &
disown
until adb wait-for-device shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do sleep 3; done
```

- [ ] **Step 2: Abrir la app y capturar Login**

```bash
adb shell am force-stop com.cenakin.billetera
adb shell monkey -p com.cenakin.billetera -c android.intent.category.LAUNCHER 1
sleep 2
adb exec-out screencap -p > /tmp/qa_login.png
```
Revisar `/tmp/qa_login.png` (leer con la herramienta Read): fondo debe verse `#121212` (casi negro, no morado), campos de texto y botón "Entrar" legibles.

- [ ] **Step 3: Login y capturar Home**

Usar credenciales de prueba conocidas para hacer login (tap en campo email, `input text`, tap en campo password, `input text`, tap en "Entrar" — coordenadas exactas vía `adb shell uiautomator dump` si cambiaron respecto a antes). Tras cargar Home:

```bash
adb exec-out screencap -p > /tmp/qa_home.png
```
Revisar: cards de cuentas con fondo `#1E1E1E` distinguible del `#121212` de fondo, texto legible, FAB visible.

- [ ] **Step 4: Recorrer y capturar el resto de pantallas**

Para cada tab (Cuentas, Presupuestos, Gráficas, Historial) — usar `adb shell uiautomator dump` para sacar los `bounds` exactos de cada tab en la barra inferior, tap en el centro de esos bounds, luego:

```bash
adb exec-out screencap -p > /tmp/qa_<pantalla>.png
```

Revisar cada captura (leer con Read): cards y listas distinguibles del fondo, texto de montos (rojo para gasto, verde/teal para ingreso) legible, gráficas de `charts_screen.dart` con colores visibles sobre fondo oscuro, sin bloques de color roto o texto negro-sobre-negro.

- [ ] **Step 5: Capturar formularios**

Abrir "Nueva cuenta" (FAB en Cuentas) y "Nueva transacción" (FAB en Home), capturar cada diálogo:

```bash
adb exec-out screencap -p > /tmp/qa_form_cuenta.png
adb exec-out screencap -p > /tmp/qa_form_transaccion.png
```
Revisar: fondo del diálogo distinguible del scrim, campos de texto y dropdowns legibles, botones "Guardar"/"Cancelar" visibles.

- [ ] **Step 6: Reportar resultado**

Si todas las capturas muestran texto legible y cards distinguibles del fondo (sin negro-sobre-negro ni contraste roto): QA pasa, no hay commit adicional (task 1 y 2 ya cerraron el cambio de código).

Si alguna pantalla muestra un problema de contraste puntual (ej. un texto específico ilegible): anotar la pantalla y el widget exacto, y corregirlo con un ajuste de color local en ese widget (no reabrir `theme.dart` salvo que el problema sea sistémico en todas las pantallas).

---

## Self-Review

**Cobertura del spec:** modo oscuro fijo (Task 1: `brightness: Brightness.dark` sin toggle) ✓. Color semilla teal sin cambios (Task 1) ✓. Superficies planas `#121212`/`#1E1E1E` (Task 1, valores exactos del spec) ✓. Paleta de gráficas y rojo de errores sin tocar (Global Constraints, ninguna task los modifica) ✓. QA manual de las 5 pantallas + formularios (Task 3) ✓.

**Placeholders:** ninguno — todos los steps tienen código o comandos completos.

**Consistencia de tipos:** `appTheme` como `ThemeData` se define en Task 1 y se consume igual en Task 2 (`theme: appTheme`). Sin discrepancias de nombre.
