# Pagos recurrentes — Diseño

Fecha: 2026-08-07
Estado: Aprobado

## Propósito

Permitir marcar un gasto como "repite cada mes" (ej. una deuda que se paga el mismo día de cada mes). La app genera automáticamente la transacción real cada mes, sin intervención manual, indefinidamente hasta que el usuario pause o borre la recurrencia.

## Decisiones

- **Solo gastos** (`tipo == gasto`). Ingresos/transferencias recurrentes quedan fuera de alcance.
- **Auto-generación**, no recordatorio: al llegar la fecha, se crea sola la `Transaction` real (afecta saldo, aparece en historial), sin que el usuario confirme nada.
- **Disparador: al abrir la app.** Sin cron en el servidor. En `HomeScreen.initState` (mismo lugar y patrón que `GooglePayListenerService`), se revisan las plantillas activas y se generan las transacciones vencidas.
- **Indefinido**, sin número de cuotas ni fecha de fin. Se detiene solo si el usuario pausa (`activo = false`) o borra la plantilla.
- **Backfill con tope de 12 meses.** Si pasaron más de 12 meses sin abrir la app, se generan solo los últimos 12 vencidos y se descartan los anteriores (evita crear años de historial de golpe). Se avisa al usuario con un `SnackBar`: "Se generaron N pagos pendientes." (si N > 0).
- **Guard de cuenta/categoría borrada:** si la `account_id` o `category_id` de una plantilla ya no existe, esa plantilla se salta silenciosamente (no rompe la generación de las demás), mismo patrón que el stale-guard ya usado en Google Pay.
- **Trazabilidad:** cada `Transaction` generada guarda `recurring_payment_id` (nullable FK), para saber de qué plantilla nació. No se usa todavía para nada en UI, pero deja la puerta abierta.
- **Sin marca visual especial** en Historial/Home: una transacción generada se ve igual que una manual.
- **Navegación:** no es un tab nuevo en la barra inferior. Se agrega como tercera sub-pestaña en la pantalla de Presupuestos, junto a "Presupuestos" y "Metas" (mismo `TabController`, ahora `length: 3`).

## Modelo de datos (Supabase / Postgres)

RLS igual que el resto de la app (`user_id = auth.uid()`):

```
recurring_payments
  id                uuid pk
  user_id           uuid fk -> auth.users
  account_id        uuid fk -> accounts
  category_id       uuid fk -> categories
  monto             numeric, check (monto > 0)
  dia_mes           int, check (dia_mes between 1 and 31)
  nota              text nullable
  fecha_inicio      date        -- fecha elegida al crear la plantilla
  ultima_generada   date nullable  -- fecha (mes) de la última Transaction generada
  activo            bool default true
  created_at        timestamptz

transactions
  + recurring_payment_id  uuid nullable fk -> recurring_payments, on delete set null
```

`on delete set null` en la FK de `transactions`: si se borra la plantilla, las transacciones ya generadas quedan como transacciones normales (no se borran en cascada — ya afectaron saldo real).

`dia_mes` se guarda por separado de `fecha_inicio` porque meses con menos de 31 días necesitan un caso especial: si `dia_mes` no existe en el mes a generar (ej. 31 en febrero), se usa el último día de ese mes.

## Lógica de generación

Función pura y testeable, en `lib/logic/recurring_payment_generator.dart`:

```dart
List<DateTime> computeDueOccurrences({
  required int diaMes,
  required DateTime fechaInicio,
  required DateTime? ultimaGenerada,
  required DateTime hoy,
  int maxBackfill = 12,
})
```

Devuelve la lista de fechas (una por mes) que faltan generar entre `ultimaGenerada` (o `fechaInicio` si es null) y `hoy`, recortada a los últimos `maxBackfill` si excede el tope. Ajusta `dia_mes` al último día del mes cuando corresponda (ej. 31 en abril → 30).

Wrapper de efectos (`RecurringPaymentService`, análogo a `GooglePayListenerService`): en `HomeScreen.initState`, tras cargar cuentas/categorías —

1. Trae las plantillas activas (`RecurringPaymentRepository.fetchActive()`).
2. Por cada una, valida que `account_id`/`category_id` sigan existiendo (guard); si no, la salta.
3. Calcula fechas vencidas con `computeDueOccurrences`.
4. Por cada fecha vencida, crea una `Transaction` (`tipo: gasto`, `recurring_payment_id` seteado) vía `OutboxService.create()` — mismo camino offline-first que una transacción manual.
5. Actualiza `ultima_generada` de la plantilla a la última fecha generada.
6. Si se generó al menos 1, muestra `SnackBar` con el conteo total.

Falla no bloqueante: si la generación completa falla (ej. sin red), se loguea (`debugPrint`) y no impide que el resto de `HomeScreen` cargue — mismo criterio que el arranque del listener de Google Pay.

## Pantallas

1. **TransactionFormScreen**: checkbox "Repetir cada mes", visible solo cuando `tipo == gasto`. Al guardar con el checkbox marcado:
   - Se crea la plantilla `recurring_payments` (`dia_mes` = día de la `fecha` elegida en el form, `fecha_inicio` = esa fecha).
   - **No** se crea también una `Transaction` suelta en el mismo submit — la primera ocurrencia nace del mismo generador que las siguientes, en el próximo ciclo de `HomeScreen.initState` (que corre inmediatamente después de cerrar el formulario, ya que este vive dentro de `HomeScreen`). Si la fecha elegida es hoy o pasada, se genera al instante; si es futura, se genera cuando llegue esa fecha y el usuario abra la app.
2. **Sub-tab "Recurrentes"** en `BudgetsScreen` (tercera, junto a Presupuestos/Metas): lista de plantillas activas — categoría, cuenta, monto, día del mes. Por fila: botón pausar/reanudar (toggle `activo`), botón eliminar (confirmación vía `confirmDelete`, coherente con el resto de la app). Sin FAB propio — las plantillas solo se crean desde `TransactionFormScreen`.

## Testing

- **Unit test** para `computeDueOccurrences`: casos — sin generación previa, con `ultima_generada` reciente (0 pendientes), varios meses vencidos, tope de 12 aplicado, ajuste de día en meses cortos (31 → 28/29/30).
- **Sin widget test nuevo** para la sub-tab de Recurrentes ni para el checkbox del formulario — mismo criterio que el resto de pantallas CRUD simples en este codebase (`AccountsScreen`, `DebtsScreen`).

## Fuera de alcance (explícito)

- Ingresos o transferencias recurrentes.
- Recurrencia con frecuencia distinta a mensual (semanal, anual, etc.).
- Número de cuotas / fecha de fin.
- Editar una plantilla existente (monto, día, cuenta) — por ahora solo pausar/reanudar/eliminar. Para cambiar el monto, se borra la plantilla y se crea una nueva.
- Notificación push o recordatorio antes de generar.
- Marca visual distinta para transacciones generadas vs manuales.
