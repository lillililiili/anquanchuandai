import 'dart:ui';

import 'package:signals_hooks/signals_hooks.dart';
import '../theme/theme_signal.dart';

/// 获取响应式主色调
///
/// 当主题切换时自动触发组件重建
///
/// 使用示例:
/// ```dart
/// class MyWidget extends HookWidget {
///   @override
///   Widget build(BuildContext context) {
///     final primary = usePrimaryColor();
///     return Container(color: primary);
///   }
/// }
/// ```
Color usePrimaryColor() {
  return useSignalValue(ThemeModeSignal.primaryColorSignal);
}

/// 获取响应式背景色
///
/// 当主题切换时自动触发组件重建
Color useBackgroundColor() {
  return useSignalValue(ThemeModeSignal.backgroundColorSignal);
}

/// 获取响应式卡片背景色
///
/// 当主题切换时自动触发组件重建
Color useCardBackground() {
  return useSignalValue(ThemeModeSignal.cardBackgroundColorSignal);
}

/// 获取响应式主文字颜色
///
/// 当主题切换时自动触发组件重建
Color useTextPrimary() {
  return useSignalValue(ThemeModeSignal.textPrimarySignal);
}

/// 获取响应式次要文字颜色
///
/// 当主题切换时自动触发组件重建
Color useTextSecondary() {
  return useSignalValue(ThemeModeSignal.textSecondarySignal);
}

/// 获取响应式第三文字颜色
///
/// 当主题切换时自动触发组件重建
Color useTextTertiary() {
  return useSignalValue(ThemeModeSignal.textTertiarySignal);
}

/// 获取响应式分割线颜色
///
/// 当主题切换时自动触发组件重建
Color useDividerColor() {
  return useSignalValue(ThemeModeSignal.dividerColorSignal);
}

/// 获取是否为暗色主题
///
/// 当主题切换时自动触发组件重建
bool useIsDark() {
  return useSignalValue(ThemeModeSignal.isDarkSignal);
}

/// 获取所有主题颜色
///
/// 一次性获取所有常用主题颜色，适合需要多个颜色的复杂组件
///
/// 使用示例:
/// ```dart
/// class ComplexWidget extends HookWidget {
///   @override
///   Widget build(BuildContext context) {
///     final theme = useTheme();
///     return Scaffold(
///       backgroundColor: theme.background,
///       appBar: AppBar(
///         backgroundColor: theme.cardBackground,
///         title: Text('标题', style: TextStyle(color: theme.textPrimary)),
///       ),
///     );
///   }
/// }
/// ```
ThemeColors useTheme() {
  return useSignalValue(ThemeModeSignal.themeColorsSignal);
}
