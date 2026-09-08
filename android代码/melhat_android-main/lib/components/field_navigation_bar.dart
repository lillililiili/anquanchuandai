import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'field_motion.dart';

/// One moving selection surface; navigation callbacks never wait for animation.
class FieldNavigationBar extends StatelessWidget {
  const FieldNavigationBar({
    super.key,
    required this.selected,
    required this.labels,
    required this.icons,
    required this.onSelected,
  });
  final int selected;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth / labels.length;
              final visualIndex =
                  Directionality.of(context) == TextDirection.rtl
                  ? labels.length - 1 - selected
                  : selected;
              return Stack(
                children: [
                  MotionSpringValue(
                    value: visualIndex.toDouble(),
                    builder: (context, position, child) {
                      final stretch = MotionPolicy.reduced(context)
                          ? 0.0
                          : (visualIndex - position).abs().clamp(0.0, 1.0) * 12;
                      final indicatorWidth = math.min(51 + stretch, width - 8);
                      final center = width * (position + .5);
                      return Positioned(
                        left: (center - indicatorWidth / 2).clamp(
                          0.0,
                          constraints.maxWidth - indicatorWidth,
                        ),
                        top: 6,
                        child: IgnorePointer(
                          child: Container(
                            key: const ValueKey('navigation-indicator'),
                            width: indicatorWidth,
                            height: 31,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(labels.length, (index) {
                      final active = index == selected;
                      return Expanded(
                        child: Semantics(
                          selected: active,
                          button: true,
                          child: MotionPress(
                            child: InkWell(
                              onTap: () => onSelected(index),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 31,
                                      child: Center(
                                        child: MotionSpringValue(
                                          value: active ? 1 : 0,
                                          builder: (context, value, child) =>
                                              Transform.translate(
                                                offset: Offset(
                                                  0,
                                                  MotionPolicy.reduced(context)
                                                      ? 0
                                                      : -2 *
                                                            math.sin(
                                                              math.pi *
                                                                  value.clamp(
                                                                    0.0,
                                                                    1.0,
                                                                  ),
                                                            ),
                                                ),
                                                child: Transform.scale(
                                                  scale:
                                                      MotionPolicy.reduced(
                                                        context,
                                                      )
                                                      ? 1
                                                      : 1 + .06 * value,
                                                  child: child,
                                                ),
                                              ),
                                          child: Icon(
                                            icons[index],
                                            size: 23,
                                            color: active
                                                ? colors.onSurface
                                                : colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      labels[index],
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: active
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: active
                                            ? colors.onSurface
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
