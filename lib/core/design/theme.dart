import 'package:flutter/material.dart';

import 'colors.dart';
import 'radius.dart';
import 'text_styles.dart';

ThemeData buildAppTheme({bool dark = false}) {
  AppColors.setDark(dark);
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: AppColors.bgPage,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.textInverse,
      secondary: AppColors.primary,
      surface: AppColors.bgSurface,
      error: AppColors.danger,
    ),
    splashFactory: InkRipple.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bgPage,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      titleTextStyle:
          AppText.titleMedium.copyWith(color: AppColors.textPrimary),
      iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bgSurface,
      indicatorColor: AppColors.primaryLight,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.all(
        AppText.caption.copyWith(fontWeight: FontWeight.w500, fontSize: 11),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textSecondary,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.borderLight, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.borderLight, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.danger, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.danger, width: 1.5),
      ),
      hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
      labelStyle: AppText.bodySmall,
      floatingLabelStyle: AppText.bodySmall.copyWith(color: AppColors.primary),
      helperStyle: AppText.caption,
      errorStyle: AppText.caption.copyWith(color: AppColors.danger),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: AppText.button,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: AppText.button,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2A3140) : AppColors.textPrimary,
      contentTextStyle: AppText.bodySmall.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      insetPadding: const EdgeInsets.all(16),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.bgSurface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.bgSurface,
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.bgSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      textStyle: AppText.bodySmall.copyWith(color: AppColors.textPrimary),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.primaryLight,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: AppColors.primaryLight,
      selectionHandleColor: AppColors.primary,
    ),
  );
}
