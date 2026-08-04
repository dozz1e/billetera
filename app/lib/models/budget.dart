class Budget {
  const Budget({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.mes,
    required this.montoLimite,
  });

  final String id;
  final String userId;
  final String categoryId;
  final DateTime mes;
  final double montoLimite;

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        categoryId: json['category_id'] as String,
        mes: DateTime.parse(json['mes'] as String),
        montoLimite: (json['monto_limite'] as num).toDouble(),
      );

  Map<String, dynamic> toInsertJson() => {
        'category_id': categoryId,
        'mes': mes.toIso8601String().split('T').first,
        'monto_limite': montoLimite,
      };
}
