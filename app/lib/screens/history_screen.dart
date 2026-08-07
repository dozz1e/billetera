import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../core/dialogs.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/pending_google_pay_record.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/google_pay_settings.dart';
import 'transaction_form_screen.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤ #,##0',
);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _accountRepo = AccountRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);
  final _pendingBox = Hive.box<Map>(googlePayPendingBoxName);
  final _settingsBox = Hive.box(googlePaySettingsBoxName);
  late final _googlePaySettings = GooglePaySettings(_settingsBox);

  List<Account> _accounts = [];
  List<Category> _categories = [];
  String? _accountFilter;
  String? _categoryFilter;
  TransactionType? _tipoFilter;
  late Future<List<Transaction>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Non-fatal to the screen if either fetch fails: the corresponding
    // dropdown just stays without options to filter by, so failures are
    // logged and swallowed rather than surfaced as a user-facing error.
    // Both the setState and the error handler are mounted-guarded since
    // this widget may be disposed before either future resolves.
    _accountRepo
        .fetchAll()
        .then((a) {
          if (mounted) {
            setState(() {
              _accounts = a;
            });
          }
        })
        .onError((e, st) {
          debugPrint('HistoryScreen: failed to load accounts: $e');
        });
    _categoryRepo
        .fetchAll()
        .then((c) {
          if (mounted) setState(() => _categories = c);
        })
        .onError((e, st) {
          debugPrint('HistoryScreen: failed to load categories: $e');
        });
  }

  Future<List<Transaction>> _load() => _transactionRepo.fetchAll(
    accountId: _accountFilter,
    categoryId: _categoryFilter,
    tipo: _tipoFilter,
  );

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _openEdit(Transaction t) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionFormScreen(
          accounts: _accounts,
          categories: _categories,
          initial: t,
          onSubmit: (updated) async {
            await _transactionRepo.update(t.id, updated.toInsertJson());
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _delete(Transaction t) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Eliminar transaccion',
      message:
          'Vas a eliminar la transaccion de ${_currency.format(t.monto)} del ${DateFormat('dd/MM/yyyy').format(t.fecha)}. Esta accion no se puede deshacer.',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _transactionRepo.delete(t.id);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo eliminar la transaccion. Revisa tu conexion e intenta de nuevo.'),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }

  // Whether the Google Pay card should even offer inserting at all — purely
  // "is anything configured", not "is that account still valid". Whether the
  // configured account is still an active account is checked with a fresh
  // fetch inside _insertPendingCore, on tap, rather than against this
  // screen's `_accounts` snapshot: `_accounts` is fetched once in initState
  // and AppShell keeps HistoryScreen alive in an IndexedStack, so initState
  // never runs again on tab switch — a stale `_accounts` here would
  // otherwise permanently miss accounts created/configured after app start.
  String? get _defaultAccountId => _googlePaySettings.defaultAccountId;

  // Inserts a single pending record without reloading the transaction list
  // afterwards — used by both _insertPending (which reloads immediately) and
  // _insertAllPending (which reloads once after the whole batch, instead of
  // once per record).
  //
  // `accounts`: the fresh account list to validate the configured default
  // account against. When omitted, fetched here (used by the single-record
  // _insertPending path, which needs its own fresh fetch). _insertAllPending
  // fetches it once for the whole batch and passes it down, instead of every
  // iteration doing its own redundant Supabase round-trip.
  Future<void> _insertPendingCore(PendingGooglePayRecord record, {List<Account>? accounts}) async {
    final accountId = _defaultAccountId;
    if (accountId == null) return;

    final messenger = ScaffoldMessenger.of(context);

    if (record.categoriaSugeridaId == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "No se pudo determinar una categoría para este registro. Revisa que la categoría 'Otros gastos' exista en Categorias.",
          ),
        ),
      );
      return;
    }

    List<Account> freshAccounts;
    if (accounts != null) {
      freshAccounts = accounts;
    } else {
      try {
        freshAccounts = await _accountRepo.fetchAll();
      } catch (e) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No se pudo insertar la transaccion. Revisa tu conexion e intenta de nuevo.'),
          ),
        );
        return;
      }
    }
    final isActive = freshAccounts.any((a) => a.id == accountId && a.activo);
    if (!isActive) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'La cuenta configurada para Google Pay ya no está disponible. Actualízala en Cuentas.',
          ),
        ),
      );
      return;
    }

    try {
      await _transactionRepo.create(
        Transaction(
          id: '',
          userId: '',
          accountId: accountId,
          categoryId: record.categoriaSugeridaId,
          tipo: TransactionType.gasto,
          monto: record.monto,
          fecha: record.fecha,
          nota: record.comercioTexto,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo insertar la transaccion. Revisa tu conexion e intenta de nuevo.'),
        ),
      );
      return;
    }
    // Keep the record (instead of deleting it) so its key still satisfies
    // GooglePayListenerService's dedupe check (`_box.containsKey`) — if
    // Android re-posts the same notification, it won't be re-inserted as a
    // new pending record. The card's `estado == 'pendiente'` filter already
    // hides anything not pending, so this doesn't change what's shown.
    await _pendingBox.put(record.id, record.copyWith(estado: 'insertado').toMap());
  }

  Future<void> _insertPending(PendingGooglePayRecord record) async {
    await _insertPendingCore(record);
    if (mounted) _reload();
  }

  Future<void> _discardPending(PendingGooglePayRecord record) async {
    await _pendingBox.put(record.id, record.copyWith(estado: 'descartado').toMap());
  }

  Future<void> _insertAllPending(List<PendingGooglePayRecord> records) async {
    final messenger = ScaffoldMessenger.of(context);
    List<Account> accounts;
    try {
      accounts = await _accountRepo.fetchAll();
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo insertar la transaccion. Revisa tu conexion e intenta de nuevo.'),
        ),
      );
      return;
    }
    for (final record in records) {
      await _insertPendingCore(record, accounts: accounts);
    }
    if (mounted) _reload();
  }

  // Reacts to both the pending-records box (new/discarded/inserted records)
  // and the settings box (default account configured/changed elsewhere,
  // e.g. in GooglePaySettingsScreen) — needed because AppShell keeps
  // HistoryScreen alive in an IndexedStack, so it doesn't naturally rebuild
  // on tab switch, and the card reads `_defaultAccountId` (backed by the
  // settings box) on every build.
  Widget _buildGooglePayCard() {
    return ValueListenableBuilder<Box>(
      valueListenable: _settingsBox.listenable(),
      builder: (context, settingsBox, _) => ValueListenableBuilder<Box<Map>>(
        valueListenable: _pendingBox.listenable(),
        builder: (context, box, _) {
          final pendientes = box.values
              .map((m) => PendingGooglePayRecord.fromMap(m))
              .where((r) => r.estado == 'pendiente')
              .toList();
          if (pendientes.isEmpty) return const SizedBox.shrink();

          final accountId = _defaultAccountId;

          return Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Registros de Google Pay',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('${pendientes.length} registros pendientes de insertar'),
                  if (accountId == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Configura una cuenta por defecto para Google Pay en Cuentas.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 8),
                  for (final record in pendientes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_currency.format(record.monto)),
                      subtitle: Text(record.comercioTexto),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check),
                            tooltip: 'Insertar',
                            onPressed: accountId == null ? null : () => _insertPending(record),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Descartar',
                            onPressed: () => _discardPending(record),
                          ),
                        ],
                      ),
                    ),
                  if (accountId != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _insertAllPending(pendientes),
                        child: const Text('Insertar todos'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: Column(
        children: [
          _buildGooglePayCard(),
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                children: [
                  DropdownButton<String?>(
                    hint: const Text('Cuenta'),
                    value: _accountFilter,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todas')),
                      ..._accounts.map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.nombre),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      _accountFilter = v;
                      _reload();
                    },
                  ),
                  DropdownButton<String?>(
                    hint: const Text('Categoria'),
                    value: _categoryFilter,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todas')),
                      ..._categories.map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.nombre),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      _categoryFilter = v;
                      _reload();
                    },
                  ),
                  DropdownButton<TransactionType?>(
                    hint: const Text('Tipo'),
                    value: _tipoFilter,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(
                        value: TransactionType.ingreso,
                        child: Text('Ingreso'),
                      ),
                      DropdownMenuItem(
                        value: TransactionType.gasto,
                        child: Text('Gasto'),
                      ),
                      DropdownMenuItem(
                        value: TransactionType.transferencia,
                        child: Text('Transferencia'),
                      ),
                    ],
                    onChanged: (v) {
                      _tipoFilter = v;
                      _reload();
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Transaction>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final transactions = snapshot.data!;
                if (transactions.isEmpty) {
                  return const Center(child: Text('Sin transacciones'));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Card(
                      child: Column(
                        children: [
                          for (final (i, t) in transactions.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            Builder(
                              builder: (context) {
                                final visual = transactionVisual(t.tipo);
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: visual.color.withValues(
                                      alpha: 0.16,
                                    ),
                                    child: Icon(
                                      visual.icon,
                                      color: visual.color,
                                    ),
                                  ),
                                  title: Text(_currency.format(t.monto)),
                                  subtitle: Text(
                                    '${DateFormat('dd/MM/yyyy').format(t.fecha)} · ${t.nota ?? t.tipo.name}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: 'Editar',
                                        onPressed: () => _openEdit(t),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: 'Eliminar',
                                        color: Theme.of(context).colorScheme.error,
                                        onPressed: () => _delete(t),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
