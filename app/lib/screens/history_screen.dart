import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';

final _currency = NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0);

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
    _accountRepo.fetchAll().then((a) {
      if (mounted) setState(() => _accounts = a);
    }).onError((e, st) {
      debugPrint('HistoryScreen: failed to load accounts: $e');
    });
    _categoryRepo.fetchAll().then((c) {
      if (mounted) setState(() => _categories = c);
    }).onError((e, st) {
      debugPrint('HistoryScreen: failed to load categories: $e');
    });
  }

  Future<List<Transaction>> _load() => _transactionRepo.fetchAll(
        accountId: _accountFilter,
        categoryId: _categoryFilter,
        tipo: _tipoFilter,
      );

  void _reload() => setState(() { _future = _load(); });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                DropdownButton<String?>(
                  hint: const Text('Cuenta'),
                  value: _accountFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    ..._accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))),
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
                    ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))),
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
                    DropdownMenuItem(value: TransactionType.ingreso, child: Text('Ingreso')),
                    DropdownMenuItem(value: TransactionType.gasto, child: Text('Gasto')),
                    DropdownMenuItem(value: TransactionType.transferencia, child: Text('Transferencia')),
                  ],
                  onChanged: (v) {
                    _tipoFilter = v;
                    _reload();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Transaction>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final transactions = snapshot.data!;
                if (transactions.isEmpty) return const Center(child: Text('Sin transacciones'));
                return ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, i) {
                    final t = transactions[i];
                    return ListTile(
                      title: Text(_currency.format(t.monto)),
                      subtitle: Text(t.nota ?? t.tipo.name),
                      trailing: Text(DateFormat('dd/MM/yyyy').format(t.fecha)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
