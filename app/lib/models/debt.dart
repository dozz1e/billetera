class Debt {
  const Debt({
    required this.id,
    required this.userId,
    required this.personId,
    required this.motivo,
    required this.monto,
    required this.fecha,
    required this.estado,
  });

  final String id;
  final String userId;
  final String personId;
  final String motivo;
  final double monto;
  final DateTime fecha;
  final String estado; // 'pendiente' | 'pagada'

  factory Debt.fromJson(Map<String, dynamic> json) => Debt(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        personId: json['person_id'] as String,
        motivo: json['motivo'] as String,
        monto: (json['monto'] as num).toDouble(),
        fecha: DateTime.parse(json['fecha'] as String),
        estado: json['estado'] as String,
      );

  Map<String, dynamic> toInsertJson() => {
        'person_id': personId,
        'motivo': motivo,
        'monto': monto,
        'fecha': fecha.toIso8601String().split('T').first,
      };
}
