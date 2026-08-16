import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens for the app. Every colour, radius, and spacing value in the
/// UI should come from here rather than being hard-coded at the call site.
class AppColors {
  AppColors._();

  // Canvas + surfaces (cool near-black, so accents read as light, not neon).
  static const canvas = Color(0xFF0A0C11);
  static const canvasTint = Color(0xFF111621);
  static const surface = Color(0xFF151922);
  static const surfaceAlt = Color(0xFF1B2130);
  static const surfaceHigh = Color(0xFF222937);

  static const border = Color(0xFF252C3A);
  static const borderStrong = Color(0xFF323B4D);

  // Accents.
  static const primary = Color(0xFF8CA6FF);
  static const primaryDeep = Color(0xFF5470E6);
  static const mint = Color(0xFF5FE3C0);
  static const amber = Color(0xFFFFC46B);
  static const rose = Color(0xFFFF8FA3);
  static const violet = Color(0xFFB79CFF);

  // Text.
  static const text = Color(0xFFEDF0F7);
  static const textMuted = Color(0xFF98A2B6);
  static const textFaint = Color(0xFF6B7488);
}

/// Corner radii, in one place so cards, fields, and sheets stay in step.
/// Fills for the primary call-to-action surfaces. Buttons are the one place
/// the UI carries a solid fill, so they use a deep gradient with white text
/// rather than a flat saturated slab — loud enough to lead, quiet enough to
/// sit next to the tinted cards and pills.
class AppGradients {
  AppGradients._();

  static const primaryButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6379EA), Color(0xFF4257CE)],
  );

  static const destructiveButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFD75C72), Color(0xFFB93E55)],
  );

  /// Hairline highlight along the top edge, so the fill reads as lit.
  static const buttonHighlight = Color(0x26FFFFFF);
}

class AppRadius {
  AppRadius._();

  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

/// The base spacing rhythm (multiples of 4).
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;

  /// Horizontal page gutter used by every screen.
  static const gutter = 20.0;
}

/// Accent ramp used to give each trip its own identity in lists and headers.
const tripAccents = <Color>[
  AppColors.primary,
  AppColors.mint,
  AppColors.amber,
  AppColors.violet,
  AppColors.rose,
];

Color accentFor(int seed) => tripAccents[seed.abs() % tripAccents.length];

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: Color(0xFF0B1020),
    primaryContainer: AppColors.primaryDeep,
    onPrimaryContainer: Colors.white,
    secondary: AppColors.mint,
    onSecondary: Color(0xFF07211B),
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.surfaceHigh,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.borderStrong,
    outlineVariant: AppColors.border,
    error: AppColors.rose,
    onError: Color(0xFF2A0A11),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    canvasColor: AppColors.canvas,
    splashFactory: InkSparkle.splashFactory,
  );

  final text = base.textTheme
      .apply(bodyColor: AppColors.text, displayColor: AppColors.text)
      .copyWith(
        displaySmall: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          color: AppColors.text,
        ),
        headlineMedium: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: AppColors.text,
        ),
        headlineSmall: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: AppColors.text,
        ),
        titleLarge: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: AppColors.text,
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: AppColors.text,
        ),
        bodyLarge: const TextStyle(fontSize: 15.5, height: 1.45),
        bodyMedium: const TextStyle(
          fontSize: 14,
          height: 1.45,
          color: AppColors.textMuted,
        ),
        bodySmall: const TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: AppColors.textFaint,
        ),
        labelLarge: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        labelSmall: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textFaint,
        ),
      );

  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      hintStyle: const TextStyle(color: AppColors.textFaint),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      floatingLabelStyle: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.rose),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.rose, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Bare FilledButtons fall back to the flat deep fill; the gradient
        // treatment comes from AppPrimaryButton.
        backgroundColor: AppColors.primaryDeep,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.surfaceHigh,
        disabledForegroundColor: AppColors.textFaint,
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textMuted,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primaryDeep,
      foregroundColor: Colors.white,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      extendedTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: const BorderSide(color: AppColors.border),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.text,
      ),
      contentTextStyle: const TextStyle(
        fontSize: 14.5,
        height: 1.5,
        color: AppColors.textMuted,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      side: const BorderSide(color: AppColors.borderStrong, width: 1.6),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.mint;
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(Color(0xFF07211B)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceAlt),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: AppColors.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: AppColors.surfaceHigh,
      headerForegroundColor: AppColors.text,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.surfaceHigh,
      circularTrackColor: Colors.transparent,
    ),
  );
}
