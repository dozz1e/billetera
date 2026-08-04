import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account.dart';
import '../repositories/account_repository.dart';
import 'categories_screen.dart';

const _tipos = ['efectivo', 'banco', 'credito', 'billetera_digital'];

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _repo = AccountRepository(Supabase.instance.client);
  late Future<List<Account>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAll();
  }

  void _reload() => setState(() => _future = _repo.fetchAll());

  Future<void> _openForm({Account? account}) async {
    final nombreController = TextEditingController(text: account?.nombre ?? '');
    final saldoController = TextEditingController(text: account?.saldoInicial.toString() ?? '0');
    var tipo = account?.tipo ?? _tipos.first;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(account == null ? 'Nueva cuenta' : 'Editar cuenta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombreController, decoration: const InputDecoration(labelText: 'Nombre')),
              DropdownButton<String>(
                value: tipo,
                items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setDialogState(() => tipo = v!),
              ),
              TextField(
                controller: saldoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Saldo inicial'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final saldo = double.tryParse(saldoController.text) ?? 0;
                try {
                  if (account == null) {
                    await _repo.create(Account(
                      id: '',
                      userId: '',
                      nombre: nombreController.text.trim(),
                      tipo: tipo,
                      saldoInicial: saldo,
                      activo: true,
                    ));
                  } else {
                    await _repo.update(account.id, {
                      'nombre': nombreController.text.trim(),
                      'tipo': tipo,
                      'saldo_inicial': saldo,
                    });
                  }
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) _reload();
                } catch (e) {
                  setDialogState(() => error = 'No se pudo guardar la cuenta. Revisa tu conexion e intenta de nuevo.');
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Categorias',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CategoriesScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Account>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final accounts = snapshot.data!;
          if (accounts.isEmpty) return const Center(child: Text('Sin cuentas todavia'));
          return ListView.builder(
            itemCount: accounts.length,
            itemBuilder: (context, i) {
              final a = accounts[i];
              return ListTile(
                title: Text(a.nombre),
                subtitle: Text(a.tipo),
                trailing: a.activo
                    ? IconButton(
                        icon: const Icon(Icons.archive_outlined),
                        tooltip: 'Desactivar',
                        onPressed: () async {
                          await _repo.update(a.id, {'activo': false});
                          _reload();
                        },
                      )
                    : const Text('inactiva'),
                onTap: () => _openForm(account: a),
              );
            },
          );
        },
      ),
    );
  }
}
