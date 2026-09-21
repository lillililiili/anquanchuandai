import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 脉冲动画组件
///
/// 用于麦克风按钮的呼吸效果
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final bool isAnimating;
  final double minScale;
  final double maxScale;
  final Duration duration;

  const PulseAnimation({
    super.key,
    required this.child,
    this.isAnimating = true,
    this.minScale = 1.0,
    this.maxScale = 1.15,
    this.duration = const Duration(milliseconds: 1000),
  });

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(
      begin: widget.minScale,
      end: widget.maxScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulseAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating != oldWidget.isAnimating) {
      if (widget.isAnimating) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isAnimating ? _animation.value : 1.0,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 波纹动画组件
///
/// 录音时的扩散波纹效果
class RippleAnimation extends StatefulWidget {
  final bool isAnimating;
  final Color color;
  final double size;
  final int ringCount;
  final Duration duration;

  const RippleAnimation({
    super.key,
    this.isAnimating = true,
    required this.color,
    this.size = 120,
    this.ringCount = 3,
    this.duration = const Duration(milliseconds: 2000),
  });

  @override
  State<RippleAnimation> createState() => _RippleAnimationState();
}

class _RippleAnimationState extends State<RippleAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    if (widget.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(RippleAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating != oldWidget.isAnimating) {
      if (widget.isAnimating) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAnimating) return const SizedBox.shrink();

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(widget.ringCount, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final delay = index * (1.0 / widget.ringCount);
              final progress = ((_controller.value + delay) % 1.0);
              final opacity = (1 - progress).clamp(0.0, 0.4);
              final scale = 0.5 + progress * 0.7;

              return Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withOpacity(opacity),
                      width: 2,
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

/// 音量指示器绘制器
class SoundLevelPainter extends CustomPainter {
  final double level;
  final Color color;
  final int segmentCount;

  SoundLevelPainter({
    required this.level,
    required this.color,
    this.segmentCount = 16,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final segmentAngle = (2 * math.pi) / segmentCount;
    final gapAngle = segmentAngle * 0.25;
    final arcAngle = segmentAngle - gapAngle;

    for (var i = 0; i < segmentCount; i++) {
      final startAngle = i * segmentAngle - math.pi / 2;
      final intensity = (math.sin(i * 0.4 + level * math.pi * 3) + 1) / 2;
      final segmentLevel = level * intensity;

      paint.color = color.withOpacity(0.15 + segmentLevel * 0.55);

      final segmentRadius = radius - 8 + segmentLevel * 12;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: segmentRadius),
        startAngle,
        arcAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SoundLevelPainter oldDelegate) {
    return oldDelegate.level != level;
  }
}

/// 音量指示器组件
class SoundLevelIndicator extends StatelessWidget {
  final double level;
  final Color color;
  final double size;

  const SoundLevelIndicator({
    super.key,
    required this.level,
    required this.color,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: level),
      duration: const Duration(milliseconds: 80),
      builder: (context, value, child) {
        return CustomPaint(
          size: Size(size, size),
          painter: SoundLevelPainter(level: value, color: color),
        );
      },
    );
  }
}

/// 波形绘制器
class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final int currentIndex;
  final Color color;
  final bool isActive;

  WaveformPainter({
    required this.waveformData,
    required this.currentIndex,
    required this.color,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final barWidth = size.width / waveformData.length;
    final centerY = size.height / 2;

    for (var i = 0; i < waveformData.length; i++) {
      final dataIndex = (currentIndex - waveformData.length + i + waveformData.length) % waveformData.length;
      final value = waveformData[dataIndex];

      final opacity = isActive ? 0.3 + (i / waveformData.length) * 0.7 : 0.2;
      paint.color = color.withOpacity(opacity);

      final height = math.max(4.0, value * (size.height - 8));
      final x = i * barWidth + barWidth / 2;

      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.currentIndex != currentIndex ||
        oldDelegate.isActive != isActive;
  }
}

/// 波形显示组件
class WaveformDisplay extends StatefulWidget {
  final double soundLevel;
  final Color color;
  final double height;
  final int barCount;
  final bool isActive;

  const WaveformDisplay({
    super.key,
    required this.soundLevel,
    required this.color,
    this.height = 60,
    this.barCount = 40,
    this.isActive = true,
  });

  @override
  State<WaveformDisplay> createState() => _WaveformDisplayState();
}

class _WaveformDisplayState extends State<WaveformDisplay> {
  late List<double> _waveformData;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _waveformData = List.filled(widget.barCount, 0.0);
  }

  @override
  void didUpdateWidget(WaveformDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.soundLevel != oldWidget.soundLevel) {
      _waveformData[_currentIndex] = widget.soundLevel;
      _currentIndex = (_currentIndex + 1) % _waveformData.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: widget.isActive
          ? CustomPaint(
              size: Size(double.infinity, widget.height),
              painter: WaveformPainter(
                waveformData: _waveformData,
                currentIndex: _currentIndex,
                color: widget.color,
                isActive: widget.isActive,
              ),
            )
          : Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.graphic_eq, color: Colors.grey.shade300, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    '波形显示',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }
}

/// 录音指示点动画
class RecordingDot extends StatefulWidget {
  final Color color;
  final double size;

  const RecordingDot({
    super.key,
    required this.color,
    this.size = 8,
  });

  @override
  State<RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<RecordingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.3 + _controller.value * 0.7),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

/// 进度环组件
class ProgressRing extends StatelessWidget {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final double size;
  final double strokeWidth;

  const ProgressRing({
    super.key,
    required this.progress,
    required this.color,
    this.backgroundColor = const Color(0xFFE0E0E0),
    this.size = 80,
    this.strokeWidth = 3,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: progress,
        strokeWidth: strokeWidth,
        backgroundColor: backgroundColor,
        valueColor: AlwaysStoppedAnimation<Color>(
          progress > 0.7 ? Colors.orange : color,
        ),
      ),
    );
  }
}

/// 文字渐入动画组件
class FadeInText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;

  const FadeInText({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      child: Text(
        text,
        key: ValueKey(text),
        style: style,
        textAlign: TextAlign.center,
      ),
    );
  }
}
