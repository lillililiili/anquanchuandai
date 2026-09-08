import 'package:flutter/material.dart';

/// CARGO 风格清晰文字层级。颜色由当前主题提供。
class AppTypography {
  AppTypography._();
  static const String fontFamily = 'Roboto';
  static const headlineLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );
  static const headlineMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );
  static const title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
  static const subtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
  static const button = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  static TextTheme get textTheme => const TextTheme(
    headlineLarge: headlineLarge,
    headlineMedium: headlineMedium,
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    titleMedium: title,
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    bodyLarge: body,
    bodyMedium: subtitle,
    bodySmall: caption,
    labelLarge: button,
    labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    labelSmall: caption,
  );
}
