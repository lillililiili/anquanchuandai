import 'package:flutter/material.dart';

/// 间距和圆角规范
class AppSpacing {
  AppSpacing._();

  // ==================== 间距 ====================
  /// 标准间距单位（基于 4px 网格）
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;

  /// 标准卡片内边距
  static const EdgeInsets cardPadding = EdgeInsets.all(12);

  /// 大卡片内边距
  static const EdgeInsets cardPaddingLarge = EdgeInsets.all(14);

  /// 标准卡片外边距
  static const EdgeInsets cardMargin = EdgeInsets.all(lg);

  /// 列表项内边距
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );

  // ==================== 圆角 ====================
  /// 小圆角（按钮、小标签）
  static const double radiusSmall = 10.0;

  /// 中圆角（内部元素）
  static const double radiusMedium = 12.0;

  /// 大圆角（主卡片）
  static const double radiusLarge = 16.0;

  /// 超大圆角（页面级容器）
  static const double radiusXLarge = 24.0;

  /// Section 标题装饰圆角
  static const double radiusSection = 2.0;

  // ==================== 组件尺寸 ====================
  /// 头像尺寸
  static const double avatarSize = 64.0;
  static const double avatarIconSize = 32.0;

  /// 统计图标容器
  static const double statIconSize = 28.0;
  static const double statIconIconSize = 18.0;

  /// 功能列表图标容器
  static const double listIconSize = 36.0;
  static const double listIconIconSize = 22.0;

  /// 快捷操作图标容器
  static const double quickActionIconSize = 48.0;
  static const double quickActionIconIconSize = 24.0;

  /// 告警/设备图标容器
  static const double alarmIconSize = 44.0;
  static const double alarmIconIconSize = 24.0;

  /// 播放按钮
  static const double playButtonSize = 40.0;
  static const double playButtonIconSize = 22.0;

  /// 小按钮
  static const double smallButtonSize = 44.0;
  static const double smallButtonIconSize = 22.0;

  // ==================== 其他尺寸 ====================
  /// Tab 指示器粗细
  static const double tabIndicatorWeight = 3.0;

  /// Section 标题装饰宽度
  static const double sectionTitleDecorationWidth = 4.0;

  /// Section 标题装饰高度
  static const double sectionTitleDecorationHeight = 18.0;

  /// 按压动画缩放比例
  static const double pressScale = 0.95;

  /// 按压动画持续时间
  static const Duration pressDuration = Duration(milliseconds: 100);

  /// 图标背景 alpha 值
  static const double iconBackgroundAlpha = 0.1;
  static const double iconBackgroundAlphaActive = 0.15;
}
