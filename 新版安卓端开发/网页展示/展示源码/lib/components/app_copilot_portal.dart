import 'ai_pet.dart';
import 'field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../store/chat_store.dart';
import '../store/user_store.dart';
import '../store/ai_config_store.dart';
import '../router/app_router.dart';
import '../router/route_tree.dart';
import '../views/chat/chat_page.dart';

/// 同一聊天实例保留在收展面板内；使用真实路由导航，避开键盘与透明叠层。
class AppCopilotPortal extends HookWidget {
  const AppCopilotPortal({
    super.key,
    required this.child,
    this.heightFactor = .7,
  });
  final Widget child;
  final double heightFactor;
  @override
  Widget build(BuildContext context) {
    final isExpanded = useState(ChatStore.isChatPanelOpen.value);
    final fullscreen = useState(false);
    final revision = useState(0);
    final petSettingsOpen = useState(false);
    final petTap = useState(0);
    final petSettingsState = useListenable(AiPetSettings.instance);
    final loggedIn = useIsLoggedIn();
    final modalOpen = useValueListenable(fieldModalOpen);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    useEffect(() {
      var active = true;
      var queued = false;
      void onRouteChanged() {
        // Router can notify while its child Navigator is building. Refresh the
        // outer portal after that frame, preserving the final matched route.
        if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
          if (queued) return;
          queued = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            queued = false;
            if (active) revision.value++;
          });
        } else {
          revision.value++;
        }
      }

      appRouter.routerDelegate.addListener(onRouteChanged);
      return () {
        active = false;
        appRouter.routerDelegate.removeListener(onRouteChanged);
      };
    }, []);
    final configuration = appRouter.routerDelegate.currentConfiguration;
    final path = configuration.isEmpty
        ? ''
        : configuration.last.matchedLocation;
    final store = AIConfigStore.instance;
    useEffect(() {
      final subscriptions = [
        ChatStore.isChatPanelOpen.subscribe((v) {
          isExpanded.value = v;
          if (v) AiPetSettings.instance.update(hide: false);
          if (!v) fullscreen.value = false;
        }),
        ChatStore.isTyping.subscribe((_) {
          revision.value++;
        }),
        ChatStore.isProcessing.subscribe((_) {
          revision.value++;
        }),
        store.apiKeySignal.subscribe((_) {
          revision.value++;
        }),
        store.baseUrlSignal.subscribe((_) {
          revision.value++;
        }),
        store.modelSignal.subscribe((_) {
          revision.value++;
        }),
      ];
      return () {
        for (final unsubscribe in subscriptions) {
          unsubscribe();
        }
      };
    }, []);
    final incomplete =
        store.apiKey.trim().isEmpty ||
        store.baseUrl.trim().isEmpty ||
        store.model.trim().isEmpty;
    final busy = ChatStore.isTyping.value || ChatStore.isProcessing.value;
    final available =
        (media.size.height - media.viewInsets.bottom - media.padding.top).clamp(
          0.0,
          media.size.height,
        );
    final height = fullscreen.value
        ? available
        : (media.size.height * heightFactor).clamp(0.0, available);
    void close() {
      ChatStore.instance.setChatPanelOpen(false);
      FocusScope.of(context).unfocus();
    }

    Future<void> clear() async {
      if (busy) return;
      final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
      if (navContext == null) return;
      final confirmed = await showDialog<bool>(
        context: navContext,
        builder: (dialog) => AlertDialog(
          title: const Text('清空聊天记录？'),
          content: const Text('将清除当前设备保存的这段会话。此操作不会撤销已经完成的业务操作。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('清空记录'),
            ),
          ],
        ),
      );
      if (confirmed == true) ChatStore.instance.clearMessages();
    }

    Future<void> petSettings() async {
      final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
      if (navContext == null) return;
      petSettingsOpen.value = true;
      try {
        await showAiPetSettings(navContext);
      } finally {
        if (context.mounted) petSettingsOpen.value = false;
      }
    }

    // MaterialApp.builder 位于路由 Navigator 外层，需要为浮层控件提供 Overlay。
    return Overlay.wrap(
      child: MotionActivity(
        child: Stack(
          children: [
            MotionActivity(child: child),
            if (loggedIn)
              AnimatedPositioned(
                duration: MotionPolicy.duration(context, MotionPolicy.panelMs),
                curve: MotionPolicy.panelCurve,
                left: 0,
                right: 0,
                bottom: media.viewInsets.bottom,
                child: MotionPanel(
                  visible: isExpanded.value && !modalOpen,
                  height: height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        top: 40,
                        child: Material(
                          key: const ValueKey('ai-chat-surface'),
                          color: scheme.surface,
                          elevation: 14,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SafeArea(
                            top: false,
                            child: Column(
                              children: [
                                const SizedBox(height: 10),
                                Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: scheme.outline,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    6,
                                    6,
                                    6,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'AI 助手',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: fullscreen.value
                                            ? '退出全屏'
                                            : '全屏',
                                        onPressed: () => fullscreen.value =
                                            !fullscreen.value,
                                        icon: AnimatedRotation(
                                          turns: fullscreen.value ? .5 : 0,
                                          duration: MotionPolicy.duration(
                                            context,
                                            MotionPolicy.panelMs,
                                          ),
                                          curve: MotionPolicy.releaseCurve,
                                          child: Icon(
                                            fullscreen.value
                                                ? Icons.fullscreen_exit
                                                : Icons.fullscreen,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: busy ? '回复完成后可清空' : '清空聊天记录',
                                        onPressed: busy ? null : clear,
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                      IconButton(
                                        tooltip: '收起 AI 助手',
                                        onPressed: close,
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                ),

                                if (incomplete)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      4,
                                    ),
                                    child: Material(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(16),
                                      child: InkWell(
                                        onTap: () {
                                          close();
                                          appRouter.push(
                                            RouteNode.aiConfig.url,
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.settings_outlined,
                                                size: 20,
                                                color: scheme.onSurface,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  '连接 AI 服务，开启对话',
                                                  style: TextStyle(
                                                    color: scheme.onSurface,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Text(
                                                '去配置',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right,
                                                color: scheme.onSurface,
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: MotionActivity(
                                    child: MediaQuery.removeViewInsets(
                                      context: context,
                                      removeBottom: true,
                                      child: ChatPage(
                                        showAppBar: false,
                                        enabled: !incomplete,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 24,
                        child: Tooltip(
                          message: '长按设置精灵',
                          child: GestureDetector(
                            onTap: () => petTap.value++,
                            onLongPress: petSettings,
                            behavior: HitTestBehavior.opaque,
                            child: AiPetAvatar(
                              key: const ValueKey('ai-chat-perched-pet'),
                              size: 48,
                              seated: true,
                              busy: busy,
                              active:
                                  isExpanded.value &&
                                  !modalOpen &&
                                  !petSettingsOpen.value,
                              idleSeconds: petSettingsState.seconds,
                              tapSerial: petTap.value,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned.fill(
              child: AiPetDock(
                visible:
                    loggedIn &&
                    (path.isEmpty || path.startsWith('/home/')) &&
                    !modalOpen &&
                    !petSettingsOpen.value &&
                    !isExpanded.value &&
                    media.viewInsets.bottom == 0 &&
                    media.orientation == Orientation.portrait,
                onOpen: () {
                  ChatStore.instance.setChatPanelOpen(true);
                  petTap.value++;
                },
                onSettings: petSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
