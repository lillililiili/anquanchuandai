---
name: "ui-design"
description: "UI 设计系统规范 Skill - 提供 Flutter 应用 UI 设计语言规范，包含颜色、间距、字体、圆角、阴影等核心设计元素的定义和使用指南。触发命令：/ui-design 或 /ui 或 /design-system。"
---

# Flutter 应用 UI 设计语言规范

*核心设计：春天色系（基于自然色彩的 Flutter 设计系统），AI 开发直接引用本规范，无需查阅源代码。*

## 一、颜色系统

### 1.1 主题色（春天色系）

|颜色名称|变量名|色值|用途|
|---|---|---|---|
|薄荷绿|mintGreen|#10B981|主色调、成功状态|
|天蓝色|skyBlue|#3B82F6|次要色调、链接/操作|
|嫩芽黄|sproutYellow|#F59E0B|强调色、警告状态|
|樱桃红|cherryRed|#DC2626|错误色、危险警告|
### 1.2 背景色/文字色/分割线

|类型|场景/层级|明亮模式|暗色模式|用途|
|---|---|---|---|---|
|背景色|页面背景|#F9FBF9|#121212|整体页面底色|
||首页背景|#F5F6FA|#121212|首页专属底色|
||卡片背景|#FFFFFF|#2C2C2C|卡片容器底色|
||表面色|-|#1E1E1E|暗色模式表面元素|
|文字色|主文字|#1F2937|#FFFFFF|标题、重要内容|
||次要文字|#4B5563|#B0B0B0|副标题、描述|
||第三文字|#6B7280|#808080|辅助信息、时间|
||禁用文字|#9CA3AF|#606060|不可用状态文字|
|分割线|-|Color(0x14000000)|Color(0x1FFFFFFF)|元素分隔|
### 1.3 功能色（核心）

```dart
// 告警类型
alarmSOS: #DC2626, alarmFall: #F59E0B, alarmGeoFence: #8B5CF6, alarmLowBattery: #6B7280
// 快捷操作
actionCheckIn: #10B981, actionMonitor: #3B82F6, actionIntercom: #8B5CF6, actionTrack: #F59E0B
```

## 二、间距与尺寸（4px网格规范）

### 2.1 标准间距/圆角/组件尺寸

|类型|变量|值|用途|
|---|---|---|---|
|标准间距|xs|4px|极小间距|
||sm|8px|小间距|
||md|12px|中等间距|
||lg|16px|标准间距|
||xl|20px|大间距|
||xxl|24px|超大间距|
|圆角|radiusSmall|10px|按钮、小标签|
||radiusMedium|12px|输入框、内部元素|
||radiusLarge|16px|主卡片|
||radiusXLarge|24px|页面级容器|
|组件尺寸|头像|容器64px、图标32px|用户头像|
||列表图标|容器44px、图标22px|列表项图标|
||快捷操作|容器48px、图标24px|快捷功能按钮|
||按钮|主按钮48px、小按钮36px|操作按钮|
### 2.2 核心代码规范

```dart
// 卡片边距
cardPadding: EdgeInsets.all(16px), cardPaddingLarge: EdgeInsets.all(20px), cardMargin: EdgeInsets.all(16px)
// 动画与透明度
pressScale: 0.95, pressDuration: 100ms, iconBackgroundAlpha: 0.1, iconBackgroundAlphaActive: 0.15
```

## 三、字体排印

|样式|字号|字重|用途|
|---|---|---|---|
|headlineLarge|20px|bold|大标题（用户名等）|
|headlineMedium|18px|w600|页面标题（AppBar）|
|title|16px|w600|卡片标题|
|body|15px|w600|列表项标题|
|button|14px|w600|按钮文字|
字体：fontFamily: 'Roboto'；使用方式：Text('内容', style: AppTypography.样式名)

## 四、阴影效果（核心类型）

```dart
// 标准卡片阴影
AppShadows.card = [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4))]
// 轻阴影（悬浮元素）
AppShadows.light = [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))]
// 重阴影（模态框）
AppShadows.heavy = [BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 8))]
```

## 五、主题系统（核心用法）

```dart
// 获取主题（HookWidget中）
final theme = useTheme(); // 包含primary、background、textPrimary等核心属性
// 主题切换
ThemeModeSignal.toggleTheme(); // 切换明暗主题
ThemeModeSignal.setThemeMode(ThemeMode.dark); // 手动设置主题
```

## 六、核心组件规范（关键代码）

```dart
// 标准卡片
Container(margin: AppSpacing.cardMargin, padding: AppSpacing.cardPaddingLarge,
  decoration: BoxDecoration(color: theme.cardBackground, borderRadius: BorderRadius.circular(AppSpacing.radiusLarge), boxShadow: AppShadows.card))
// 主按钮（带按压缩放）
GestureDetector(onTap: onTap, child: AnimatedScale(
  scale: isPressed ? AppSpacing.pressScale : 1, duration: AppSpacing.pressDuration,
  child: Container(height: 48, decoration: BoxDecoration(color: SpringColors.skyBlue, borderRadius: BorderRadius.circular(AppSpacing.radiusMedium)),
    child: Center(child: Text(label, style: AppTypography.button.copyWith(color: Colors.white))))))
// AppBar
AppBar(backgroundColor: theme.background, elevation: 0, title: Text('标题', style: AppTypography.headlineMedium), centerTitle: true)
```

## 七、快速参考

1. 间距速查：xs=4px、sm=8px、md=12px、lg=16px、xl=20px、xxl=24px

2. 圆角速查：small=10px、medium=12px、large=16px、xLarge=24px

3. 主题色速查：theme.background（背景）、theme.textPrimary（主文字）、theme.cardBackground（卡片背景）
> （注：文档部分内容可能由 AI 生成）