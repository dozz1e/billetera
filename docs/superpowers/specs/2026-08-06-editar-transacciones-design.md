# Editar / eliminar transacciones — Diseño

Fecha: 2026-08-06
Estado: Aprobado

## Propósito

`HistoryScreen` hoy muestra transacciones solo de lectura. Agregar edición y eliminación, con el mismo patrón ya usado en `AccountsScreen`/`CategoriesScreen`/`BudgetsScreen`/`GoalsScreen` (íconos de editar/eliminar por fila, `confirmDelete()` para confirmar borrado).

## Decisiones

- **Repositorio:** `TransactionRepository` gana `update(id, changes)` y `delete(id)`, mismo shape que `AccountRepository.update`/`delete`.
- **Formulario reutilizado:** `NewTransactionScreen` se renombra a `TransactionFormScreen` y gana un parámetro opcional `Transaction? initial`. Si viene no-null: título "Editar transacción", todos los campos (tipo, cuenta, cuenta destino, categoría, monto, nota, fecha) se prellenan desde `initial`. El callback `onSubmit` no cambia de forma — quien abre la pantalla decide si hace `create` o `update`.
- **Campo fecha (nuevo):** la pantalla no tiene selector de fecha hoy (usa `DateTime.now()` fijo). Se agrega un campo de fecha (`ListTile` con fecha formateada + `showDatePicker`), default `initial?.fecha ?? DateTime.now()`. Aplica tanto a alta como a edición.
- **Alcance de la edición:** solo transacciones ya sincronizadas (lo que `HistoryScreen` lista viene de `_transactionRepo.fetchAll()`, siempre server-side). Las transacciones en el outbox offline (`OutboxService`, aún sin `id` de servidor) quedan fuera de alcance — no son editables/eliminables desde este flujo.
- **Saldo:** no requiere ningún ajuste adicional. `calculateAccountBalance()` recalcula sobre la lista de transacciones en cada carga, así que editar/eliminar una transacción ya propaga el cambio de saldo sin lógica extra.
- **Errores de red:** mismo patrón que el resto de la app — snackbar "No se pudo eliminar/guardar la transacción. Revisa tu conexión e intenta de nuevo.", sin romper la pantalla.

## Pantallas

1. **`HistoryScreen` (modificada):** cada `ListTile` de la lista gana `trailing: Row` con ícono editar (lápiz) e ícono eliminar (basurero, color `scheme.error`), igual estructura visual que `AccountsScreen`. Tap en editar abre `TransactionFormScreen(initial: t, ...)`; on submit llama `_transactionRepo.update(t.id, nuevo.toInsertJson())` y recarga. Tap en eliminar dispara `confirmDelete()` y, si confirma, `_transactionRepo.delete(t.id)` + recarga.
2. **`TransactionFormScreen` (renombrada, con modo edición):** agrega selector de fecha; el resto de la estructura (tipo, cuenta, cuenta destino/categoría condicional, monto, nota) no cambia.
3. **`HomeScreen`:** actualiza el import/nombre de clase (`NewTransactionScreen` → `TransactionFormScreen`), sin cambio de comportamiento en el flujo de alta.

## Testing

- Renombrar `test/screens/new_transaction_screen_test.dart` → `transaction_form_screen_test.dart`; agregar caso: con `initial` seteado, los campos aparecen prellenados (monto, nota, fecha) y el título dice "Editar transacción".
- Nuevo caso para el date picker: cambiar la fecha y confirmar que el `Transaction` enviado a `onSubmit` refleja la fecha elegida (no `DateTime.now()`).
- `TransactionRepository`: si existen tests de repositorio para otras entidades (`update`/`delete`) seguir el mismo patrón; si no existen (como es el caso hoy — `AccountRepository` tampoco tiene test unitario propio, se cubre vía integración de pantalla), no se agregan tests de repositorio nuevos, solo los de pantalla.

## Fuera de alcance (explícito)

- Editar/eliminar transacciones todavía en el outbox offline (sin `id` de servidor).
- Cambiar el tipo de transacción de transferencia a no-transferencia (o viceversa) durante edición reajustando saldos históricos de forma especial — se maneja igual que cualquier cambio de campo, sin lógica de reconciliación adicional (el saldo ya se recalcula dinámicamente).
- Historial de auditoría de ediciones (quién/cuándo editó).
