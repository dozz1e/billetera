class ParsedGooglePayNotification {
  const ParsedGooglePayNotification({required this.monto, required this.comercioTexto});

  final double monto;
  final String comercioTexto;
}

final _esPattern = RegExp(r'Pagaste\s+\$?\s*([\d.,]+)\s+en\s+(.+)', caseSensitive: false);
final _enPattern = RegExp(r'You paid\s+\$?\s*([\d.,]+)\s+at\s+(.+)', caseSensitive: false);

ParsedGooglePayNotification? parseGooglePayNotification({
  required String? title,
  required String? text,
}) {
  if (text == null) return null;

  final match = _esPattern.firstMatch(text) ?? _enPattern.firstMatch(text);
  if (match == null) return null;

  final monto = _parseMonto(match.group(1)!);
  if (monto == null) return null;

  final comercioTexto = match.group(2)!.trim();
  if (comercioTexto.isEmpty) return null;

  return ParsedGooglePayNotification(monto: monto, comercioTexto: comercioTexto);
}

/// Handles both decimal conventions since the real device format isn't
/// confirmed yet (see risk note in the Google Pay design spec): CL-style
/// ("8.574,00", comma decimal) and US-style ("8,574.00", point decimal).
/// Disambiguates by digit count after the last separator rather than by
/// position alone: exactly 2 trailing digits means that separator is the
/// decimal point (the other separator, if any, is thousands grouping);
/// any other trailing digit count (including a lone thousands separator on
/// a whole-peso CLP amount with no cents, e.g. "1.300" or "8,574") means
/// there is no decimal component at all, so every separator found is
/// stripped as thousands grouping.
double? _parseMonto(String raw) {
  final trimmed = raw.trim();
  final lastComma = trimmed.lastIndexOf(',');
  final lastDot = trimmed.lastIndexOf('.');
  final lastSeparator = lastComma > lastDot ? lastComma : lastDot;

  if (lastSeparator == -1) return double.tryParse(trimmed);

  final digitsAfterLastSeparator = trimmed.length - lastSeparator - 1;
  if (digitsAfterLastSeparator != 2) {
    return double.tryParse(trimmed.replaceAll(',', '').replaceAll('.', ''));
  }

  final decimalChar = trimmed[lastSeparator];
  final thousandsChar = decimalChar == ',' ? '.' : ',';
  var normalized = trimmed.replaceAll(thousandsChar, '');
  if (decimalChar == ',') normalized = normalized.replaceAll(',', '.');
  return double.tryParse(normalized);
}
