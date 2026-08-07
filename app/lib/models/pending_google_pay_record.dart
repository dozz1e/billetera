class PendingGooglePayRecord {
  const PendingGooglePayRecord({
    required this.id,
    required this.monto,
    required this.comercioTexto,
    required this.categoriaSugeridaId,
    required this.fecha,
    required this.estado,
    required this.createdAt,
  });

  final String id;
  final double monto;
  final String comercioTexto;
  final String? categoriaSugeridaId;
  final DateTime fecha;
  // 'pendiente' | 'descartado' | 'insertado' — 'insertado' marks a record
  // that was successfully inserted as a transaction: its key is kept (rather
  // than deleted) so GooglePayListenerService's dedupe check still catches a
  // re-posted notification, but it's filtered out of the pending-card UI
  // (which only shows 'pendiente').
  final String estado;
  final DateTime createdAt;

  factory PendingGooglePayRecord.fromMap(Map map) => PendingGooglePayRecord(
        id: map['id'] as String,
        monto: (map['monto'] as num).toDouble(),
        comercioTexto: map['comercio_texto'] as String,
        categoriaSugeridaId: map['categoria_sugerida_id'] as String?,
        fecha: DateTime.parse(map['fecha'] as String),
        estado: map['estado'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'monto': monto,
        'comercio_texto': comercioTexto,
        'categoria_sugerida_id': categoriaSugeridaId,
        'fecha': fecha.toIso8601String(),
        'estado': estado,
        'created_at': createdAt.toIso8601String(),
      };

  PendingGooglePayRecord copyWith({String? estado}) => PendingGooglePayRecord(
        id: id,
        monto: monto,
        comercioTexto: comercioTexto,
        categoriaSugeridaId: categoriaSugeridaId,
        fecha: fecha,
        estado: estado ?? this.estado,
        createdAt: createdAt,
      );
}
