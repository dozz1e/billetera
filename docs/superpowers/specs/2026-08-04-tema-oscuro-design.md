# Tema oscuro — Diseño

Fecha: 2026-08-04
Estado: Aprobado

## Propósito

Reemplazar el tema claro fijo actual (`colorSchemeSeed: Colors.teal`, Material3) por un tema oscuro fijo, inspirado en el estilo visual de la app Wallet (BudgetBakers): fondo casi negro, cards planas bien distinguidas del fondo, sin el tinte morado que Material3 aplica por defecto en modo oscuro.

Es un cambio puramente visual — no agrega pantallas, no agrega datos, no cambia lógica. Contexto: capturas de referencia en `images/` (carpeta del working directory), tomadas de la app Wallet.

## Alcance

Solo tema. Toca únicamente la definición de `ThemeData` en `lib/main.dart`. Todas las pantallas existentes (Home, Cuentas, Presupuestos, Gráficas, Historial, Login, formularios de cuenta/transacción/categoría/presupuesto) heredan el tema global sin necesitar cambios de código propio, porque ya usan widgets Material estándar (`Card`, `ListTile`, `AlertDialog`, `Scaffold`, etc.) sin colores hardcodeados que choquen con el fondo oscuro.

## Decisiones

- **Modo:** oscuro fijo, sin toggle ni seguimiento del tema del sistema. Coherente con una app personal de un solo usuario — menos superficie de mantenimiento (una sola paleta que validar).
- **Color de marca:** se mantiene teal (no se adopta el azul de Wallet). La app conserva identidad propia; Wallet es solo referencia de estructura visual (fondo oscuro, cards planas), no de paleta.
- **Base del ColorScheme:** `ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark)`. Material3 deriva automáticamente colores de texto/ícono con contraste correcto sobre cada superficie — evita tener que calcular contraste a mano.
- **Override de superficies planas:** Material3 en modo oscuro por defecto aplica "surface tint" (mezcla el color primario en las superficies elevadas), lo que da un aspecto morado/verdoso no deseado. Se fuerzan valores planos:
  - `scaffoldBackgroundColor`: `#121212`
  - Superficie de cards (`cardTheme.color` / `colorScheme.surface` override según corresponda): `#1E1E1E`
  - Dividers sutiles, sin bordes marcados

## Qué no cambia

- **Paleta de gráficas** (`lib/screens/charts_screen.dart:14`, 8 colores Material estándar: teal, orange, purple, blue, pink, brown, green, indigo) — ya tienen contraste aceptable sobre fondo oscuro, no se tocan.
- **Rojo para gastos/errores** (`Colors.red` en `accounts_screen.dart`, `categories_screen.dart`, `new_transaction_screen.dart`, `login_screen.dart`, `budgets_screen.dart`, `charts_screen.dart`) — funciona bien sobre oscuro tal cual está, no se cambia.
- Ninguna pantalla nueva, ningún modelo de datos nuevo.

## Testing

Sin unit tests (cambio puramente visual, sin lógica que testear). QA manual en el emulador recorriendo:

- Login
- Home
- Cuentas (lista + formulario nueva/editar cuenta)
- Presupuestos
- Gráficas
- Historial
- Nueva transacción

Verificar en cada una: texto legible sobre el fondo, cards distinguibles del fondo, botones visibles, sin contraste roto en ningún widget.

## Fuera de alcance

- Toggle claro/oscuro.
- Seguimiento del tema del sistema operativo.
- Rediseño de paleta de gráficas o colores de estado (rojo/verde).
- Cualquier función nueva (Metas, Pagos planificados quedan como proyectos separados, ver conversación de referencia).
