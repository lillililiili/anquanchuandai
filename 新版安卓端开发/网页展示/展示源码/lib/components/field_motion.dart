import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

abstract final class MotionPolicy {
  static const pressMs = 120;
  static const contentMs = 200;
  static const panelMs = 300;
  // Material separates spatial movement from non-overshooting visual effects.
  // These are local Flutter presets, not official Material spring tokens.
  static const panelCurve = Curves.easeOutCubic;
  static const releaseCurve = Curves.easeOutBack;
  static const effectsCurve = Curves.easeInOutCubic;
  static final spatialSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 600,
    ratio: .85,
  );
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  static Duration duration(BuildContext context, int milliseconds) =>
      Duration(milliseconds: reduced(context) ? 0 : milliseconds);
}

/// Pause descendant tickers off-route, in an inactive tab, or in the background.
class MotionActivity extends StatefulWidget {
  const MotionActivity({super.key, required this.child});
  final Widget child;
  @override
  State<MotionActivity> createState() => _MotionActivityState();
}

class _MotionActivityState extends State<MotionActivity>
    with WidgetsBindingObserver {
  bool active =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => active = state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled:
        active &&
        TickerMode.of(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true),
    child: widget.child,
  );
}

class MotionEntrance extends StatefulWidget {
  const MotionEntrance({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionPolicy.reduced(context) || !TickerMode.of(context)) {
      controller.value = 1;
      started = true;
    } else if (!started) {
      started = true;
      controller.forward();
    }
  }

  @override
  void initState() {
    super.initState();
    controller;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MotionPolicy.reduced(context);
    final start = (widget.index.clamp(0, 4) * 40) / 400;
    final animation = controller.drive(
      CurveTween(
        curve: Interval(
          start,
          (start + .6).clamp(0, 1),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
    return AnimatedBuilder(
      animation: animation,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: reduced ? 1 : animation.value,
        child: Transform.translate(
          offset: Offset(0, reduced ? 0 : 8 * (1 - animation.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Uses pointer observation only; the existing button retains its gesture action.
class MotionPress extends StatefulWidget {
  const MotionPress({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<MotionPress> createState() => _MotionPressState();
}

class _MotionPressState extends State<MotionPress> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled
        ? (_) => setState(() => pressed = true)
        : null,
    onPointerUp: (_) => setState(() => pressed = false),
    onPointerCancel: (_) => setState(() => pressed = false),
    child: AnimatedScale(
      scale: pressed && widget.enabled && !MotionPolicy.reduced(context)
          ? .98
          : 1,
      duration: MotionPolicy.duration(
        context,
        pressed ? MotionPolicy.pressMs : MotionPolicy.contentMs,
      ),
      curve: pressed ? Curves.easeOutCubic : MotionPolicy.releaseCurve,
      child: widget.child,
    ),
  );
}

/// Retargets from the current position and velocity, keeping the child mounted.
class MotionSpringValue extends StatefulWidget {
  const MotionSpringValue({
    super.key,
    required this.value,
    required this.builder,
    this.child,
  });
  final double value;
  final Widget? child;
  final Widget Function(BuildContext, double, Widget?) builder;
  @override
  State<MotionSpringValue> createState() => _MotionSpringValueState();
}

class _MotionSpringValueState extends State<MotionSpringValue>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController.unbounded(
    vsync: this,
    value: widget.value,
  );
  bool get staticState =>
      MotionPolicy.reduced(context) || !TickerMode.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (staticState) controller.value = widget.value;
  }

  @override
  void didUpdateWidget(MotionSpringValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (staticState) {
      controller.value = widget.value;
    } else if (oldWidget.value != widget.value) {
      final velocity = controller.velocity;
      controller.animateWith(
        SpringSimulation(
          MotionPolicy.spatialSpring,
          controller.value,
          widget.value,
          velocity,
          tolerance: const Tolerance(distance: .00001, velocity: .00001),
        ),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (context, child) =>
        widget.builder(context, controller.value, child),
  );
}

class MotionReveal extends StatefulWidget {
  const MotionReveal({super.key, required this.child});
  final Widget child;
  @override
  State<MotionReveal> createState() => _MotionRevealState();
}

class _MotionRevealState extends State<MotionReveal> {
  final childKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: childKey, child: widget.child);
    // A stable global subtree preserves focus/player state when accessibility
    // switches to static layout; zero-duration AnimatedSize fails during layout.
    return MotionPolicy.reduced(context)
        ? content
        : AnimatedSize(
            duration: const Duration(milliseconds: MotionPolicy.panelMs),
            curve: MotionPolicy.panelCurve,
            alignment: Alignment.topCenter,
            child: content,
          );
  }
}

/// Fade the updated content without replacing its state, focus or scroll position.
class MotionSwap extends StatefulWidget {
  const MotionSwap({super.key, required this.value, required this.child});
  final String value;
  final Widget child;
  @override
  State<MotionSwap> createState() => _MotionSwapState();
}

class _MotionSwapState extends State<MotionSwap>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: MotionPolicy.contentMs),
    value: 1,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionPolicy.reduced(context) || !TickerMode.of(context)) {
      controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(MotionSwap old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value &&
        !MotionPolicy.reduced(context) &&
        TickerMode.of(context)) {
      controller.forward(from: .4);
    }
  }

  @override
  void initState() {
    super.initState();
    controller;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: MotionPolicy.reduced(context)
        ? const AlwaysStoppedAnimation(1)
        : controller,
    child: widget.child,
  );
}

/// Keeps the same child mounted throughout closing and fullscreen transitions.
class MotionPanel extends StatefulWidget {
  const MotionPanel({
    super.key,
    required this.visible,
    required this.height,
    required this.child,
  });
  final bool visible;
  final double height;
  final Widget child;
  @override
  State<MotionPanel> createState() => _MotionPanelState();
}

class _MotionPanelState extends State<MotionPanel> {
  late bool hidden = !widget.visible;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionPolicy.reduced(context)) hidden = !widget.visible;
  }

  @override
  void didUpdateWidget(MotionPanel old) {
    super.didUpdateWidget(old);
    if (widget.visible) hidden = false;
    if (MotionPolicy.reduced(context)) hidden = !widget.visible;
  }

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: hidden && !widget.visible,
    child: IgnorePointer(
      ignoring: !widget.visible,
      child: ExcludeSemantics(
        excluding: !widget.visible,
        child: TickerMode(
          enabled: !hidden,
          child: AnimatedSlide(
            offset: widget.visible ? Offset.zero : const Offset(0, 1),
            duration: MotionPolicy.duration(context, MotionPolicy.panelMs),
            curve: MotionPolicy.panelCurve,
            onEnd: () {
              if (mounted && !widget.visible && !hidden) {
                setState(() => hidden = true);
              }
            },
            child: AnimatedContainer(
              duration: MotionPolicy.duration(context, MotionPolicy.panelMs),
              curve: MotionPolicy.panelCurve,
              height: widget.height,
              child: widget.child,
            ),
          ),
        ),
      ),
    ),
  );
}
