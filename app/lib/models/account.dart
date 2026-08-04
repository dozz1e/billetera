class Account {
  const Account({
    required this.id,
    required this.userId,
    required this.nombre,
    required this.tipo,
    required this.saldoInicial,
    required this.activo,
  });

  final String id;
  final String userId;
  final String nombre;
  final String tipo; // 'efectivo' | 'banco' | 'credito' | 'billetera_digital'
  final double saldoInicial;
  final bool activo;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        nombre: json['nombre'] as String,
        tipo: json['tipo'] as String,
        saldoInicial: (json['saldo_inicial'] as num).toDouble(),
        activo: json['activo'] as bool,
      );

  Map<String, dynamic> toInsertJson() => {
        'nombre': nombre,
        'tipo': tipo,
        'saldo_inicial': saldoInicial,
        'activo': activo,
      };
}
