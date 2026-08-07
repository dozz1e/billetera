# Deudas (personas que me deben dinero) — Diseño

Fecha: 2026-08-06
Estado: Aprobado

## Propósito

Agregar un tracker de deudas: personas que le deben dinero al usuario, con la posibilidad de registrar varias deudas independientes por persona (cada una con su propio motivo, monto y fecha). Feature nueva, sin relación con el resto de la app (cuentas, transacciones, presupuestos).

## Decisiones

- **Un solo sentido:** solo se registra plata que le deben al usuario. No se modela plata que el usuario debe a otros.
- **Sin vínculo con cuentas/saldo:** marcar una deuda como pagada no crea una transacción ni afecta el saldo de ninguna cuenta. Es un tracker completamente separado.
- **Sin pagos parciales:** cada deuda individual es un monto fijo con dos estados (`pendiente` | `pagada`). No hay saldo restante ni abonos.
- **Total pendiente por persona:** no se guarda precalculado — se suma dinámicamente sobre las deudas en estado `pendiente` de esa persona, mismo criterio que `calculateAccountBalance()` para el saldo de cuentas (`lib/logic/balance_calculator.dart`).
- **Eliminar una persona borra sus deudas en cascada** (`on delete cascade`) — a diferencia de `accounts`/`categories`, que usan `on delete restrict` porque ahí las transacciones existentes deben seguir siendo válidas. Acá una deuda no tiene sentido sin la persona a la que pertenece.
- **Navegación:** nuevo tab "Deudas", sexto en la barra inferior (Home, Cuentas, Presupuestos, Graficas, Historial, Deudas).

## Modelo de datos (Supabase / Postgres)

RLS igual que el resto de la app (`user_id = auth.uid()`):

```
people
  id          uuid pk
  user_id     uuid fk -> auth.users
  nombre      text
  created_at  timestamptz

debts
  id          uuid pk
  user_id     uuid fk -> auth.users
  person_id   uuid fk -> people, on delete cascade
  motivo      text
  monto       numeric
  fecha       date
  estado      text  -- 'pendiente' | 'pagada', default 'pendiente'
  created_at  timestamptz
```

## Pantallas

1. **DebtsScreen** (tab "Deudas"): lista de personas (mismo patrón visual que `AccountsScreen`/`CategoriesScreen` — `Card` con `ListTile` por fila). Cada fila: nombre + "Total pendiente: $X" (suma dinámica de sus deudas `pendiente`; si no tiene ninguna pendiente, "Sin deuda pendiente"). Botón eliminar por fila (confirmación vía `confirmDelete`, borra en cascada). FAB abre formulario simple: solo nombre.
2. **PersonDebtsScreen** (tap en una persona): `AppBar` con el nombre de la persona. Lista de sus deudas individuales: motivo, monto, fecha, estado. Por cada deuda: botón para alternar pendiente/pagada (mismo patrón que `_toggleActivo` en `AccountsScreen`), botón editar (abre el mismo formulario de alta con los campos prellenados), botón eliminar (confirmación). FAB abre formulario de deuda nueva: motivo (texto), monto, fecha (date picker, default hoy), queda en estado `pendiente`.

## Testing

- **Unit test:** función pura para el total pendiente de una persona, `calculatePersonDebtTotal({required String personId, required List<Debt> debts}) -> double`, suma `monto` de las deudas con `estado == 'pendiente'` de esa persona, ignora `pagada` y deudas de otras personas. Mismo criterio que `balance_calculator_test.dart`.
- **Sin widget test nuevo** para `DebtsScreen`/`PersonDebtsScreen` — siguen el patrón de `AccountsScreen`/`BudgetsScreen` (repositorios instanciados directo desde `Supabase.instance.client` en `initState`, sin test de pantalla en este codebase).

## Fuera de alcance (explícito)

- Deudas del usuario hacia otras personas (el sentido inverso).
- Pagos parciales / saldo restante por deuda.
- Vínculo con cuentas o transacciones al marcar una deuda como pagada.
- Recordatorios o notificaciones de deudas vencidas.
- Historial de quién/cuándo cambió el estado de una deuda.
