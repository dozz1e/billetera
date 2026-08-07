class RecurringPayment {
  const RecurringPayment({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.categoryId,
    required this.monto,
    required this.diaMes,
    required this.fechaInicio,
    this.nota,
    required this.activo,
    this.ultimaGenerada,
  });

  final String id;
  final String userId;
  final String accountId;
  final String categoryId;
  final double monto;
  final int diaMes;
  final DateTime fechaInicio;
  final String? nota;
  final bool activo;
  final DateTime? ultimaGenerada;

  factory RecurringPayment.fromJson(Map<String, dynamic> json) =>
      RecurringPayment(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        accountId: json['account_id'] as String,
        categoryId: json['category_id'] as String,
        monto: (json['monto'] as num).toDouble(),
        diaMes: json['dia_mes'] as int,
        fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
        nota: json['nota'] as String?,
        activo: json['activo'] as bool,
        ultimaGenerada: json['ultima_generada'] == null
            ? null
            : DateTime.parse(json['ultima_generada'] as String),
      );

  Map<String, dynamic> toInsertJson() => {
        'account_id': accountId,
        'category_id': categoryId,
        'monto': monto,
        'dia_mes': diaMes,
        'nota': nota,
        'fecha_inicio': fechaInicio.toIso8601String().split('T').first,
        'activo': activo,
      };
}
