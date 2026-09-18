import 'package:flutter/material.dart';

/// The palette and type the whole app draws from.
class FocusPalette {
  const FocusPalette._();

  /// The blue of the AR zone and the locked-in session.
  static const Color focus = Color(0xFF2E6BFF);
  static const Color focusSoft = Color(0xFF9CB0FF);

  /// The crimson of the focus card.
  static const Color card = Color(0xFFE8134B);
  static const Color cardDeep = Color(0xFFA00733);

  /// Backgrounds.
  static const Color ink = Color(0xFF05101F);
  static const Color surface = Color(0xFF101F36);

  /// Session states.
  static const Color alarm = Color(0xFFFF4D6D);
  static const Color done = Color(0xFF4ADE9B);

  /// Radial gradients behind each session state.
  static const List<Color> restingGradient = [Color(0xFF1B4DBF), Color(0xFF040C1A)];
  static const List<Color> lockedGradient = [Color(0xFF1350E8), Color(0xFF03081A)];
  static const List<Color> alarmGradient = [Color(0xFF12161C), Color(0xFF05070A)];
  static const List<Color> doneGradient = [Color(0xFF12735E), Color(0xFF04191A)];
  static const List<Color> earningGradient = [Color(0xFF1A2F8C), Color(0xFF060B1F)];
}

/// Builds the app-wide dark theme.
ThemeData buildFocusTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: FocusPalette.ink,
    colorScheme: ColorScheme.fromSeed(
      seedColor: FocusPalette.focus,
      brightness: Brightness.dark,
      surface: FocusPalette.surface,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -2,
      ),
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FocusPalette.focus,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
    ),
  );
}

/// The caption style used for the small all-caps labels.
const TextStyle kEyebrow = TextStyle(
  fontSize: 11.5,
  letterSpacing: 1.8,
  fontWeight: FontWeight.w700,
  color: Colors.white60,
);
