# Detalle de cuenta — Diseño

Fecha: 2026-08-07
Estado: Aprobado

## Propósito

Al tocar una cuenta (tarjeta en Home o fila en Cuentas) se abre una pantalla de detalle: saldo actual, un gráfico de la evolución del saldo, un selector de periodo (día/semana/mes/6 meses) que cambia la ventana del gráfico, y el % de variación del saldo dentro de ese periodo. Separado (sin relación funcional): los íconos de la barra inferior pasan de un solo tono a un color distinto cada uno.

## Decisiones

- **Ambos puntos de entrada abren el detalle:** las tarjetas de cuenta en `HomeScreen` (hoy sin acción al tocar) y las filas en `AccountsScreen` (hoy abren editar). Editar se mueve a un botón dentro del detalle; tocar la fila en Cuentas ahora abre el detalle en vez de editar directamente.
- **Gráfico: línea de saldo en el tiempo**, mismo tipo que "Evolución del saldo" en `ChartsScreen`, pero filtrado a esta cuenta y a la ventana del periodo elegido.
- **Periodo "6 meses" fijo** (no hay sub-selector de cantidad) — mismo criterio que "Ingresos vs gastos (6 meses)" ya existente en Gráficas.
- **% de variación** = `(saldo_final − saldo_inicio_periodo) / saldo_inicio_periodo × 100`. Si el saldo al inicio del periodo es `0`, se muestra "—" en vez de dividir por cero (variación no definida cuando se parte de cero).
- **Transferencias cuentan en ambos lados:** una transferencia hacia esta cuenta suma, una transferencia desde esta cuenta resta — mismo criterio ya usado en `calculateAccountBalance`.
- **Sin marca de tiempo intradía:** las transacciones en este codebase solo tienen fecha (no hora), así que el periodo "Día" puede mostrar el gráfico prácticamente plano si no hubo movimientos hoy — es una limitación de los datos existentes, no algo que este feature deba resolver.
- **Fuera de alcance:** editar el periodo con rango custom (fechas arbitrarias), exportar el gráfico, comparar dos cuentas a la vez.

## Lógica pura

Nuevo archivo `app/lib/logic/account_period_summary.dart`:

```
class AccountBalancePoint {
  fecha: DateTime
  saldo: double
}

class AccountPeriodSummary {
  points: List<AccountBalancePoint>       // incluye un punto ancla en `from` con el saldo de inicio de periodo
  saldoInicio: double                     // saldo de la cuenta justo antes de `from`
  saldoFinal: double                      // saldo de la cuenta al llegar a `hasta`
  variacionPorcentual: double?            // null si saldoInicio == 0
}

AccountPeriodSummary accountBalanceForPeriod({
  required Account account,
  required List<Transaction> transactions,
  required DateTime from,
  required DateTime hasta,
})
```

Algoritmo:
1. Filtra `transactions` a las que tocan esta cuenta (`accountId == account.id || accountDestinoId == account.id`), ordena por `fecha` ascendente.
2. Recorre las transacciones con `fecha < from` acumulando sobre `account.saldoInicial` (mismo signo que `calculateAccountBalance`: ingreso/transferencia-entrante suma, gasto/transferencia-saliente resta) → resultado es `saldoInicio`.
3. Agrega un `AccountBalancePoint(fecha: from, saldo: saldoInicio)` como ancla del gráfico.
4. Continúa el acumulado por las transacciones con `from <= fecha <= hasta`, agregando un punto por cada una. El acumulado al terminar es `saldoFinal`.
5. `variacionPorcentual = saldoInicio == 0 ? null : (saldoFinal - saldoInicio) / saldoInicio * 100`.

Los límites de cada periodo (calculados por el caller, `hasta` siempre "ahora"):
- **Día:** `from` = medianoche de hoy.
- **Semana:** `from` = ahora menos 7 días.
- **Mes:** `from` = día 1 del mes actual.
- **6 meses:** `from` = `DateTime(hoy.year, hoy.month - 6, 1)` — mismo cálculo que `monthlyIncomeVsExpense` ya existente.

## Pantalla

`AccountDetailScreen` (`app/lib/screens/account_detail_screen.dart`):

- Recibe `account: Account` por constructor (mismo patrón que `GoalDetailScreen`: la pantalla que la abre ya tiene la cuenta cargada), pero la guarda en una variable de estado mutable `_account` — se reasigna después de editar, para que el saldo/nombre en pantalla no queden desactualizados sin tener que salir y volver a entrar.
- Trae sus propias transacciones en `initState` vía `TransactionRepository.fetchAll()` sin filtro (necesita ver transferencias hacia/desde la cuenta, que un filtro por `account_id` no capturaría del lado destino).
- **AppBar:** nombre de `_account`, botón editar (ícono lápiz) que llama a un callback `onEdit: Future<void> Function()` recibido por constructor — `AccountsScreen`/`HomeScreen` lo implementan abriendo su propio `_openForm(account: ...)` (el mismo diálogo que ya existe). Al volver de ese diálogo, `AccountDetailScreen` vuelve a pedir la cuenta (`AccountRepository.fetchAll()`, busca por `id`) y hace `setState(() => _account = actualizada)` — mismo patrón de refresco que el resto de la app usa tras editar.
- **Card de saldo:** ícono de tipo de cuenta (`accountVisual`), saldo actual (`calculateAccountBalance` con todas las transacciones, no las del periodo).
- **Selector de periodo:** `SegmentedButton<Periodo>` con 4 opciones (Día, Semana, Mes, 6 meses), default "Mes". Cambiar de segmento recalcula `accountBalanceForPeriod` con el `from` correspondiente y hace `setState`.
- **% de variación:** texto junto al selector o bajo el gráfico, verde si `>= 0`, rojo si `< 0` (mismo criterio de color que `AppColors.ingreso`/`AppColors.gasto`), "—" si es `null`.
- **Gráfico:** `LineChart` de `fl_chart` con `AccountPeriodSummary.points`, mismo estilo que "Evolución del saldo" en `ChartsScreen` (línea recta sin curva, color `Theme.of(context).colorScheme.primary`, sin puntos). Si `points.length <= 1`, mensaje "Sin movimientos en este periodo" en vez del gráfico (evita renderizar una línea sin datos).

## Wiring

- El diálogo de alta/edición que hoy vive como `_openForm` dentro de `_AccountsScreenState` se extrae a una función top-level en `accounts_screen.dart`: `Future<void> showAccountFormDialog(BuildContext context, AccountRepository repo, {Account? account})`. Es la misma lógica que ya existe (campos nombre/tipo/saldo inicial, `dialogActions`, manejo de error), solo deja de ser un método privado del State para poder llamarse también desde `HomeScreen`. `AccountsScreen._openForm` pasa a ser un wrapper de una línea que llama a esta función y luego `_reload()`.
- `HomeScreen`: cada tarjeta de cuenta (dentro del `Wrap`) se envuelve en `InkWell` (con el mismo `borderRadius` que el `Card` para que el ripple no se salga) que hace `Navigator.push` a `AccountDetailScreen(account: a, onEdit: () => showAccountFormDialog(context, _accountRepo, account: a))`.
- `AccountsScreen`: el `ListTile.onTap` cambia de `_openForm(account: a)` a `Navigator.push` a `AccountDetailScreen(account: a, onEdit: () => showAccountFormDialog(context, _repo, account: a))`. Al volver del `Navigator.push`, `AccountsScreen._reload()` (para que la lista refleje cambios hechos desde el detalle).

## Colores del menú inferior

`app_shell.dart`: cada `NavigationDestination` envuelve su ícono en `Icon(..., color: AppColors.chartPalette[i])`, tomando los primeros 6 colores de la paleta ya existente (`chartPalette` tiene 8). El color se aplica siempre (seleccionado y no seleccionado) — la selección ya se distingue por la píldora de fondo y el label en negrita que `NavigationBar` dibuja por defecto, así que no hace falta un segundo estado de color.

## Testing

- **Unit tests** para `accountBalanceForPeriod`: saldo de inicio correcto con transacciones antes del periodo, transferencia entrante/saliente cuenta con el signo correcto, `variacionPorcentual` null cuando `saldoInicio == 0`, punto ancla presente incluso sin movimientos en el periodo, orden cronológico correcto de los puntos.
- **Sin widget test** para `AccountDetailScreen` — mismo criterio que el resto de pantallas de detalle/CRUD de este codebase (`GoalDetailScreen`, `PersonDebtsScreen`, etc. no tienen test de pantalla).

## Fuera de alcance (explícito)

- Rango de fechas custom.
- Exportar/compartir el gráfico.
- Comparar cuentas entre sí en el mismo gráfico.
- Editar el periodo "6 meses" a otra cantidad.
