import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/field_tools_section.dart';
import 'package:rolling_intelligence_headband/theme/app_theme.dart';

void main() {
  for (final setup in [
    (375.0, 1.0),
    (320.0, 1.25),
    (320.0, 2.0),
    (260.0, 1.0),
  ]) {
    testWidgets(
      'all tool actions remain reachable at ${setup.$1}dp / ${setup.$2}x',
      (tester) async {
        tester.view.physicalSize = Size(setup.$1, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(setup.$1, 812),
                textScaler: TextScaler.linear(setup.$2),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: FieldToolsSection(
                    onTrack: () => calls.add('人员轨迹'),
                    onDevices: () => calls.add('设备状态'),
                    onFence: () => calls.add('电子围栏'),
                    onMyHelmet: () => calls.add('我的安全帽'),
                    onCheckIn: () => calls.add('现场签到'),
                    onAiConfig: () => calls.add('AI 服务配置'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('演示功能，不提交签到'), findsOneWidget);
        expect(find.text('实时监控'), findsNothing);
        expect(find.text('现场对讲'), findsNothing);
        for (final title in [
          '人员轨迹',
          '设备状态',
          '电子围栏',
          '我的安全帽',
          '现场签到',
          'AI 服务配置',
        ]) {
          await tester.ensureVisible(find.text(title));
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
        }
        expect(calls, ['人员轨迹', '设备状态', '电子围栏', '我的安全帽', '现场签到', 'AI 服务配置']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
