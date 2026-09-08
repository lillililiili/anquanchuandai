import 'package:flutter/material.dart';

// 🔥 核心：给所有 Widget 加上链式样式方法
extension TailwindStyle on Widget {
  // --- 间距 (Padding/Margin) ---
  Widget p(double v) => Padding(padding: EdgeInsets.all(v), child: this);
  Widget px(double v) => Padding(
    padding: EdgeInsets.symmetric(horizontal: v),
    child: this,
  );
  Widget py(double v) => Padding(
    padding: EdgeInsets.symmetric(vertical: v),
    child: this,
  );
  Widget pt(double v) => Padding(
    padding: EdgeInsets.only(top: v),
    child: this,
  );
  Widget pb(double v) => Padding(
    padding: EdgeInsets.only(bottom: v),
    child: this,
  );

  Widget m(double v) => Container(margin: EdgeInsets.all(v), child: this);
  Widget mx(double v) => Container(
    margin: EdgeInsets.symmetric(horizontal: v),
    child: this,
  );
  Widget my(double v) => Container(
    margin: EdgeInsets.symmetric(vertical: v),
    child: this,
  );

  // --- 颜色 (Background) ---
  Widget bg(Color c) => Container(color: c, child: this);
  Widget bgTransparent() => Container(color: Colors.transparent, child: this);

  // 模拟 Tailwind 颜色 (你可以扩展更多)
  Widget bgRed({int shade = 500}) => bg(_colors['red']?[shade] ?? Colors.red);
  Widget bgBlue({int shade = 500}) =>
      bg(_colors['blue']?[shade] ?? Colors.blue);
  Widget bgWhite() => bg(Colors.white);
  Widget bgBlack() => bg(Colors.black);

  // --- 尺寸 (Width/Height) ---
  Widget w(double v) => SizedBox(width: v, child: this);
  Widget h(double v) => SizedBox(height: v, child: this);
  Widget sizedBox({double? w, double? h}) =>
      SizedBox(width: w, height: h, child: this);
  Widget expanded() => Expanded(child: this);
  Widget flexible({int flex = 1}) => Flexible(flex: flex, child: this);

  // --- 圆角 (Radius) ---
  Widget rounded({double r = 8.0}) =>
      ClipRRect(borderRadius: BorderRadius.circular(r), child: this);
  Widget circle() => ClipOval(child: this);

  // --- 对齐 (Alignment) ---
  Widget center() => Center(child: this);
  Widget alignTopLeft() => Align(alignment: Alignment.topLeft, child: this);
  Widget alignCenterRight() =>
      Align(alignment: Alignment.centerRight, child: this);

  // --- 装饰 (Decoration - 高级) ---
  Widget card({Color? color, double radius = 12, List<BoxShadow>? shadows}) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow:
            shadows ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
      ),
      child: this,
    );
  }
}

// 简单的颜色映射表 (模拟 Tailwind 色板)
final Map<String, Map<int, Color>> _colors = {
  'red': {
    50: const Color(0xFFFEF2F2),
    500: const Color(0xFFEF4444),
    900: const Color(0xFF7F1D1D),
  },
  'blue': {
    50: const Color(0xFFEFF6FF),
    500: const Color(0xFF3B82F6),
    900: const Color(0xFF1E3A8A),
  },
};
