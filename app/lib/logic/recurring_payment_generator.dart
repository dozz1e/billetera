DateTime _occurrenceForMonth(int year, int month, int diaMes) {
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final day = diaMes > daysInMonth ? daysInMonth : diaMes;
  return DateTime(year, month, day);
}

/// Returns one due date per month owed between the last generated month
/// (or [fechaInicio]'s month if [ultimaGenerada] is null) and [hoy],
/// inclusive, skipping any month whose occurrence date is still in the
/// future relative to [hoy]. If more than [maxBackfill] months are owed,
/// only the most recent [maxBackfill] are returned — older ones are
/// silently dropped rather than generating years of backlog at once.
List<DateTime> computeDueOccurrences({
  required int diaMes,
  required DateTime fechaInicio,
  required DateTime? ultimaGenerada,
  required DateTime hoy,
  int maxBackfill = 12,
}) {
  var cursorMonth = ultimaGenerada == null
      ? DateTime(fechaInicio.year, fechaInicio.month)
      : DateTime(ultimaGenerada.year, ultimaGenerada.month + 1);
  final lastMonth = DateTime(hoy.year, hoy.month);

  final due = <DateTime>[];
  while (!cursorMonth.isAfter(lastMonth)) {
    final occurrence = _occurrenceForMonth(
      cursorMonth.year,
      cursorMonth.month,
      diaMes,
    );
    if (!occurrence.isAfter(hoy)) {
      due.add(occurrence);
    }
    cursorMonth = DateTime(cursorMonth.year, cursorMonth.month + 1);
  }

  if (due.length > maxBackfill) {
    return due.sublist(due.length - maxBackfill);
  }
  return due;
}
