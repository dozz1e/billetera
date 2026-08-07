import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../core/dialogs.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';
import 'transaction_form_screen.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤#,##0',
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
          if (mounted) setState(() => _accounts = a);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: Column(
        children: [
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
