import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  void _reload() => setState(() { _future = _repo.fetchAll(); });

  Future<void> _openForm() async {
    final nombreController = TextEditingController();
    var tipo = 'gasto';
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva categoria'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombreController, decoration: const InputDecoration(labelText: 'Nombre')),
              DropdownButton<String>(
                value: tipo,
                items: const [
                  DropdownMenuItem(value: 'gasto', child: Text('Gasto')),
                  DropdownMenuItem(value: 'ingreso', child: Text('Ingreso')),
                ],
                onChanged: (v) => setDialogState(() => tipo = v!),
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
                try {
                  await _repo.create(Category(
                    id: '',
                    userId: '',
                    nombre: nombreController.text.trim(),
                    tipo: tipo,
                    icono: 'category',
                    predefinida: false,
                  ));
                } catch (e) {
                  setDialogState(() => error = 'No se pudo guardar la categoria. Revisa tu conexion e intenta de nuevo.');
                  return;
                }
                if (context.mounted) Navigator.pop(context);
                if (mounted) _reload();
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
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Category>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final categories = snapshot.data!;
          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final c = categories[i];
              return ListTile(
                title: Text(c.nombre),
                subtitle: Text(c.tipo),
                trailing: c.predefinida ? const Chip(label: Text('predefinida')) : null,
              );
            },
          );
        },
      ),
    );
  }
}
