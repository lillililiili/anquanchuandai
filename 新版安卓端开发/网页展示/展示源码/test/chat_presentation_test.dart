import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/chat_input_bar.dart';
import 'package:rolling_intelligence_headband/views/chat/chat_page.dart';
import 'package:rolling_intelligence_headband/theme/app_theme.dart';
import 'package:rolling_intelligence_headband/store/chat_store.dart';

void main() {
  testWidgets(
    'suggestion fills draft without sending; small viewport scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 570);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ChatStore.instance.clearMessages();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 570),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: ChatPage(showAppBar: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('跌倒告警如何处理？'));
      await tester.tap(find.text('跌倒告警如何处理？'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '跌倒告警如何处理？',
      );
      expect(ChatStore.messages.value, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'blank messages disabled; sends trimmed text and stops generation',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? sent;
      var stopped = false;
      Widget app(bool sending) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            onSend: ({content, message}) async {
              sent = content;
            },
            isSending: sending,
            onStop: () => stopped = true,
          ),
        ),
      );
      await tester.pumpWidget(app(false));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '发送消息',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '  设备离线  ');
      await tester.pump();
      await tester.tap(find.byTooltip('发送消息'));
      expect(sent, '设备离线');
      await tester.pumpWidget(app(true));
      await tester.tap(find.byTooltip('停止生成'));
      expect(stopped, isTrue);
    },
  );
  testWidgets('unconfigured AI permits draft editing and clearing but blocks send', (tester) async {
    final controller = TextEditingController(text: '跌倒告警如何处理？');
    addTearDown(controller.dispose);
    var sends = 0;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
      home: Scaffold(body: ChatInputBar(controller: controller, enabled: false,
        onSend: ({content, message}) async { sends++; }))));
    await tester.enterText(find.byType(TextField), '修改后的问题');
    expect(controller.text, '修改后的问题');
    await tester.pump();
    await tester.tap(find.byTooltip('清空输入'));
    expect(controller.text, isEmpty);
    await tester.enterText(find.byType(TextField), '新增问题');
    await tester.pump();
    expect(controller.text, '新增问题');
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '发送消息')).onPressed, isNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(sends, 0);
    expect(tester.takeException(), isNull);
  });
}
