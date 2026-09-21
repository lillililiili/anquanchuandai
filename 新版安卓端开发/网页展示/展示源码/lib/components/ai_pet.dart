import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'field_motion.dart';

class AiPetSettings extends ChangeNotifier {
  static final instance = AiPetSettings();
  bool hidden = false, right = true;
  double height = .38;
  int seconds = 20;
  Future<void>? _loading;
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    hidden = prefs.getBool('ai_pet_hidden') ?? false;
    right = prefs.getBool('ai_pet_right') ?? true;
    height = (prefs.getDouble('ai_pet_height') ?? .38).clamp(0, 1);
    final saved = prefs.getInt('ai_pet_interval') ?? 20;
    seconds = [0, 10, 20, 30, 60, 180].contains(saved) ? saved : 20;
    notifyListeners();
  }

  Future<void> update({
    bool? hide,
    bool? side,
    double? position,
    int? interval,
  }) async {
    await load();
    hidden = hide ?? hidden;
    right = side ?? right;
    height = position ?? height;
    seconds = interval ?? seconds;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_pet_hidden', hidden);
    await prefs.setBool('ai_pet_right', right);
    await prefs.setDouble('ai_pet_height', height);
    if (interval != null) await prefs.setInt('ai_pet_interval', seconds);
  }
}

Future<void> showAiPetSettings(BuildContext context) async {
  final settings = AiPetSettings.instance;
  await settings.load();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) => AlertDialog(
        title: const Text('精灵设置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示侧边精灵'),
                value: !settings.hidden,
                onChanged: (v) => settings.update(hide: !v),
              ),
              const Text('闲置时做一次短动作；后台或系统减少动画时停止。'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final seconds in [10, 20, 30, 60, 180, 0])
                    ChoiceChip(
                      label: Text(
                        seconds == 0
                            ? '不动'
                            : seconds < 60
                            ? '$seconds 秒'
                            : '${seconds ~/ 60} 分钟',
                      ),
                      selected: settings.seconds == seconds,
                      onSelected: (_) => settings.update(interval: seconds),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    ),
  );
}

enum AiPetAction { rest, twist, wave, yawn, stretch, typing }

/// Only this small repaint boundary animates; no chat or page state is replaced.
class AiPetAvatar extends StatefulWidget {
  const AiPetAvatar({
    super.key,
    this.busy = false,
    this.idleSeconds = 0,
    this.size = 32,
    this.seated = false,
    this.active = true,
    this.tapSerial = 0,
  });
  final bool busy;
  final bool active;
  final int tapSerial;
  final int idleSeconds;
  final double size;
  final bool seated;
  @override
  State<AiPetAvatar> createState() => _AiPetAvatarState();
}

class _AiPetAvatarState extends State<AiPetAvatar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  Timer? timer;
  AiPetAction action = AiPetAction.rest;
  AiPetAction? lastIdle;
  bool nextWave = false;
  final random = math.Random();
  bool foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool allowed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed && !widget.busy) {
        action = AiPetAction.rest;
        animation.value = 0;
        waitForIdle();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TickerMode.of(context) && !MotionPolicy.reduced(context);
    if (next != allowed) {
      allowed = next;
      schedule();
    }
  }

  @override
  void didUpdateWidget(AiPetAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy != widget.busy ||
        oldWidget.active != widget.active ||
        oldWidget.idleSeconds != widget.idleSeconds)
      schedule();
    if (oldWidget.tapSerial != widget.tapSerial) {
      // Opening the retained panel enables its TickerMode in this same frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) react();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final next = state == AppLifecycleState.resumed;
    if (foreground == next) return;
    foreground = next;
    schedule();
  }

  bool get enabled => allowed && foreground && widget.active;

  void waitForIdle() {
    timer?.cancel();
    if (!enabled || widget.busy || widget.idleSeconds <= 0) return;
    timer = Timer(Duration(seconds: widget.idleSeconds), () {
      final choices = [
        AiPetAction.twist,
        AiPetAction.yawn,
        AiPetAction.stretch,
      ].where((a) => a != lastIdle).toList();
      lastIdle = choices[random.nextInt(choices.length)];
      play(lastIdle!, 2600);
    });
  }

  void play(AiPetAction next, int milliseconds) {
    timer?.cancel();
    action = next;
    animation.duration = Duration(milliseconds: milliseconds);
    animation.forward(from: 0);
  }

  void react() {
    if (!enabled ||
        widget.busy ||
        (animation.isAnimating &&
            (action == AiPetAction.wave || action == AiPetAction.twist) &&
            animation.duration?.inMilliseconds == 1500))
      return;
    play(nextWave ? AiPetAction.wave : AiPetAction.twist, 1500);
    nextWave = !nextWave;
  }

  void schedule() {
    timer?.cancel();
    animation.stop();
    action = AiPetAction.rest;
    animation.value = 0;
    if (!enabled) return;
    if (widget.busy) {
      action = AiPetAction.typing;
      animation.duration = const Duration(milliseconds: 1200);
      animation.repeat();
    } else {
      waitForIdle();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: animation,
      builder: (_, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _PetPainter(animation.value, action, widget.seated),
      ),
    ),
  );
}

class _PetPainter extends CustomPainter {
  _PetPainter(this.frame, this.action, this.seated);
  final bool seated;
  final double frame;
  final AiPetAction action;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    // Integer-grid poses preserve the pixel silhouette at small sizes.
    final beat = (frame * 8).floor();
    final moving = frame > 0 && frame < 1;
    final wave = action == AiPetAction.wave && moving;
    final yawn = action == AiPetAction.yawn && frame > .2 && frame < .85;
    final stretch = action == AiPetAction.stretch && moving;
    final busy = action == AiPetAction.typing;
    final blink = yawn || (frame > .18 && frame < .3);
    final paint = Paint()..isAntiAlias = false;
    const ink = Color(0xFF20304C),
        cyan = Color(0xFF2CCCE4),
        light = Color(0xFFACF5FF),
        face = Color(0xFF34516C);
    void block(double x, double y, double w, double h, Color color) {
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
    }

    // Feet remain anchored to the panel; only the upper body sways.
    block(9, 27, 4, seated ? 5 : 3, ink);
    block(19, 27, 4, seated ? 5 : 3, ink);
    canvas.save();
    final sway = action == AiPetAction.twist
        ? (math.sin(frame * math.pi * 4) * 2).roundToDouble()
        : 0.0;
    canvas.translate(
      sway,
      stretch ? -math.sin(frame * math.pi).roundToDouble() : 0,
    );

    block(9, 3, 14, 2, ink);
    block(6, 5, 20, 3, ink);
    block(4, 8, 24, 15, ink);
    block(7, 23, 18, 4, ink);
    block(9, 5, 14, 3, cyan);
    block(6, 8, 20, 3, cyan);
    block(14, 4, 4, 7, light);
    block(3, 11, 26, 3, light);
    block(6, 15, 20, 8, face);
    block(9, blink ? 19 : 16, 3, blink ? 1 : 4, light);
    block(21, blink ? 19 : 16, 3, blink ? 1 : 4, light);
    block(14, yawn ? 20 : 21, yawn ? 4 : 5, yawn ? 4 : 1, light);
    block(10, 24, 13, 3, cyan);
    if (busy) {
      block(4, 28, 24, 3, ink);
      for (var i = 0; i < 6; i++) {
        block(6 + i * 3, 29, 2, 1, light);
      }
      block(4, beat.isEven ? 24 : 26, 5, 3, cyan);
      block(23, beat.isEven ? 26 : 24, 5, 3, cyan);
    } else if (yawn) {
      block(15, 22, 5, 4, cyan);
      block(27, 22, 3, 3, cyan);
    } else if (stretch) {
      final lift = (math.sin(frame * math.pi) * 14).roundToDouble();
      block(1, 22 - lift, 3, 5, cyan);
      block(28, 22 - lift, 3, 5, cyan);
    } else {
      // Resting hands perch at the body edge; a finite idle pose waves.
      block(1, wave && beat.isEven ? 16 : 22, 4, 5, ink);
      block(2, wave && beat.isEven ? 16 : 22, 3, 3, cyan);
      block(27, 22, 4, 5, ink);
      block(27, 22, 3, 3, cyan);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PetPainter old) =>
      old.frame != frame || old.action != action || old.seated != seated;
}

class AiPetDock extends StatefulWidget {
  const AiPetDock({
    super.key,
    required this.visible,
    required this.onOpen,
    required this.onSettings,
  });
  final bool visible;
  final VoidCallback onOpen, onSettings;
  @override
  State<AiPetDock> createState() => _AiPetDockState();
}

class _AiPetDockState extends State<AiPetDock> {
  final settings = AiPetSettings.instance;
  Offset? drag;
  @override
  void initState() {
    super.initState();
    settings.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      if (!widget.visible || settings.hidden) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, limits) {
          final media = MediaQuery.of(context);
          final minY = media.padding.top + 80;
          final maxY = math.max(
            minY,
            limits.maxHeight - media.padding.bottom - 160,
          );
          // Keep the draggable target out of Android's edge-back gesture strip.
          final minX = media.systemGestureInsets.left;
          final maxX = math.max(
            minX,
            limits.maxWidth - 56 - media.systemGestureInsets.right,
          );
          final y = (drag?.dy ?? minY + (maxY - minY) * settings.height).clamp(
            minY,
            maxY,
          );
          final x = (drag?.dx ?? (settings.right ? maxX : minX)).clamp(
            minX,
            maxX,
          );
          return Stack(
            children: [
              Positioned(
                left: x,
                top: y,
                child: Tooltip(
                  message: '打开 AI 助手',
                  child: Semantics(
                    container: true,
                    button: true,
                    label: 'AI 助手精灵，点击聊天，拖动换位置，长按设置',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onOpen,
                      onLongPress: widget.onSettings,
                      onPanUpdate: (d) => setState(
                        () => drag = Offset(
                          ((drag?.dx ?? x) + d.delta.dx).clamp(minX, maxX),
                          ((drag?.dy ?? y) + d.delta.dy).clamp(minY, maxY),
                        ),
                      ),
                      onPanEnd: (_) {
                        final end = drag ?? Offset(x, y);
                        settings
                            .update(
                              side: end.dx + 28 > limits.maxWidth / 2,
                              position: maxY == minY
                                  ? 0
                                  : (end.dy - minY) / (maxY - minY),
                            )
                            .then((_) {
                              if (mounted) setState(() => drag = null);
                            });
                      },
                      onPanCancel: () => setState(() => drag = null),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: Center(
                          child: AiPetAvatar(
                            size: 48,
                            idleSeconds: drag == null ? settings.seconds : 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

