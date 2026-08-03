# Billetera personal (Android) — Diseño

Fecha: 2026-08-03
Estado: Aprobado

## Propósito

App Android de uso exclusivamente personal (un solo usuario) para registrar ingresos, gastos y transferencias entre cuentas propias, ver saldos por cuenta y consultar gráficas de gasto. Reemplaza registro manual disperso por una sola fuente de verdad con respaldo en la nube.

## Stack

- **Frontend**: Flutter (Android). Un solo código, buen soporte de gráficas (`fl_chart`), rápido de construir para app personal.
- **Backend**: Supabase (Postgres + Auth). Proyecto Supabase nuevo, dedicado solo a esta app.
- **Auth**: Supabase Auth, login con email/password. Protege los datos en la nube con RLS por `user_id`.
- **Moneda**: única, CLP (peso chileno). Sin tasas de cambio ni multi-moneda.
- **Registro de transacciones**: 100% manual. No hay integración con Google Wallet ni bancos — no existe API pública de terceros para leer transacciones de Google Pay, y los bancos en Chile no ofrecen open banking abierto para apps personales sin convenio. Queda fuera de alcance.

## Arquitectura de datos y sync

**Online-first con cache local.** La app habla directo contra Supabase (`supabase_flutter`) para lectura y escritura. Un cache local con Hive guarda el último snapshot de datos para poder consultarlos sin señal.

Si el usuario registra una transacción sin conexión, el registro queda en una cola local (outbox) y se sincroniza automáticamente al recuperar señal (`connectivity_plus` escucha cambios de red). No hay motor de resolución de conflictos porque es un solo usuario en un solo dispositivo — no hay escritura concurrente que reconciliar.

Se descartó un motor offline-first con base local (SQLite/drift) y sync bidireccional completo: resolver conflictos no aporta nada en un escenario de un solo dispositivo, y el celular casi siempre tiene señal. La complejidad extra no se justifica.

## Modelo de datos (Supabase / Postgres)

Todas las tablas con Row Level Security filtrando por `user_id = auth.uid()`.

```
accounts
  id            uuid pk
  user_id       uuid fk -> auth.users
  nombre        text
  tipo          text  -- 'efectivo' | 'banco' | 'credito' | 'billetera_digital'
  saldo_inicial numeric
  activo        boolean default true
  created_at    timestamptz

categories
  id            uuid pk
  user_id       uuid fk -> auth.users
  nombre        text
  tipo          text  -- 'ingreso' | 'gasto'
  icono         text
  predefinida   boolean default false

transactions
  id                 uuid pk
  user_id            uuid fk -> auth.users
  account_id         uuid fk -> accounts
  category_id        uuid fk -> categories, nullable  -- null si tipo = 'transferencia'
  account_destino_id uuid fk -> accounts, nullable     -- solo si tipo = 'transferencia'
  tipo               text  -- 'ingreso' | 'gasto' | 'transferencia'
  monto              numeric
  fecha              date
  nota               text, nullable
  created_at         timestamptz

budgets
  id             uuid pk
  user_id        uuid fk -> auth.users
  category_id    uuid fk -> categories
  mes            date  -- primer día del mes que aplica
  monto_limite   numeric
```

El saldo de cada cuenta se **calcula** (`saldo_inicial` + suma de transacciones que la afectan), no se guarda como columna — evita desincronización entre saldo guardado y transacciones reales.

Una transferencia es un solo registro en `transactions` con `account_id` (origen) y `account_destino_id` (destino); resta del origen y suma en el destino. No cuenta como ingreso ni gasto en las gráficas ni en los totales de ingreso/gasto.

## Categorías

Vienen predefinidas (comida, transporte, sueldo, etc., marcadas `predefinida = true`) y el usuario puede agregar o editar las propias.

## Presupuestos

Por categoría y mes (`budgets`). En la pantalla de presupuestos se muestra barra de progreso (gastado / límite) con alerta visual (cambio de color) al superar el límite. Sin notificaciones push en el MVP — solo indicador visual dentro de la app.

## Pantallas

1. **Login** — email/password contra Supabase Auth.
2. **Home** — saldo total y saldo por cuenta (cards), lista de transacciones recientes, botón de acceso rápido para nueva transacción (ingreso / gasto / transferencia).
3. **Nueva transacción** — formulario que cambia según tipo: monto, cuenta, categoría, fecha, nota; si es transferencia, pide cuenta destino y no pide categoría.
4. **Cuentas** — listado, crear/editar/desactivar cuenta.
5. **Categorías** — listado de predefinidas + agregar/editar propias.
6. **Presupuestos** — por categoría/mes, barra de progreso, alerta visual si se supera el límite.
7. **Gráficas**:
   - Torta/dona: gasto por categoría del mes.
   - Barras: ingresos vs gastos por mes (últimos 6-12 meses).
   - Línea: evolución del saldo total en el tiempo.
   - Barras: saldo actual por cuenta.
8. **Historial / filtros** — todas las transacciones, filtrables por cuenta, categoría, fecha y tipo.

## Manejo de errores

- **Sin señal al escribir**: la transacción se guarda en el outbox local, se muestra un ícono de "pendiente de sincronizar" en esa transacción, y se reintenta automáticamente al reconectar.
- **Falla de login**: mensaje de error claro en pantalla, sin crash de la app.
- **Validación de formularios**: monto debe ser número positivo; cuenta y categoría son requeridas (categoría no aplica a transferencias); en transferencias, cuenta origen y destino no pueden ser la misma.

## Testing

- **Unit tests** (Dart, sin UI): lógica de cálculo de saldo por cuenta y agregación de datos para las gráficas.
- **Widget tests**: formulario de nueva transacción (validaciones, cambio de campos según tipo).
- **Sin integración automatizada contra Supabase real** — fuera de alcance para una app personal de un solo usuario. Se verifica manualmente en el dispositivo antes de dar por terminada cada etapa.

## Fuera de alcance (explícito)

- Multi-moneda / tasas de cambio.
- Integración automática con bancos o Google Wallet.
- Multi-usuario / compartir cuentas con otra persona.
- Notificaciones push.
- Sync offline-first con resolución de conflictos.
