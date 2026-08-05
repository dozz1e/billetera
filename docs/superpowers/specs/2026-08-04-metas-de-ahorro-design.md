# Metas de ahorro — Diseño

Fecha: 2026-08-04
Estado: Aprobado

## Propósito

Agregar seguimiento de metas de ahorro (ej. "Arriendo departamento", CLP 1.500.000, fecha objetivo 31/10/2026), inspirado en la sección "Metas" de la app Wallet (BudgetBakers) — ver capturas de referencia en `images/` del working directory. Feature nueva, independiente del proyecto de tema oscuro (ver `docs/superpowers/specs/2026-08-04-tema-oscuro-design.md`).

## Decisiones

- **Fuente del "ahorrado":** la meta se vincula a una cuenta existente (`account_id`). El ahorrado **no se guarda** — se calcula igual que el saldo de cualquier cuenta, reutilizando `calculateAccountBalance()` (`lib/logic/balance_calculator.dart`, ya existe, sin cambios). Cero UI nueva para registrar aportes; los aportes son las transacciones que el usuario ya registra normalmente contra esa cuenta.
- **Estados** (`activo` | `pausado` | `alcanzado`):
  - **Alcanzado:** automático. Al cargar la pantalla de Metas, si `ahorrado >= monto_objetivo` y el estado actual no es `pausado`, se persiste `UPDATE estado='alcanzado'`. Se persiste (no se recalcula en cada render) para que el filtro por tab funcione directo contra la columna `estado`.
  - **Pausado:** toggle manual del usuario.
  - **Activo:** estado inicial y al despausar.
- **Navegación:** la pantalla Presupuestos (`lib/screens/budgets_screen.dart`) pasa a tener un `TabBar` de 2 tabs: "Presupuestos" (sin cambios) y "Metas" (nuevo). Dentro de Metas, un segundo `TabBar` anidado: Activo / Pausado / Alcanzado, filtra la lista ya cargada en memoria por `estado` (sin refetch por tab).
- **Ícono:** sin selector en el MVP — ícono fijo (`Icons.flag` o similar), mismo criterio que categorías hoy (`icono: 'category'` hardcodeado en `categories_screen.dart:65`, sin picker).

## Modelo de datos (Supabase / Postgres)

Nueva tabla, RLS igual que el resto de la app (`user_id = auth.uid()`):

```
goals
  id              uuid pk
  user_id         uuid fk -> auth.users
  nombre          text
  account_id      uuid fk -> accounts
  monto_objetivo  numeric
  fecha_objetivo  date
  estado          text  -- 'activo' | 'pausado' | 'alcanzado', default 'activo'
  created_at      timestamptz
```

## Pantallas

1. **Presupuestos (modificada):** `TabBar` con "Presupuestos" | "Metas".
2. **Metas (nueva, dentro del tab):** `TabBar` anidado Activo/Pausado/Alcanzado. Lista de metas del tab activo: nombre, ícono fijo, barra de progreso, "Ahorrado: $X / Objetivo: $Y". FAB para nueva meta.
3. **Formulario nueva meta:** nombre, dropdown de cuenta (cuentas activas existentes), monto objetivo, fecha objetivo (date picker).
4. **Detalle de meta:** tap en una meta de la lista abre nombre, fecha objetivo, barra de progreso grande, "Ahorrado: $X / Objetivo: $Y", botón pausar/reactivar.

## Testing

- **Unit test:** función pura de transición de estado, `nextGoalState({required double ahorrado, required double montoObjetivo, required String estadoActual}) -> String`, cubre: activo→alcanzado cuando ahorrado >= objetivo; pausado no cambia aunque ahorrado >= objetivo; alcanzado se mantiene aunque el saldo baje después (no hay "des-alcanzar" automático).
- **Sin widget test nuevo** — sigue el patrón de `budgets_screen.dart` y `categories_screen.dart`, que tampoco tienen.

## Fuera de alcance (explícito)

- Selector de ícono para metas (ni para categorías — no existe hoy).
- Aportes manuales independientes de cuenta (la meta siempre está atada a una cuenta real).
- Des-alcanzar una meta automáticamente si el saldo de la cuenta baja después de alcanzarla.
- Notificaciones o recordatorios de la fecha objetivo.
