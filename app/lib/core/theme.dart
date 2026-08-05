import 'package:flutter/material.dart';

/// Vivid, high-chroma blue: distinct from the near-black scaffold and from
/// Flutter's stock Colors.blue, so primary actions read as this app's own.
const _seedBlue = Color(0xFF3D7DFB);

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seedBlue,
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: const Color(0xFF121212),
  cardColor: const Color(0xFF1E1E1E),
  cardTheme: const CardThemeData(
    color: Color(0xFF1E1E1E),
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
);
