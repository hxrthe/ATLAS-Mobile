import 'package:flutter/material.dart';

class AppTheme {
  // The signature ATLAS Red
  static const Color primaryRed = Color(0xFF8B1515);

  // -------------------------
  // GLOBAL TEXT THEMES
  // -------------------------
  // We define the base typography scales here to ensure absolute consistency.
  static final TextTheme _lightTextTheme = ThemeData.light().textTheme.copyWith(
    displayLarge: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
    titleLarge: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600, fontSize: 22),
    bodyLarge: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 16),
    bodyMedium: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
    labelLarge: const TextStyle(color: Color(0xFF757575), fontWeight: FontWeight.w500),
  ).apply(
    bodyColor: const Color(0xFF1A1A1A), // Forces all standard text to this color
    displayColor: const Color(0xFF1A1A1A), // Forces all headers to this color
  );

  static final TextTheme _darkTextTheme = ThemeData.dark().textTheme.copyWith(
    displayLarge: const TextStyle(color: Color(0xFFF5F5F5), fontWeight: FontWeight.bold),
    titleLarge: const TextStyle(color: Color(0xFFF5F5F5), fontWeight: FontWeight.w600, fontSize: 22),
    bodyLarge: const TextStyle(color: Color(0xFFF5F5F5), fontSize: 16),
    bodyMedium: const TextStyle(color: Color(0xFFF5F5F5), fontSize: 14),
    labelLarge: const TextStyle(color: Color(0xFFAAAAAA), fontWeight: FontWeight.w500),
  ).apply(
    bodyColor: const Color(0xFFF5F5F5),
    displayColor: const Color(0xFFF5F5F5),
  );

  // -------------------------
  // LIGHT MODE PALETTE
  // -------------------------
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    textTheme: _lightTextTheme, // <--- Injected here
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF8B1515), // ATLAS Red stays here
      surfaceContainer: Color(0xFFFFFFFF), // Pure white for cards/lists
      onSurface: Color(0xFF1A1A1A), // Dark text
      surface: Color(0xFFF9F9F9),
      secondary: Color(0xFFD4811B),
      onSurfaceVariant: Color(0xFF757575),
    ),
    scaffoldBackgroundColor: const Color(0xFFF4F6F9), // Clean, crisp off-white
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF9F9F9),
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
      centerTitle: true,
      titleTextStyle: TextStyle(color: Color(0xFF1A1A1A), fontSize: 20, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFFFFFFF), // Or Colors.white
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE0E0E0), width: 1), // Crisp iOS-style border
      ),
    ),
  );

  // -------------------------
  // DARK MODE PALETTE
  // -------------------------
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    textTheme: _darkTextTheme, // <--- Injected here
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF8B1515),
      surfaceContainer: Color(0xFF1C1C1E), // Authentic Apple Dark Mode gray
      onSurface: Color(0xFFFFFFFF),
      secondary: Color(0xFFD4811B),
      surface: Color(0xFF121212),
      onSurfaceVariant: Color(0xFFAAAAAA),
    ),
    scaffoldBackgroundColor: const Color(0xFF000000), // True deep black
     // Pure white text
      // ...// True black background
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF000000),
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFFF5F5F5)),
      centerTitle: true,
      titleTextStyle: TextStyle(color: Color(0xFFF5F5F5), fontSize: 20, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1C1C1E),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF333333), width: 1),
      ),
    ),
  );
}