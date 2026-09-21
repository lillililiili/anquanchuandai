import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'app_colors.dart';

/// 主题信号管理类
///
/// 使用方式:
/// ```dart
/// // 在 HookWidget 中使用
/// final primary = usePrimaryColor();
/// final theme = useTheme();
/// ```
class ThemeModeSignal {
  ThemeModeSignal._();

  // ==================== 信号定义 ====================

  // 当前主题模式信号
  static final themeMode = Signal(ThemeMode.system);

  // 颜色信号 - 使用 computed 实现响应式计算
  static final primaryColorSignal = computed(
    () => _getColor(
      (isDark) =>
          isDark ? SpringColors.mintGreenDarkTheme : SpringColors.mintGreen,
    ),
  );
  static final backgroundColorSignal = computed(
    () => _getColor(
      (isDark) =>
          isDark ? SpringColors.backgroundDark : SpringColors.backgroundLight,
    ),
  );
  static final cardBackgroundColorSignal = computed(
    () => _getColor(
      (isDark) => isDark
          ? SpringColors.cardBackgroundDark
          : SpringColors.cardBackgroundLight,
    ),
  );
  static final textPrimarySignal = computed(
    () => _getColor(
      (isDark) =>
          isDark ? SpringColors.textPrimaryDark : SpringColors.textPrimaryLight,
    ),
  );
  static final textSecondarySignal = computed(
    () => _getColor(
      (isDark) => isDark
          ? SpringColors.textSecondaryDark
          : SpringColors.textSecondaryLight,
    ),
  );
  static final textTertiarySignal = computed(
    () => _getColor(
      (isDark) => isDark
          ? SpringColors.textTertiaryDark
          : SpringColors.textTertiaryLight,
    ),
  );
  static final dividerColorSignal = computed(
    () => _getColor(
      (isDark) => isDark ? SpringColors.dividerDark : SpringColors.dividerLight,
    ),
  );
  static final isDarkSignal = computed(() => isDark);

  // 组合信号 - 包含所有主题颜色
  static final themeColorsSignal = computed(_buildThemeColors);

  // ==================== 辅助方法 ====================

  // 计算属性：是否为暗色主题
  static bool get isDark {
    final mode = themeMode.value;
    if (mode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return mode == ThemeMode.dark;
  }

  // 获取颜色的辅助函数
  static Color _getColor(Color Function(bool isDark) colorBuilder) {
    return colorBuilder(isDark);
  }

  // 构建主题颜色对象
  static ThemeColors _buildThemeColors() {
    return ThemeColors(
      primary: primaryColorSignal.value,
      background: backgroundColorSignal.value,
      cardBackground: cardBackgroundColorSignal.value,
      textPrimary: textPrimarySignal.value,
      textSecondary: textSecondarySignal.value,
      textTertiary: textTertiarySignal.value,
      divider: dividerColorSignal.value,
      isDark: isDarkSignal.value,
    );
  }

  /// 获取响应式的主色调 (兼容旧 API)
  static Color get primaryColor => primaryColorSignal.value;

  /// 获取响应式的背景色 (兼容旧 API)
  static Color get backgroundColor => backgroundColorSignal.value;

  /// 获取响应式的卡片背景色 (兼容旧 API)
  static Color get cardBackgroundColor => cardBackgroundColorSignal.value;

  /// 获取响应式的主文字颜色 (兼容旧 API)
  static Color get textPrimary => textPrimarySignal.value;

  /// 获取响应式的次要文字颜色 (兼容旧 API)
  static Color get textSecondary => textSecondarySignal.value;

  /// 获取响应式的第三文字颜色 (兼容旧 API)
  static Color get textTertiary => textTertiarySignal.value;

  /// 获取响应式的分割线颜色 (兼容旧 API)
  static Color get dividerColor => dividerColorSignal.value;

  /// 切换主题
  static void toggleTheme() {
    final current = themeMode.value;
    themeMode.value = current == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  /// 设置主题模式
  static void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
  }
}

/// 主题颜色数据类
///
/// 用于 [ThemeModeSignal.themeColorsSignal] 的返回值
class ThemeColors {
  final Color primary;
  final Color background;
  final Color cardBackground;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final bool isDark;

  ThemeColors({
    required this.primary,
    required this.background,
    required this.cardBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.isDark,
  });
}

/// 主题信号扩展方法
extension ThemeSignalExtensions on BuildContext {
  /// 获取响应式的主色调
  Color get primaryColor => ThemeModeSignal.primaryColor;

  /// 获取响应式的背景色
  Color get backgroundColor => ThemeModeSignal.backgroundColor;

  /// 获取响应式的卡片背景色
  Color get cardBackgroundColor => ThemeModeSignal.cardBackgroundColor;

  /// 获取响应式的主文字颜色
  Color get textPrimary => ThemeModeSignal.textPrimary;

  /// 获取响应式的次要文字颜色
  Color get textSecondary => ThemeModeSignal.textSecondary;

  /// 获取响应式的第三文字颜色
  Color get textTertiary => ThemeModeSignal.textTertiary;

  /// 获取响应式的分割线颜色
  Color get dividerColor => ThemeModeSignal.dividerColor;

  /// 是否为暗色主题
  bool get isDark => ThemeModeSignal.isDark;
}
