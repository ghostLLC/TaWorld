/// TaWorld 主题配置
///
/// 定义亮色和暗色两套完整的 Material 3 主题。
/// 所有组件样式在此统一配置，页面和组件中不应出现硬编码样式。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';
import 'typography.dart';

/// TaWorld 主题工厂
abstract final class TaTheme {
  /// 亮色主题
  static ThemeData get light {
    final textTheme = createTextTheme(
      bodyColor: TaLightColors.onSurface,
      displayColor: TaLightColors.onBackground,
    );

    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: TaLightColors.primary,
      onPrimary: TaLightColors.onPrimary,
      primaryContainer: TaLightColors.primaryContainer,
      onPrimaryContainer: TaLightColors.onPrimaryContainer,
      secondary: TaLightColors.secondary,
      onSecondary: TaLightColors.onSecondary,
      secondaryContainer: TaLightColors.secondaryContainer,
      onSecondaryContainer: TaLightColors.onSecondaryContainer,
      tertiary: TaLightColors.tertiary,
      onTertiary: TaLightColors.onTertiary,
      tertiaryContainer: TaLightColors.tertiaryContainer,
      onTertiaryContainer: TaLightColors.onTertiaryContainer,
      error: TaLightColors.error,
      onError: TaLightColors.onError,
      surface: TaLightColors.surface,
      onSurface: TaLightColors.onSurface,
      surfaceContainerHighest: TaLightColors.surfaceVariant,
      onSurfaceVariant: TaLightColors.onSurfaceVariant,
      outline: TaLightColors.outline,
      outlineVariant: TaLightColors.outlineVariant,
      shadow: TaLightColors.shadow,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: TaLightColors.background,

      // ---- AppBar ----
      appBarTheme: AppBarTheme(
        backgroundColor: TaLightColors.background,
        foregroundColor: TaLightColors.onBackground,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: TaLightColors.onBackground,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // ---- Card ----
      cardTheme: CardThemeData(
        color: TaLightColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderMd,
        ),
        margin: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
      ),

      // ---- ElevatedButton（主按钮） ----
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: TaLightColors.primary,
          foregroundColor: TaLightColors.onPrimary,
          minimumSize: const Size(double.infinity, TaSizes.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: TaRadius.borderMd,
          ),
          elevation: 0,
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // ---- OutlinedButton（次要按钮） ----
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TaLightColors.primary,
          minimumSize: const Size(double.infinity, TaSizes.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: TaRadius.borderMd,
          ),
          side: const BorderSide(color: TaLightColors.primary, width: 1.5),
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ---- TextButton ----
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TaLightColors.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),

      // ---- InputDecoration ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TaLightColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TaSpacing.md,
          vertical: TaSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: TaRadius.borderMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: TaRadius.borderMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: TaRadius.borderMd,
          borderSide: const BorderSide(color: TaLightColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: TaRadius.borderMd,
          borderSide: const BorderSide(color: TaLightColors.error, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: TaLightColors.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),

      // ---- BottomNavigationBar ----
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: TaLightColors.surface,
        selectedItemColor: TaLightColors.primary,
        unselectedItemColor: TaLightColors.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: textTheme.labelSmall,
      ),

      // ---- Chip ----
      chipTheme: ChipThemeData(
        backgroundColor: TaLightColors.surfaceVariant,
        selectedColor: TaLightColors.primaryContainer,
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderFull,
        ),
        side: BorderSide.none,
      ),

      // ---- Dialog ----
      dialogTheme: DialogThemeData(
        backgroundColor: TaLightColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderLg,
        ),
        titleTextStyle: textTheme.titleLarge,
      ),

      // ---- BottomSheet ----
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TaLightColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TaRadius.lg),
          ),
        ),
      ),

      // ---- Divider ----
      dividerTheme: const DividerThemeData(
        color: TaLightColors.outlineVariant,
        thickness: 1,
        space: 0,
      ),

      // ---- SnackBar ----
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderSm,
        ),
      ),

      // ---- FloatingActionButton ----
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: TaLightColors.primary,
        foregroundColor: TaLightColors.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderMd,
        ),
      ),
    );
  }

  /// 暗色主题
  static ThemeData get dark {
    final textTheme = createTextTheme(
      bodyColor: TaDarkColors.onSurface,
      displayColor: TaDarkColors.onBackground,
    );

    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: TaDarkColors.primary,
      onPrimary: TaDarkColors.onPrimary,
      primaryContainer: TaDarkColors.primaryContainer,
      onPrimaryContainer: TaDarkColors.onPrimaryContainer,
      secondary: TaDarkColors.secondary,
      onSecondary: TaDarkColors.onSecondary,
      secondaryContainer: TaDarkColors.secondaryContainer,
      onSecondaryContainer: TaDarkColors.onSecondaryContainer,
      tertiary: TaDarkColors.tertiary,
      onTertiary: TaDarkColors.onTertiary,
      tertiaryContainer: TaDarkColors.tertiaryContainer,
      onTertiaryContainer: TaDarkColors.onTertiaryContainer,
      error: TaDarkColors.error,
      onError: TaDarkColors.onError,
      surface: TaDarkColors.surface,
      onSurface: TaDarkColors.onSurface,
      surfaceContainerHighest: TaDarkColors.surfaceVariant,
      onSurfaceVariant: TaDarkColors.onSurfaceVariant,
      outline: TaDarkColors.outline,
      outlineVariant: TaDarkColors.outlineVariant,
      shadow: TaDarkColors.shadow,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: TaDarkColors.background,

      appBarTheme: AppBarTheme(
        backgroundColor: TaDarkColors.background,
        foregroundColor: TaDarkColors.onBackground,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: TaDarkColors.onBackground,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      cardTheme: CardThemeData(
        color: TaDarkColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderMd,
          side: BorderSide(color: TaDarkColors.outline.withValues(alpha: 0.3)),
        ),
        margin: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: TaDarkColors.primary,
          foregroundColor: TaDarkColors.onPrimary,
          minimumSize: const Size(double.infinity, TaSizes.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: TaRadius.borderMd,
          ),
          elevation: 0,
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TaDarkColors.primary,
          minimumSize: const Size(double.infinity, TaSizes.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: TaRadius.borderMd,
          ),
          side: const BorderSide(color: TaDarkColors.primary, width: 1.5),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TaDarkColors.primary,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TaDarkColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TaSpacing.md,
          vertical: TaSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: TaRadius.borderMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: TaRadius.borderMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: TaRadius.borderMd,
          borderSide: const BorderSide(color: TaDarkColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: TaRadius.borderMd,
          borderSide: const BorderSide(color: TaDarkColors.error, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: TaDarkColors.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: TaDarkColors.surface,
        selectedItemColor: TaDarkColors.primary,
        unselectedItemColor: TaDarkColors.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: TaDarkColors.surfaceVariant,
        selectedColor: TaDarkColors.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderFull,
        ),
        side: BorderSide.none,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: TaDarkColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderLg,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TaDarkColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TaRadius.lg),
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: TaDarkColors.outlineVariant,
        thickness: 1,
        space: 0,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderSm,
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: TaDarkColors.primary,
        foregroundColor: TaDarkColors.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: TaRadius.borderMd,
        ),
      ),
    );
  }
}
