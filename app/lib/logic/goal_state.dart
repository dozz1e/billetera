String nextGoalState({
  required double ahorrado,
  required double montoObjetivo,
  required String estadoActual,
}) {
  if (estadoActual == 'pausado' || estadoActual == 'alcanzado') return estadoActual;
  if (ahorrado >= montoObjetivo) return 'alcanzado';
  return estadoActual;
}
