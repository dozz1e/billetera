# Integración Google Pay (registro semi-automático vía notificaciones) — Diseño

Fecha: 2026-08-07
Estado: Aprobado

## Propósito

Reducir registro manual de gastos pagados con Google Pay: la app escucha notificaciones de la app Google Wallet en el celular, extrae monto y comercio, arma una cola de "registros pendientes" revisable, y el usuario los inserta (o descarta) como transacciones reales con un tap. Inspirado en app de terceros (ver `1.jpg`), pero acotado a Google Pay únicamente (no bancos).

**Nota**: esto revierte el punto del diseño original (`2026-08-03-billetera-app-design.md`) que descartaba integración con Google Wallet por falta de API pública. No existe API pública de *transacciones*, pero sí es posible leer el *texto de la notificación* que Android muestra cuando se paga — mecanismo distinto, con limitaciones propias (ver Riesgos).

## Decisiones

- **Solo notificaciones de Google Wallet** (`com.google.android.apps.walletnfcrel`), no de apps bancarias. Menor cobertura que leer todos los bancos, pero menor superficie de permisos y alineado al alcance pedido.
- **Cola pendiente es local, no Supabase.** Los registros pendientes viven en un Hive box en el dispositivo hasta que el usuario los inserta o descarta; solo al insertar se crea un row real en `transactions` (vía `transaction_repository.dart` existente). Si el usuario descarta o desinstala sin insertar, no queda rastro en la nube — coherente con que es un solo dispositivo, un solo usuario.
- **Cuenta destino fija y configurable**, no elegida cada vez. La notificación no indica a qué cuenta de la app corresponde el pago, así que el usuario configura una "cuenta por defecto Google Pay" una vez (cualquier `account` existente); todo registro pendiente usa esa cuenta, editable antes de insertar si hace falta.
- **Categorización automática por palabra clave, editable.** Lista de reglas en código (`(palabraClave, categoriaNombre)`) matchea contra el texto crudo del comercio en minúsculas; sin match cae en categoría "Gasto desconocido". Usuario puede cambiar la categoría sugerida antes de insertar. Sin UI de reglas custom en este alcance (YAGNI).
- **Permiso especial de notificaciones**, no es un permiso runtime estándar de Android — se otorga manualmente en Ajustes del sistema. La app no puede mostrar el diálogo nativo de permisos; en su lugar muestra una pantalla explicativa con un botón que abre Ajustes directo (`ACTION_NOTIFICATION_LISTENER_SETTINGS`). Sin este permiso, la feature no captura nada pero el resto de la app sigue funcionando normal.
- **Deduplicación por notification key nativa.** Android a veces re-postea la misma notificación; el `id` del registro pendiente se deriva de la key nativa (única), así que un reintento no genera duplicado en la cola.
- **Ubicación en UI**: card "Registros de Google Pay" en la pantalla Historial existente (`history_screen.dart`), arriba del listado, visible solo si hay ≥1 pendiente. No se agrega tab nuevo.

## Arquitectura

- Plugin Flutter mantenido para `NotificationListenerService` (plumbing + solicitud de permiso), en vez de escribir el listener nativo desde cero.
- Filtro por `packageName` en capa nativa (antes de llegar a Dart) para descartar notificaciones de otras apps y no gastar CPU/batería parseando ruido.
- Parsing (regex extracción de monto y comercio) y matching de categoría viven en Dart (`lib/services/google_pay_listener_service.dart`), no en Kotlin — permite testear con `flutter test` siguiendo el patrón TDD ya usado en el proyecto (ver `balance_calculator_test.dart`, `calculatePersonDebtTotal`).
- Servicio nuevo sigue el patrón de `lib/services/outbox_service.dart` ya existente (cola local que se resuelve por acción del usuario/reconexión).

## Modelo de datos

**Local (Hive box, no tabla Supabase):**

```
PendingGooglePayRecord
  id                String    -- hash de notificationKey nativa (dedupe)
  monto             double
  comercioTexto     String    -- texto crudo del comercio tal como llega en la notificación
  categoriaSugerida String?   -- resultado de matcher por palabra clave, null si no matchea
  fecha             DateTime
  estado            String    -- 'pendiente' | 'descartado'
  createdAt         DateTime
```

**Configuración local**: `accountIdGooglePayDefault` (uuid de un `account` existente) — guardado junto al resto de preferencias locales de la app, configurable desde pantalla Cuentas.

No hay cambios al esquema de Supabase — los registros pendientes nunca se guardan ahí; al insertarse se convierten en un `transactions` row normal, indistinguible de uno creado a mano.

## Pantallas

**Card en HistoryScreen** ("Registros de Google Pay"):
- Visible solo si hay ≥1 registro con `estado == 'pendiente'`.
- Por ítem: ícono de categoría, texto de comercio, monto, fecha, categoría sugerida (tap para cambiar antes de insertar).
- Acciones por ítem: **Insertar** (crea `transactions` row con la cuenta default configurada y categoría elegida, marca el pendiente como resuelto/lo remueve del box) y **Descartar** (`estado = 'descartado'`, no vuelve a aparecer).
- Botón "Insertar todos" para aceptar la cola completa de una vez.
- Si no hay cuenta default Google Pay configurada: la card muestra aviso con link a configurarla, en vez de bloquear el resto de Historial.

**Pantalla de permiso** (nueva, mostrada la primera vez o desde Ajustes): explica qué hace la feature, botón "Activar" abre Ajustes del sistema (`ACTION_NOTIFICATION_LISTENER_SETTINGS`), botón "Ahora no" cierra sin activar.

## Riesgos / limitaciones aceptadas

- **Formato exacto de la notificación Google Pay en Chile no está confirmado** — se diseña el parser contra un formato asumido genérico ("Pagaste $X en COMERCIO" / equivalente en inglés), con regex flexible. Requiere validación y ajuste con una notificación real en dispositivo antes de considerar el parser completo; si el formato real difiere mucho, puede necesitar iteración post-implementación.
- Si Google cambia el texto/formato de sus notificaciones en una actualización de la app Wallet, el parser puede dejar de matchear silenciosamente (los registros simplemente no se generan) — no hay forma de detectar esto automáticamente en este alcance.
- El permiso de acceso a notificaciones es amplio a nivel Android (técnicamente el listener recibe la posted notification de cualquier app, aunque se filtre en código); esto es inherente al mecanismo, no algo que se pueda acotar más a nivel de permiso del sistema.

## Testing

- Unit tests para el parser (regex): formato esperado → extrae monto/comercio correctos; formato inesperado → retorna null / no genera registro.
- Unit tests para el matcher de categoría por palabra clave: casos con match, caso sin match (cae a "Gasto desconocido").
- Widget tests para la card en Historial: estado vacío (sin card), con pendientes, insertar ítem, descartar ítem, "Insertar todos".
- Sin test de integración real del `NotificationListenerService` (no es practicable en CI) — se valida manualmente en dispositivo.

## Fuera de alcance (explícito)

- Notificaciones de apps bancarias u otras billeteras digitales (solo Google Wallet).
- Sincronización de la cola pendiente entre dispositivos o respaldo en la nube antes de insertar.
- UI para editar/agregar reglas de categorización por palabra clave (reglas viven en código).
- Detección automática de cambios de formato en las notificaciones de Google Wallet.
- Soporte iOS (Google Pay + `NotificationListenerService` son mecanismos específicos de Android; la app ya es Android-only).
