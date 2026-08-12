import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format/money.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: isDark ? AppColors.darkPrimary : AppColors.brand,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? AppColors.darkPrimary : AppColors.brand,
          onPrimary: isDark ? AppColors.darkOnPrimary : Colors.white,
          primaryContainer: isDark
              ? AppColors.darkPrimaryContainer
              : AppColors.lightPrimaryContainer,
          onPrimaryContainer: isDark ? AppColors.darkText : AppColors.brandDeep,
          surface: isDark
              ? AppColors.darkBackground
              : AppColors.lightBackground,
          surfaceContainerLowest: isDark
              ? AppColors.darkSurface
              : AppColors.lightSurface,
          surfaceContainerLow: isDark
              ? AppColors.darkSurfaceMuted
              : AppColors.lightSurfaceMuted,
          surfaceContainer: isDark
              ? AppColors.darkSurfaceMuted
              : AppColors.lightSurfaceMuted,
          onSurface: isDark ? AppColors.darkText : AppColors.lightText,
          onSurfaceVariant: isDark
              ? AppColors.darkTextMuted
              : AppColors.lightTextMuted,
          outline: isDark ? AppColors.darkOutline : AppColors.lightOutline,
          outlineVariant: isDark
              ? AppColors.darkOutline
              : AppColors.lightOutline,
          error: isDark ? AppColors.darkError : AppColors.error,
          onError: isDark ? const Color(0xFF690005) : Colors.white,
        );

    final baseText = ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      focusColor: scheme.primary.withValues(alpha: .12),
      hoverColor: scheme.primary.withValues(alpha: .07),
      splashColor: scheme.primary.withValues(alpha: .08),
      textTheme: baseText.copyWith(
        // The display sizes carry the big money figures, so they get
        // fixed-width digits: without them a changing total visibly jitters
        // and stacked amounts fail to line up.
        displayLarge: baseText.displayLarge?.copyWith(
          fontFeatures: tabularFigures,
        ),
        displayMedium: baseText.displayMedium?.copyWith(
          fontFeatures: tabularFigures,
        ),
        displaySmall: baseText.displaySmall?.copyWith(
          fontSize: 40,
          height: 1.05,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.6,
          fontFeatures: tabularFigures,
        ),
        headlineLarge: baseText.headlineLarge?.copyWith(
          fontSize: 40,
          height: 1.08,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.25,
          fontFeatures: tabularFigures,
        ),
        headlineMedium: baseText.headlineMedium?.copyWith(
          fontSize: 32,
          height: 1.12,
          fontWeight: FontWeight.w800,
          letterSpacing: -.8,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontSize: 22,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -.35,
          fontFeatures: tabularFigures,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontFeatures: tabularFigures,
        ),
        titleSmall: baseText.titleSmall?.copyWith(fontFeatures: tabularFigures),
        labelMedium: baseText.labelMedium?.copyWith(
          fontFeatures: tabularFigures,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
        bodyMedium: baseText.bodyMedium?.copyWith(height: 1.45),
        bodySmall: baseText.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .55),
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        iconTheme: IconThemeData(color: scheme.primary, size: 22),
        actionsIconTheme: IconThemeData(color: scheme.primary, size: 22),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -.2,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: scheme.surface,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: .14),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: .14),
        indicatorShape: const CircleBorder(),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurfaceMuted.withValues(alpha: .88)
            : Colors.white.withValues(alpha: .88),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: .82),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        errorStyle: TextStyle(color: scheme.error, fontWeight: FontWeight.w500),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: .12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: .45),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -.1,
          ),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: .24),
        selectionHandleColor: scheme.primary,
      ),
    );
  }
}
