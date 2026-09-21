import 'package:flutter/material.dart';

/// 阴影样式定义
class AppShadows {
  AppShadows._();

  /// 标准卡片阴影
  static List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0A000000), // ~0.04 alpha
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  /// 轻阴影（用于悬浮元素）
  static List<BoxShadow> light = [
    BoxShadow(
      color: Color(0x08000000), // ~0.03 alpha
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  /// 重阴影（用于模态框/弹窗）
  static List<BoxShadow> heavy = [
    BoxShadow(
      color: Color(0x1A000000), // ~0.1 alpha
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  /// 悬浮按钮阴影
  static List<BoxShadow> fab = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 12,
      offset: const Offset(0, 6),
    ),
  ];

  /// 暗色主题下的发光效果
  static List<BoxShadow> glow = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 15,
      offset: const Offset(0, 4),
    ),
  ];
}
