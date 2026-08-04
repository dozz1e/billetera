import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';

class NewTransactionScreen extends StatefulWidget {
  const NewTransactionScreen({
    super.key,
    required this.accounts,
    required this.categories,
    required this.onSubmit,
  });

  final List<Account> accounts;
  final List<Category> categories;
  final Future<void> Function(Transaction) onSubmit;

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  TransactionType _tipo = TransactionType.gasto;
  String? _accountId;
  String? _accountDestinoId;
  String? _categoryId;
  final DateTime _fecha = DateTime.now();
  final _montoController = TextEditingController();
  final _notaController = TextEditingController();
  String? _error;

  List<Category> get _categoriasFiltradas => widget.categories
      .where((c) => c.tipo == (_tipo == TransactionType.ingreso ? 'ingreso' : 'gasto'))
      .toList();

  @override
  void initState() {
    super.initState();
    if (widget.accounts.isNotEmpty) _accountId = widget.accounts.first.id;
    if (_categoriasFiltradas.isNotEmpty) _categoryId = _categoriasFiltradas.first.id;
  }

  @override
  void dispose() {
    _montoController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final monto = double.tryParse(_montoController.text);
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Monto invalido');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Selecciona una cuenta');
      return;
    }
    if (_tipo == TransactionType.transferencia) {
      if (_accountDestinoId == null || _accountDestinoId == _accountId) {
        setState(() => _error = 'Selecciona una cuenta destino distinta');
        return;
      }
    } else if (_categoryId == null) {
      setState(() => _error = 'Selecciona una categoria');
      return;
    }

    final transaction = Transaction(
      id: '',
      userId: '',
      accountId: _accountId!,
      categoryId: _tipo == TransactionType.transferencia ? null : _categoryId,
      accountDestinoId: _tipo == TransactionType.transferencia ? _accountDestinoId : null,
      tipo: _tipo,
      monto: monto,
      fecha: _fecha,
      nota: _notaController.text.trim().isEmpty ? null : _notaController.text.trim(),
    );

    await widget.onSubmit(transaction);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva transaccion')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(value: TransactionType.gasto, label: Text('Gasto')),
                ButtonSegment(value: TransactionType.ingreso, label: Text('Ingreso')),
                ButtonSegment(value: TransactionType.transferencia, label: Text('Transferencia')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() {
                _tipo = s.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('monto_field'),
              controller: _montoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Cuenta'),
              items: widget.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))).toList(),
              onChanged: (v) => setState(() => _accountId = v),
            ),
            if (_tipo == TransactionType.transferencia) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _accountDestinoId,
                decoration: const InputDecoration(labelText: 'Cuenta destino'),
                items: widget.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre))).toList(),
                onChanged: (v) => setState(() => _accountDestinoId = v),
              ),
            ] else ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: _categoriasFiltradas.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))).toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(controller: _notaController, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(onPressed: _submit, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
