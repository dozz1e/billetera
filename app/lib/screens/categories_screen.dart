import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../core/dialogs.dart';
import '../models/category.dart';
import '../repositories/category_repository.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _repo = CategoryRepository(Supabase.instance.client);
  late Future<List<Category>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAll();
  }

  void _reload() => setState(() {
    _future = _repo.fetchAll();
  });

  Future<void> _openForm() async {
    final nombreController = TextEditingController();
    var tipo = 'gasto';
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: kDialogInsetPadding,
          title: const Text('Nueva categoria'),
          content: wideDialogContent([
            TextField(
              controller: nombreController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'gasto', child: Text('Gasto')),
                DropdownMenuItem(value: 'ingreso', child: Text('Ingreso')),
              ],
              onChanged: (v) => setDialogState(() => tipo = v!),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            dialogActions(
              onCancel: () => Navigator.pop(context),
              onConfirm: () async {
                try {
                  await _repo.create(
                    Category(
                      id: '',
                      userId: '',
                      nombre: nombreController.text.trim(),
                      tipo: tipo,
                      icono: 'category',
                      predefinida: false,
                    ),
                  );
                } catch (e) {
                  setDialogState(
                    () => error =
                        'No se pudo guardar la categoria. Revisa tu conexion e intenta de nuevo.',
                  );
                  return;
                }
                if (context.mounted) Navigator.pop(context);
                if (mounted) _reload();
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _delete(Category category) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Eliminar categoria',
      message:
          'Vas a eliminar "${category.nombre}". Esta accion no se puede deshacer.',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.delete(category.id);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar la categoria. Puede tener transacciones o presupuestos asociados.',
          ),
        ),
      );
      return;
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'categories_fab',
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Category>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = snapshot.data!;
          if (categories.isEmpty) {
            return const Center(child: Text('Sin categorias todavia'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    for (final (i, c) in categories.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      Builder(
                        builder: (context) {
                          final color = c.tipo == 'ingreso'
                              ? AppColors.ingreso
                              : AppColors.gasto;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.16),
                              child: Icon(
                                c.tipo == 'ingreso'
                                    ? Icons.trending_up_rounded
                                    : Icons.sell_outlined,
                                color: color,
                              ),
                            ),
                            title: Text(c.nombre),
                            subtitle: Text(c.tipo),
                            trailing: c.predefinida
                                ? const Chip(label: Text('predefinida'))
                                : IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Eliminar',
                                    color: Theme.of(context).colorScheme.error,
                                    onPressed: () => _delete(c),
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
    );
  }
}
