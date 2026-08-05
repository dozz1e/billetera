class Goal {
  const Goal({
    required this.id,
    required this.userId,
    required this.nombre,
    required this.accountId,
    required this.montoObjetivo,
    required this.fechaObjetivo,
    required this.estado,
  });

  final String id;
  final String userId;
  final String nombre;
  final String accountId;
  final double montoObjetivo;
  final DateTime fechaObjetivo;
  final String estado; // 'activo' | 'pausado' | 'alcanzado'

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        nombre: json['nombre'] as String,
        accountId: json['account_id'] as String,
        montoObjetivo: (json['monto_objetivo'] as num).toDouble(),
        fechaObjetivo: DateTime.parse(json['fecha_objetivo'] as String),
        estado: json['estado'] as String,
      );

  Map<String, dynamic> toInsertJson() => {
        'nombre': nombre,
        'account_id': accountId,
        'monto_objetivo': montoObjetivo,
        'fecha_objetivo': fechaObjetivo.toIso8601String().split('T').first,
      };
}
