import 'package:flutter/material.dart';

/// CARGO 参考色板：亮青操作、海军蓝文字、浅灰内容背景。
/// 包含明亮主题和暗色主题的所有颜色
class SpringColors {
  SpringColors._();

  // ==================== 主题色 ====================
  /// 亮青 - 主操作色（保留原公共字段）
  static const Color mintGreen = Color(0xFF35CFF1);
  static const Color mintGreenLight = Color(0xFF70DEF4);
  static const Color mintGreenDark = Color(0xFF14758C);

  /// 统一交互强调色
  static const Color skyBlue = Color(0xFF35CFF1);
  static const Color skyBlueLight = Color(0xFF70DEF4);
  static const Color skyBlueDark = Color(0xFF14758C);

  /// 嫩芽黄 - 强调色
  static const Color sproutYellow = Color(0xFFF59E0B);
  static const Color sproutYellowLight = Color(0xFFFBBF24);
  static const Color sproutYellowDark = Color(0xFFD97706);

  /// 樱桃红 - 告警/危险色
  static const Color cherryRed = Color(0xFFDC2626);
  static const Color cherryRedLight = Color(0xFFEF4444);
  static const Color cherryRedDark = Color(0xFFB91C1C);

  // ==================== 背景色 ====================
  /// 明亮主题背景
  static const Color backgroundLight = Color(0xFFF6F8FC);
  static const Color homeBackgroundLight = Color(0xFFF6F8FC);
  static const Color cardBackgroundLight = Color(0xFFFFFFFF);

  /// 暗色主题背景
  static const Color backgroundDark = Color(0xFF141D31);
  static const Color surfaceDark = Color(0xFF202B46);
  static const Color cardBackgroundDark = Color(0xFF26344F);

  // ==================== 文字颜色 ====================
  /// 明亮主题文字
  static const Color textPrimaryLight = Color(0xFF202B46);
  static const Color textSecondaryLight = Color(0xFF56637A);
  static const Color textTertiaryLight = Color(0xFF69768A);
  static const Color textDisabledLight = Color(0xFF9CA3AF);

  /// 暗色主题文字
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFB0B0B0);
  static const Color textTertiaryDark = Color(0xFF808080);
  static const Color textDisabledDark = Color(0xFF606060);

  // ==================== 功能色 ====================
  /// 告警类型颜色
  static const Color alarmSOS = Color(0xFFDC2626);
  static const Color alarmFall = Color(0xFFF59E0B);
  static const Color alarmGeoFence = Color(0xFF8B5CF6);
  static const Color alarmLowBattery = Color(0xFF69768A);

  /// 快捷操作颜色
  static const Color actionCheckIn = Color(0xFF35CFF1);
  static const Color actionMonitor = Color(0xFF35CFF1);
  static const Color actionIntercom = Color(0xFF8B5CF6);
  static const Color actionTrack = Color(0xFFF59E0B);
  static const Color actionFence = Color(0xFFEF4444);
  static const Color actionAlarm = Color(0xFFEC4899);

  // ==================== 其他 UI 元素 ====================
  /// 分割线
  static const Color dividerLight = Color(0x14000000); // ~0.08 alpha
  static const Color dividerDark = Color(0x1FFFFFFF);

  /// 图标背景 alpha 值
  static const double iconBackgroundAlpha = 0.1;
  static const double iconBackgroundAlphaActive = 0.15;

  // ==================== 暗色主题适配色 ====================
  /// 暗色主题下的主题色（降低饱和度）
  static const Color mintGreenDarkTheme = Color(0xFF70DEF4);
  static const Color skyBlueDarkTheme = Color(0xFF70DEF4);
  static const Color sproutYellowDarkTheme = Color(0xFFFBBF24);
  static const Color cherryRedDarkTheme = Color(0xFFEF4444);

  /// 获取暗色主题下的主题色
  static Color getPrimaryColor(bool isDark) =>
      isDark ? mintGreenDarkTheme : mintGreen;
  static Color getSecondaryColor(bool isDark) =>
      isDark ? skyBlueDarkTheme : skyBlue;
  static Color getAccentColor(bool isDark) =>
      isDark ? sproutYellowDarkTheme : sproutYellow;
  static Color getErrorColor(bool isDark) =>
      isDark ? cherryRedDarkTheme : cherryRed;

  /// 获取薄荷绿（适配暗色主题）
  static Color getMintColor(bool isDark) =>
      isDark ? mintGreenDarkTheme : mintGreen;

  /// 获取快捷操作颜色
  static Color getActionColor(String label) {
    final colorMap = {
      '打卡签到': actionCheckIn,
      '实时监控': actionMonitor,
      '集群对讲': actionIntercom,
      '轨迹回放': actionTrack,
      '电子围栏': actionFence,
      '告警记录': actionAlarm,
    };
    return colorMap[label] ?? const Color(0xFF69768A);
  }
}
