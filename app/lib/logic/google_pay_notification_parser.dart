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
/// Whichever of `,`/`.` appears last in the string is treated as the
/// decimal separator; the other is stripped as a thousands separator.
double? _parseMonto(String raw) {
  final trimmed = raw.trim();
  final lastComma = trimmed.lastIndexOf(',');
  final lastDot = trimmed.lastIndexOf('.');

  String normalized;
  if (lastComma > lastDot) {
    normalized = trimmed.replaceAll('.', '').replaceAll(',', '.');
  } else if (lastDot > lastComma) {
    normalized = trimmed.replaceAll(',', '');
  } else {
    normalized = trimmed;
  }
  return double.tryParse(normalized);
}
