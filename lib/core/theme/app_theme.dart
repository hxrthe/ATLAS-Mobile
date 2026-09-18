import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared brand + semantic colors for light/dark ATLAS UI.
class AtlasColors {
  final Color scaffold;
  final Color card;
  final Color cardMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color primary;
  final Color onPrimary;
  final Color correct;
  final Color incorrect;
  final Color ambiguous;
  final Color pass;
  final Color fail;
  final Color inputFill;
  final Color divider;

  const AtlasColors({
    required this.scaffold,
    required this.card,
    required this.cardMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.primary,
    required this.onPrimary,
    required this.correct,
    required this.incorrect,
    required this.ambiguous,
    required this.pass,
    required this.fail,
    required this.inputFill,
    required this.divider,
  });

  static const light = AtlasColors(
    scaffold: Color(0xFFF4F6F9),
    card: Color(0xFFFFFFFF),
    cardMuted: Color(0xFFE8ECF4),
    textPrimary: Color(0xFF1E232C),
    textSecondary: Color(0xFF8391A1),
    border: Color(0xFFE8ECF4),
    primary: Color(0xFF8B1515),
    onPrimary: Color(0xFFFFFFFF),
    correct: Color(0xFF2E7D32),
    incorrect: Color(0xFFC62828),
    ambiguous: Color(0xFFE6A23C),
    pass: Color(0xFF2E7D32),
    fail: Color(0xFF8B1515),
    inputFill: Color(0xFFFFFFFF),
    divider: Color(0xFFE8ECF4),
  );

  /// Matches Scan Result dark palette.
  static const dark = AtlasColors(
    scaffold: Color(0xFF0E1116),
    card: Color(0xFF1A1F27),
    cardMuted: Color(0xFF2A3038),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xB3FFFFFF),
    border: Color(0xFF2A3038),
    primary: Color(0xFF8B1515),
    onPrimary: Color(0xFFFFFFFF),
    correct: Color(0xFF81C784),
    incorrect: Color(0xFFEF9A9A),
    ambiguous: Color(0xFFFFD54F),
    pass: Color(0xFF00E676),
    fail: Color(0xFFFF5252),
    inputFill: Color(0xFF1A1F27),
    divider: Color(0xFF2A3038),
  );

  static AtlasColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? dark : light;
  }
}

extension AtlasThemeX on BuildContext {
  AtlasColors get atlas => AtlasColors.of(this);
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  static const _seed = Color(0xFF8B1515);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
      primary: AtlasColors.light.primary,
      surface: AtlasColors.light.card,
    );
    return _base(scheme, AtlasColors.light);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      primary: AtlasColors.dark.primary,
      surface: AtlasColors.dark.card,
    ).copyWith(
      surface: AtlasColors.dark.card,
      onSurface: AtlasColors.dark.textPrimary,
    );
    return _base(scheme, AtlasColors.dark);
  }

  static ThemeData _base(ColorScheme scheme, AtlasColors c) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.scaffold,
      canvasColor: c.scaffold,
      cardColor: c.card,
      dividerColor: c.divider,
      primaryColor: c.primary,
      appBarTheme: AppBarTheme(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? c.cardMuted : c.primary,
        contentTextStyle: TextStyle(color: c.onPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
      ),
      dividerTheme: DividerThemeData(color: c.divider),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.inputFill,
        hintStyle: TextStyle(color: c.textSecondary),
        labelStyle: TextStyle(color: c.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primary,
          side: BorderSide(color: c.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return c.primary;
          return c.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return c.primary.withValues(alpha: 0.45);
          }
          return c.cardMuted;
        }),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: c.textPrimary),
        bodyMedium: TextStyle(color: c.textPrimary),
        bodySmall: TextStyle(color: c.textSecondary),
        titleLarge: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
      ),
    );
  }
}
