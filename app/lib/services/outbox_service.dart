import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/transaction.dart';
import '../repositories/transaction_repository.dart';

class OutboxService {
  OutboxService(this._repository) {
    _box = Hive.box<Map>('outbox');
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) flush();
    });
  }

  final TransactionRepository _repository;
  late final Box<Map> _box;
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  final _uuid = const Uuid();

  int get pendingCount => _box.length;

  Future<void> create(Transaction transaction) async {
    try {
      await _repository.create(transaction);
    } catch (_) {
      await _box.put(_uuid.v4(), transaction.toInsertJson());
    }
  }

  Future<void> flush() async {
    for (final key in _box.keys.toList()) {
      final json = Map<String, dynamic>.from(_box.get(key)!);
      try {
        final transaction = Transaction(
          id: '',
          userId: '',
          accountId: json['account_id'] as String,
          categoryId: json['category_id'] as String?,
          accountDestinoId: json['account_destino_id'] as String?,
          tipo: transactionTypeFromString(json['tipo'] as String),
          monto: (json['monto'] as num).toDouble(),
          fecha: DateTime.parse(json['fecha'] as String),
          nota: json['nota'] as String?,
        );
        await _repository.create(transaction);
        await _box.delete(key);
      } catch (_) {
        // stays queued, retried on the next connectivity change
      }
    }
  }

  /// Cancels the connectivity listener. Must be called when the owning
  /// widget (HomeScreen) is disposed — e.g. on logout — so a new
  /// OutboxService created on the next login doesn't accumulate an extra
  /// leaked listener that would flush concurrently with the new instance.
  void dispose() {
    _connectivitySubscription.cancel();
  }
}
