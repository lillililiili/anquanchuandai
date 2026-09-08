import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/field_navigation_bar.dart';
import 'package:rolling_intelligence_headband/components/field_motion.dart';
import 'package:rolling_intelligence_headband/components/app_copilot_portal.dart';
import 'package:rolling_intelligence_headband/store/user_store.dart';
import 'package:rolling_intelligence_headband/store/chat_store.dart';

void main() {
  testWidgets('navigation retargets during flight and fits narrow large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 0;
    final calls = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: FieldNavigationBar(
                selected: selected,
                labels: const ['首页', '对讲', '监控', '我的'],
                icons: const [
                  Icons.home,
                  Icons.mic,
                  Icons.videocam,
                  Icons.person,
                ],
                onSelected: (i) {
                  calls.add(i);
                  setState(() => selected = i);
                },
              ),
            ),
          ),
        ),
      ),
    );
    final indicator = find.byKey(const ValueKey('navigation-indicator'));
    final start = tester.getTopLeft(indicator).dx;
    await tester.tap(find.text('我的'));
    expect(calls, [3]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(indicator).dx, greaterThan(start));
    await tester.tap(find.text('对讲'));
    expect(calls, [3, 1]);
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(indicator).dx,
      closeTo(tester.getCenter(find.text('对讲')).dx, .1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced panel hides immediately and entrance schedules no animation',
    (tester) async {
      Widget app(bool open) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MotionEntrance(
            child: MotionPanel(
              visible: open,
              height: 300,
              child: const Material(child: TextField()),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(true));
      await tester.enterText(find.byType(TextField), 'saved');
      await tester.pumpWidget(app(false));
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(app(true));
      expect(find.text('saved'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('AI draft and focus survive fullscreen and keyboard geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    UserStore.instance.statusSignal.value = UserStatus.authorized;
    ChatStore.instance.setChatPanelOpen(true);
    addTearDown(() {
      ChatStore.instance.setChatPanelOpen(false);
      UserStore.instance.statusSignal.value = UserStatus.unauthorized;
    });
    Widget app(double keyboard) => MaterialApp(
      home: const Scaffold(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: AppCopilotPortal(child: child!),
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '设备离线');
    final original = tester.state(find.byType(EditableText));
    await tester.tap(find.byTooltip('全屏'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(app(260));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(original));
    expect(find.text('设备离线'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(TextField)).dy,
      lessThanOrEqualTo(480),
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(original));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
