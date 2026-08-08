import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({
    super.key,
    required this.accounts,
    required this.categories,
    required this.onSubmit,
    this.initial,
  });

  final List<Account> accounts;
  final List<Category> categories;
  final Future<void> Function(Transaction) onSubmit;
  final Transaction? initial;

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  late TransactionType _tipo;
  String? _accountId;
  String? _accountDestinoId;
  String? _categoryId;
  late DateTime _fecha;
  final _montoController = TextEditingController();
  final _notaController = TextEditingController();
  String? _error;

  bool get _isEditing => widget.initial != null;

  List<Category> get _categoriasFiltradas => widget.categories
      .where((c) => c.tipo == (_tipo == TransactionType.ingreso ? 'ingreso' : 'gasto'))
      .toList();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _tipo = initial?.tipo ?? TransactionType.gasto;
    _fecha = initial?.fecha ?? DateTime.now();
    _accountDestinoId = initial?.accountDestinoId;
    if (initial != null) {
      _montoController.text = initial.monto == initial.monto.roundToDouble()
          ? initial.monto.toStringAsFixed(0)
          : initial.monto.toString();
      _notaController.text = initial.nota ?? '';
      _accountId = initial.accountId;
      _categoryId = initial.categoryId;
    } else {
      if (widget.accounts.isNotEmpty) _accountId = widget.accounts.first.id;
      if (_categoriasFiltradas.isNotEmpty) _categoryId = _categoriasFiltradas.first.id;
    }
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
      id: widget.initial?.id ?? '',
      userId: widget.initial?.userId ?? '',
      accountId: _accountId!,
      categoryId: _tipo == TransactionType.transferencia ? null : _categoryId,
      accountDestinoId: _tipo == TransactionType.transferencia ? _accountDestinoId : null,
      tipo: _tipo,
      monto: monto,
      fecha: _fecha,
      nota: _notaController.text.trim().isEmpty ? null : _notaController.text.trim(),
    );

    try {
      await widget.onSubmit(transaction);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo guardar la transaccion. Revisa tu conexion e intenta de nuevo.');
      }
    }
  }

  Future<void> _pickFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null && mounted) setState(() => _fecha = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar transaccion' : 'Nueva transaccion')),
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
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Fecha: '),
                    Text(_dateFormat.format(_fecha)),
                  ],
                ),
                TextButton(
                  key: const Key('fecha_button'),
                  onPressed: _pickFecha,
                  child: const Text('Cambiar'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton(onPressed: _submit, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
