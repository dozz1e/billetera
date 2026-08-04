enum TransactionType { ingreso, gasto, transferencia }

TransactionType transactionTypeFromString(String value) {
  switch (value) {
    case 'ingreso':
      return TransactionType.ingreso;
    case 'gasto':
      return TransactionType.gasto;
    case 'transferencia':
      return TransactionType.transferencia;
    default:
      throw ArgumentError('Unknown transaction type: $value');
  }
}

String transactionTypeToString(TransactionType type) => type.name;

class Transaction {
  const Transaction({
    required this.id,
    required this.userId,
    required this.accountId,
    this.categoryId,
    this.accountDestinoId,
    required this.tipo,
    required this.monto,
    required this.fecha,
    this.nota,
  });

  final String id;
  final String userId;
  final String accountId;
  final String? categoryId;
  final String? accountDestinoId;
  final TransactionType tipo;
  final double monto;
  final DateTime fecha;
  final String? nota;

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        accountId: json['account_id'] as String,
        categoryId: json['category_id'] as String?,
        accountDestinoId: json['account_destino_id'] as String?,
        tipo: transactionTypeFromString(json['tipo'] as String),
        monto: (json['monto'] as num).toDouble(),
        fecha: DateTime.parse(json['fecha'] as String),
        nota: json['nota'] as String?,
      );

  Map<String, dynamic> toInsertJson() => {
        'account_id': accountId,
        'category_id': categoryId,
        'account_destino_id': accountDestinoId,
        'tipo': transactionTypeToString(tipo),
        'monto': monto,
        'fecha': fecha.toIso8601String().split('T').first,
        'nota': nota,
      };
}
