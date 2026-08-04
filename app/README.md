# Billetera

App personal de registro de ingresos, gastos, transferencias, cuentas y graficas.

## Setup

1. Copiar `env.json.example` a `env.json` y completar con la URL y anon key del proyecto Supabase (ver `supabase/migrations/0001_init.sql`).
2. `flutter pub get`
3. Crear tu usuario en el dashboard de Supabase (Authentication > Users > Add user), o habilitar signup y registrarte desde la app si se agrega esa pantalla mas adelante.

## Correr en desarrollo

```bash
flutter run --dart-define-from-file=env.json
```

## Build de release (APK para instalar en el celular)

```bash
flutter build apk --release --dart-define-from-file=env.json
```

APK queda en `build/app/outputs/flutter-apk/app-release.apk`. Se instala transfiriendolo al telefono y abriendolo (requiere permitir "instalar apps de origenes desconocidos" para el instalador usado).

## Tests

```bash
flutter test
```
