import 'package:flutter/material.dart';

import 'ui.dart';

/// Keeps the button above the page while its content scrolls independently.
class WearScrollToTop extends StatefulWidget {
  const WearScrollToTop({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<WearScrollToTop> createState() => _WearScrollToTopState();
}

class _WearScrollToTopState extends State<WearScrollToTop> {
  bool _visible = false;
  bool _updateQueued = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleUpdate);
    _scheduleUpdate();
  }

  @override
  void didUpdateWidget(WearScrollToTop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleUpdate);
      widget.controller.addListener(_scheduleUpdate);
    }
    _scheduleUpdate();
  }

  // Scroll metrics may change during layout (filtering, rotation, restoration).
  void _scheduleUpdate() {
    if (_updateQueued) return;
    _updateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateQueued = false;
      if (!mounted) return;
      final controller = widget.controller;
      final show =
          controller.hasClients &&
          controller.position.hasContentDimensions &&
          controller.position.viewportDimension > 0 &&
          controller.offset > controller.position.viewportDimension;
      if (show != _visible) setState(() => _visible = show);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _scheduleUpdate();
        return false;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_visible)
            Positioned(
              bottom: 16,
              right: 16,
              child: Material(
                color: Colors.white,
                elevation: 4,
                shadowColor: const Color(0x332F7BFF),
                shape: const CircleBorder(
                  side: BorderSide(color: Color(0xFFD4E4FF)),
                ),
                child: IconButton(
                  key: const ValueKey('wear-scroll-to-top'),
                  tooltip: '回到顶部',
                  color: WearColors.brand,
                  icon: const Icon(Icons.vertical_align_top_rounded),
                  onPressed: () {
                    if (!widget.controller.hasClients) return;
                    FocusScope.of(context).unfocus();
                    widget.controller.animateTo(
                      0,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
