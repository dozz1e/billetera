import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/account.dart';
import '../services/google_pay_notification_source.dart';
import '../services/google_pay_plugin_notification_source.dart';
import '../services/google_pay_settings.dart';

class GooglePaySettingsScreen extends StatefulWidget {
  const GooglePaySettingsScreen({super.key, required this.accounts});

  final List<Account> accounts;

  @override
  State<GooglePaySettingsScreen> createState() => _GooglePaySettingsScreenState();
}

class _GooglePaySettingsScreenState extends State<GooglePaySettingsScreen> {
  final GooglePayNotificationSource _source = PluginGooglePayNotificationSource();
  late final GooglePaySettings _settings = GooglePaySettings(Hive.box(googlePaySettingsBoxName));

  bool _hasPermission = false;
  String? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _selectedAccountId = _settings.defaultAccountId;
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final granted = await _source.hasPermission();
    if (mounted) setState(() => _hasPermission = granted);
  }

  Future<void> _save() async {
    await _settings.setDefaultAccountId(_selectedAccountId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final activeAccounts = widget.accounts.where((a) => a.activo).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Google Pay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acceso a notificaciones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La app necesita leer las notificaciones de Google Wallet para armar la cola de registros pendientes. Se activa en Ajustes del sistema.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _hasPermission ? Icons.check_circle : Icons.cancel_outlined,
                        color: _hasPermission ? Colors.green : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(_hasPermission ? 'Activado' : 'No activado'),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await _source.requestPermission();
                          _refreshPermission();
                        },
                        child: const Text('Activar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cuenta por defecto',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Los registros pendientes de Google Pay se insertan en esta cuenta.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedAccountId,
                    decoration: const InputDecoration(labelText: 'Cuenta'),
                    items: activeAccounts
                        .map((a) => DropdownMenuItem(value: a.id, child: Text(a.nombre)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Guardar')),
        ],
      ),
    );
  }
}
