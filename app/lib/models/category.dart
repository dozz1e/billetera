class Category {
  const Category({
    required this.id,
    required this.userId,
    required this.nombre,
    required this.tipo,
    required this.icono,
    required this.predefinida,
  });

  final String id;
  final String userId;
  final String nombre;
  final String tipo; // 'ingreso' | 'gasto'
  final String icono;
  final bool predefinida;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        nombre: json['nombre'] as String,
        tipo: json['tipo'] as String,
        icono: json['icono'] as String,
        predefinida: json['predefinida'] as bool,
      );

  Map<String, dynamic> toInsertJson() => {
        'nombre': nombre,
        'tipo': tipo,
        'icono': icono,
        'predefinida': predefinida,
      };
}
