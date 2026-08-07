class Person {
  const Person({
    required this.id,
    required this.userId,
    required this.nombre,
  });

  final String id;
  final String userId;
  final String nombre;

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        nombre: json['nombre'] as String,
      );

  Map<String, dynamic> toInsertJson() => {
        'nombre': nombre,
      };
}
