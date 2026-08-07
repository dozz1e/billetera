import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../logic/balance_calculator.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/outbox_service.dart';
import 'transaction_form_screen.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _accountRepo = AccountRepository(Supabase.instance.client);
  final _categoryRepo = CategoryRepository(Supabase.instance.client);
  final _transactionRepo = TransactionRepository(Supabase.instance.client);
  final _outbox = OutboxService(
    TransactionRepository(Supabase.instance.client),
  );

  late Future<(List<Account>, List<Transaction>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    // HomeScreen is recreated on every login (main.dart's StreamBuilder
    // swaps AppShell for LoginScreen when the session goes null, disposing
    // this state), so without this the OutboxService's connectivity
    // listener would leak and accumulate across logout/login cycles.
    _outbox.dispose();
    super.dispose();
  }

  Future<(List<Account>, List<Transaction>)> _load() async {
    final accounts = await _accountRepo.fetchAll();
    final transactions = await _transactionRepo.fetchAll();
    return (accounts, transactions);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _openNewTransaction() async {
    final accounts = await _accountRepo.fetchAll();
    final categories = await _categoryRepo.fetchAll();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionFormScreen(
          accounts: accounts.where((a) => a.activo).toList(),
          categories: categories,
          // OutboxService.create() deliberately swallows network-failure
          // exceptions and queues the transaction locally instead of
          // rethrowing (offline-first by design, see outbox_service.dart).
          // So unlike the old direct _transactionRepo.create(t) call, a
          // network failure here will NOT reach
          // TransactionFormScreen._submit()'s error-surfacing catch: it
          // queues silently and the form closes normally below, same as a
          // successful write. The pendingCount check after this screen
          // closes is what tells the user their transaction was queued
          // rather than actually saved.
          onSubmit: (t) async {
            await _outbox.create(t);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
    if (!mounted) return;
    _reload();
    final pending = _outbox.pendingCount;
    if (pending > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$pending transacción(es) pendiente(s) de sincronizar'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Billetera')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_fab',
        onPressed: _openNewTransaction,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<(List<Account>, List<Transaction>)>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (accounts, transactions) = snapshot.data!;
          final total = calculateTotalBalance(
            accounts: accounts,
            allTransactions: transactions,
          );
          final recientes = transactions.take(10).toList();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: scheme.primary.withValues(
                            alpha: 0.16,
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_rounded,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Saldo total',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              _currency.format(total),
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 92,
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
                      final visual = accountVisual(a.tipo, scheme.primary);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    visual.icon,
                                    size: 16,
                                    color: visual.color,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    a.nombre,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(_currency.format(balance)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'Transacciones recientes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Card(
                  child: recientes.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Sin transacciones todavia'),
                        )
                      : Column(
                          children: [
                            for (final (i, t) in recientes.indexed) ...[
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
                                    subtitle: Text(t.nota ?? t.tipo.name),
                                    trailing: Text(
                                      DateFormat('dd/MM').format(t.fecha),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
