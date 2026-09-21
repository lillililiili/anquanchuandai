import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'field_motion.dart';

/// Decorative light only: never represents device connectivity or telemetry.
class TechAura extends StatefulWidget {
  const TechAura({super.key, this.orb = false, this.active = true});
  final bool orb;
  final bool active;
  @override
  State<TechAura> createState() => _TechAuraState();
}

class _TechAuraState extends State<TechAura>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController clock;
  Timer? rest;
  bool foreground = true;
  bool running = false;
  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    clock.addStatusListener((status) {
      if (status == AnimationStatus.completed && running)
        rest = Timer(const Duration(seconds: 2), () {
          if (mounted && running) clock.forward(from: 0);
        });
    });
    WidgetsBinding.instance.addObserver(this);
  }

  void sync() {
    final next =
        widget.active &&
        foreground &&
        TickerMode.of(context) &&
        !MotionPolicy.reduced(context);
    if (next == running) return;
    running = next;
    rest?.cancel();
    if (next) {
      clock.forward(from: clock.isCompleted ? 0 : clock.value);
    } else {
      clock.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(TechAura old) {
    super.didUpdateWidget(old);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (mounted) sync();
  }

  @override
  void dispose() {
    rest?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AuraPainter(
            clock,
            Theme.of(context).colorScheme.primary,
            widget.orb,
          ),
          size: Size.infinite,
        ),
      ),
    ),
  );
}

class _AuraPainter extends CustomPainter {
  _AuraPainter(this.clock, this.color, this.orb) : super(repaint: clock);
  final Animation<double> clock;
  final Color color;
  final bool orb;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = clock.value * math.pi * 2;
    final center = Offset(size.width * (orb ? .5 : .78), size.height * .5);
    final r = math.min(size.width, size.height) * (orb ? .32 : .38);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: orb ? .32 : .18),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r * 1.8));
    canvas.drawCircle(center, r * 1.8, glow);
    if (orb) {
      canvas.drawCircle(
        center,
        r * .74,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.4, -.5),
            colors: [
              Colors.white,
              color.withValues(alpha: .3),
              color.withValues(alpha: .9),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r * .74)),
      );
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t);
    for (var i = 0; i < 3; i++) {
      final ring = Rect.fromCenter(
        center: Offset.zero,
        width: r * 2 * (1 + i * .22),
        height: r * 2 * (orb ? 1 : .56) * (1 + i * .22),
      );
      canvas.drawArc(
        ring,
        i * 2.1,
        math.pi * (i == 1 ? 1.15 : .65),
        false,
        Paint()
          ..color = color.withValues(alpha: i == 1 ? 0.48 : 0.23)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (i == 1 ? 1.5 : 0.7)
          ..strokeCap = StrokeCap.round,
      );
    }
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      canvas.drawCircle(
        Offset(math.cos(a) * r, math.sin(a) * r * (orb ? 1 : .56)),
        i == 0 ? 3 : 1.5,
        Paint()..color = i == 0 ? color : color.withValues(alpha: .45),
      );
    }
    canvas.restore();
    if (!orb) {
      final x = size.width * (.45 + .48 * clock.value);
      canvas.drawRect(
        Rect.fromLTWH(x - 18, 0, 36, size.height),
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: .12),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(x - 18, 0, 36, size.height)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuraPainter old) =>
      old.color != color || old.orb != orb || old.clock != clock;
}

/// A stable surface around existing content; overlays do not capture gestures.
class TechSurface extends StatelessWidget {
  const TechSurface({
    super.key,
    required this.child,
    this.animated = false,
    this.radius = 20,
  });
  final Widget child;
  final bool animated;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .07),
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: color.withValues(alpha: .16)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: .045),
                        Colors.transparent,
                        color.withValues(alpha: .025),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (animated) const Positioned.fill(child: TechAura()),
          ],
        ),
      ),
    );
  }
}
