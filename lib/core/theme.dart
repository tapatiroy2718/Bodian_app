import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kMaroon = Color(0xFF5B1020);
const kRoyalRed = Color(0xFFC2185B);
const kGold = Color(0xFFD4AF37);
const kIvory = Color(0xFFFFF9F0);
const kCream = Color(0xFFFCE4EC);
const kInk = Color(0xFF2B1A1D);
const kMuted = Color(0xFF7A6A6D);
const kSuccess = Color(0xFF2E7D32);
const kWarning = Color(0xFFE08A00);

const kRadius = 20.0;

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kMaroon,
    primary: kMaroon,
    secondary: kRoyalRed,
    tertiary: kGold,
    surface: kIvory,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kIvory,
  );
  final body = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: kInk, displayColor: kInk);
  TextStyle? heading(TextStyle? s) => GoogleFonts.poppins(textStyle: s, fontWeight: FontWeight.w600, color: kInk);

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: body.copyWith(
      headlineLarge: heading(body.headlineLarge),
      headlineMedium: heading(body.headlineMedium),
      headlineSmall: heading(body.headlineSmall),
      titleLarge: heading(body.titleLarge),
      titleMedium: heading(body.titleMedium),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kMaroon,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        shape: buttonShape,
        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kMaroon,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        shape: buttonShape,
        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kMaroon,
        minimumSize: const Size(64, 48),
        shape: buttonShape,
        side: const BorderSide(color: kMaroon),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: kCream,
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
    ),
  );
}

/// Shared text-field decoration (kept out of ThemeData for SDK compatibility).
InputDecoration inputDeco(String label, {String? hint, IconData? icon, Widget? suffix, String? helper}) {
  OutlineInputBorder border(Color c) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    prefixIcon: icon == null ? null : Icon(icon),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    border: border(const Color(0xFFE6D9D2)),
    enabledBorder: border(const Color(0xFFE6D9D2)),
    focusedBorder: border(kMaroon),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
