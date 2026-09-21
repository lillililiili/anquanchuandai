import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/app_copilot_portal.dart';
import 'package:rolling_intelligence_headband/store/user_store.dart';
import 'package:rolling_intelligence_headband/store/chat_store.dart';
import 'package:rolling_intelligence_headband/theme/app_theme.dart';
import 'package:rolling_intelligence_headband/components/field_assistant_action.dart';
import 'package:rolling_intelligence_headband/router/app_router.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(375, 812);
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });
  testWidgets('modal dialog suspends AI overlay and restores its draft', (
    tester,
  ) async {
    UserStore.instance.statusSignal.value = UserStatus.authorized;
    ChatStore.instance.setChatPanelOpen(true);
    addTearDown(() {
      fieldModalOpen.value = false;
      ChatStore.instance.setChatPanelOpen(false);
      UserStore.instance.statusSignal.value = UserStatus.unauthorized;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(),
        builder: (_, child) => AppCopilotPortal(child: child!),
      ),
    );
    await tester.pumpAndSettle();
    final pet = find.byKey(const ValueKey('ai-chat-perched-pet'));
    final surface = find.byKey(const ValueKey('ai-chat-surface'));
    expect(tester.getTopLeft(pet).dy, tester.getTopLeft(surface).dy - 40);
    expect(tester.getBottomRight(pet).dy, tester.getTopLeft(surface).dy + 8);
    await tester.enterText(find.byType(TextField), '草稿保留');
    final state = tester.state(find.byType(EditableText));
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pet).dy, greaterThanOrEqualTo(0));
    expect(tester.getTopLeft(pet).dy, tester.getTopLeft(surface).dy - 40);
    expect(tester.state(find.byType(EditableText)), same(state));
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();

    fieldModalOpen.value = true;
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起 AI 助手'), findsNothing);
    fieldModalOpen.value = false;
    await tester.pumpAndSettle();
    expect(find.text('草稿保留'), findsOneWidget);
    expect(tester.state(find.byType(EditableText)), same(state));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'assistant entry stays behind modal filters and returns when closed',
    (tester) async {
      UserStore.instance.statusSignal.value = UserStatus.authorized;
      addTearDown(
        () => UserStore.instance.statusSignal.value = UserStatus.unauthorized,
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [FieldModalObserver()],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheet) => TextButton(
                    onPressed: () => Navigator.pop(sheet),
                    child: const Text('关闭筛选'),
                  ),
                ),
                child: const Text('打开筛选'),
              ),
            ),
          ),
          builder: (_, child) => AppCopilotPortal(child: child!),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开 AI 助手'), findsOneWidget);
      await tester.tap(find.text('打开筛选'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开 AI 助手'), findsNothing);
      await tester.tap(find.text('关闭筛选'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开 AI 助手'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inline assistant entry opens and closes the shared panel', (
    tester,
  ) async {
    UserStore.instance.statusSignal.value = UserStatus.authorized;
    ChatStore.instance.setChatPanelOpen(false);
    addTearDown(() {
      UserStore.instance.statusSignal.value = UserStatus.unauthorized;
      ChatStore.instance.setChatPanelOpen(false);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          appBar: AppBar(actions: const [FieldAssistantAction()]),
          body: const Text('设备数据'),
        ),
        builder: (context, child) => AppCopilotPortal(child: child!),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(FieldAssistantAction),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('连接 AI 服务，开启对话'), findsOneWidget);
    await tester.tap(find.byTooltip('收起 AI 助手'));
    await tester.pumpAndSettle();
    expect(find.text('设备数据'), findsOneWidget);
    expect(ChatStore.isChatPanelOpen.value, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'portal outside Navigator renders tooltips and survives open close',
    (tester) async {
      UserStore.instance.statusSignal.value = UserStatus.authorized;
      ChatStore.instance.setChatPanelOpen(false);
      addTearDown(() {
        UserStore.instance.statusSignal.value = UserStatus.unauthorized;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Text('工作台')),
          builder: (context, child) => AppCopilotPortal(child: child!),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('打开 AI 助手'), findsOneWidget);
      await tester.tap(find.byTooltip('打开 AI 助手'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final dynamic petPainter = tester.widget<CustomPaint>(find.descendant(
        of: find.byKey(const ValueKey('ai-chat-perched-pet')),
        matching: find.byType(CustomPaint))).painter;
      expect(petPainter.action.toString(), 'AiPetAction.twist');
      await tester.pumpAndSettle();
      expect(find.text('连接 AI 服务，开启对话'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('收起 AI 助手'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开 AI 助手'), findsOneWidget);
      expect(find.text('工作台'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
