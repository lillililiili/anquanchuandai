import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// CARGO 风格的全局控件规范；业务危险/告警颜色仍由各页面显式声明。
class AppTheme {
  AppTheme._();
  static ThemeData get lightTheme => _build(false);
  static ThemeData get darkTheme => _build(true);

  static ThemeData _build(bool dark) {
    final ink = dark
        ? SpringColors.textPrimaryDark
        : SpringColors.textPrimaryLight;
    final muted = dark
        ? SpringColors.textSecondaryDark
        : SpringColors.textSecondaryLight;
    final background = dark
        ? SpringColors.backgroundDark
        : SpringColors.backgroundLight;
    final surface = dark ? SpringColors.cardBackgroundDark : Colors.white;
    final line = dark ? const Color(0xFF41516B) : const Color(0xFFE2E7F0);
    const cyan = SpringColors.mintGreen;
    const navy = SpringColors.textPrimaryLight;
    final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(
          primary: cyan,
          onPrimary: navy,
          primaryContainer: dark
              ? const Color(0xFF254E60)
              : const Color(0xFFE5F9FD),
          onPrimaryContainer: ink,
          secondary: cyan,
          onSecondary: navy,
          secondaryContainer: dark
              ? const Color(0xFF32445C)
              : const Color(0xFFEDF2F8),
          onSecondaryContainer: ink,
          tertiary: SpringColors.sproutYellow,
          onTertiary: navy,
          error: SpringColors.cherryRed,
          onError: Colors.white,
          errorContainer: dark
              ? const Color(0xFF582B35)
              : const Color(0xFFFEE2E2),
          onErrorContainer: dark
              ? const Color(0xFFFFDAD6)
              : const Color(0xFF991B1B),
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: line,
          outlineVariant: line,
        );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final textTheme = AppTypography.textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
    );
    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          ...const PageTransitionsTheme().builders,
          TargetPlatform.android: const FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      fontFamily: AppTypography.fontFamily,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      primaryColor: cyan,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        year2023: false,
        color: cyan,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 52,
        titleTextStyle: AppTypography.headlineMedium.copyWith(color: ink),
        iconTheme: IconThemeData(color: ink, size: 22),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: ink, size: 22),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? background : const Color(0xFFF5F7FB),
        hintStyle: TextStyle(color: muted, fontSize: 14),
        labelStyle: TextStyle(color: muted, fontSize: 14),
        floatingLabelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cyan, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: navy,
          disabledBackgroundColor: dark
              ? const Color(0xFF34425A)
              : const Color(0xFFE8EDF3),
          disabledForegroundColor: muted,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: buttonShape,
          textStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: navy,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
          textStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: line),
          minimumSize: const Size(48, 48),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: muted,
          height: 1.5,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: line,
        dragHandleSize: const Size(36, 4),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        disabledColor: background,
        labelStyle: TextStyle(color: ink, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: ink),
        checkmarkColor: ink,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: muted,
        indicatorColor: cyan,
        dividerColor: Colors.transparent,
        labelStyle: AppTypography.title,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: cyan,
        thumbColor: ink,
        inactiveTrackColor: line,
        overlayColor: cyan.withValues(alpha: .14),
        trackHeight: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: navy,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        actionTextColor: cyan,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: cyan,
        foregroundColor: navy,
        elevation: 3,
      ),
    );
  }
}
