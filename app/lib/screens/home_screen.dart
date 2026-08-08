import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../logic/balance_calculator.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/recurring_payment_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/google_pay_listener_service.dart';
import '../services/google_pay_plugin_notification_source.dart';
import '../services/google_pay_settings.dart';
import '../services/outbox_service.dart';
import '../services/recurring_payment_service.dart';
import 'transaction_form_screen.dart';

final _currency = NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤ #,##0',
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
  final _recurringRepo = RecurringPaymentRepository(Supabase.instance.client);
  final _outbox = OutboxService(
    TransactionRepository(Supabase.instance.client),
  );
  GooglePayListenerService? _googlePayListener;
  bool _generating = false;

  late Future<(List<Account>, List<Transaction>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Started only once categories are available (needed to resolve the
    // suggested category id) — non-fatal if this fails, same pattern as the
    // account/category prefetch in HistoryScreen.initState.
    _categoryRepo.fetchAll().then((categories) {
      if (!mounted) return;
      _googlePayListener = GooglePayListenerService(
        PluginGooglePayNotificationSource(),
        Hive.box<Map>(googlePayPendingBoxName),
        categories,
      )..start();
    }).onError((e, st) {
      debugPrint('HomeScreen: failed to start Google Pay listener: $e');
    });
    _generateDueRecurringPayments();
  }

  @override
  void dispose() {
    // HomeScreen is recreated on every login (main.dart's StreamBuilder
    // swaps AppShell for LoginScreen when the session goes null, disposing
    // this state), so without this the OutboxService's connectivity
    // listener would leak and accumulate across logout/login cycles.
    _outbox.dispose();
    _googlePayListener?.dispose();
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

  Future<void> _generateDueRecurringPayments() async {
    if (_generating) return;
    _generating = true;
    try {
      final accounts = await _accountRepo.fetchAll();
      final categories = await _categoryRepo.fetchAll();
      if (!mounted) return;
      final service = RecurringPaymentService(
        _recurringRepo,
        _outbox,
        accounts,
        categories,
      );
      final count = await service.generateDue();
      if (count > 0 && mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Se generaron $count pago(s) recurrente(s) pendiente(s).',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('HomeScreen: failed to generate due recurring payments: $e');
    } finally {
      _generating = false;
    }
  }

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
          onSubmitRecurring: (r) async {
            await _recurringRepo.create(r);
            if (context.mounted) Navigator.pop(context);
            // Unlike a normal transaction, creating a template alone doesn't
            // put anything in the ledger — if fechaInicio is today or past,
            // this generates that first occurrence immediately instead of
            // leaving it stuck until the next full app restart (initState
            // already ran once before this FAB was tapped).
            await _generateDueRecurringPayments();
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
          final recientes = transactions.take(10).toList();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final a in accounts)
                      Builder(
                        builder: (context) {
                          final balance = calculateAccountBalance(
                            saldoInicial: a.saldoInicial,
                            accountId: a.id,
                            transactions: transactions,
                          );
                          final visual = accountVisual(a.tipo, scheme.primary);
                          return SizedBox(
                            width:
                                (MediaQuery.of(context).size.width - 16 * 2 - 12) /
                                2,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          visual.icon,
                                          size: 22,
                                          color: visual.color,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            a.nombre,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _currency.format(balance),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
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
