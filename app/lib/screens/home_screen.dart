import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/balance_calculator.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';
import 'new_transaction_screen.dart';

final _currency = NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _accountRepo = AccountRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);

  late Future<(List<Account>, List<Transaction>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Account>, List<Transaction>)> _load() async {
    final accounts = await _accountRepo.fetchAll();
    final transactions = await _transactionRepo.fetchAll();
    return (accounts, transactions);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openNewTransaction() async {
    final accounts = await _accountRepo.fetchAll();
    final categories = await _categoryRepo.fetchAll();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewTransactionScreen(
          accounts: accounts.where((a) => a.activo).toList(),
          categories: categories,
          // NewTransactionScreen._submit() (see new_transaction_screen.dart,
          // fixed in commit 8bd23f0) already wraps `await widget.onSubmit(...)`
          // in a try/catch that shows an inline error and does NOT pop the
          // navigator on failure. So this callback intentionally does not
          // catch here: if _transactionRepo.create throws, the exception
          // propagates unchanged to that catch, `Navigator.pop` below is
          // skipped (it's unreachable once the await throws), and the user
          // sees the inline error instead of the screen silently popping.
          onSubmit: (t) async {
            await _transactionRepo.create(t);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billetera')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewTransaction,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<(List<Account>, List<Transaction>)>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final (accounts, transactions) = snapshot.data!;
          final total = calculateTotalBalance(accounts: accounts, allTransactions: transactions);
          final recientes = transactions.take(10).toList();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Saldo total', style: Theme.of(context).textTheme.titleMedium),
                Text(_currency.format(total), style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: accounts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final a = accounts[i];
                      final balance = calculateAccountBalance(
                        saldoInicial: a.saldoInicial,
                        accountId: a.id,
                        transactions: transactions,
                      );
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(a.nombre, style: Theme.of(context).textTheme.labelLarge),
                              Text(_currency.format(balance)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Text('Transacciones recientes', style: Theme.of(context).textTheme.titleMedium),
                ...recientes.map((t) => ListTile(
                      leading: Icon(switch (t.tipo) {
                        TransactionType.ingreso => Icons.arrow_downward,
                        TransactionType.gasto => Icons.arrow_upward,
                        TransactionType.transferencia => Icons.swap_horiz,
                      }),
                      title: Text(_currency.format(t.monto)),
                      subtitle: Text(t.nota ?? t.tipo.name),
                      trailing: Text(DateFormat('dd/MM').format(t.fecha)),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}
