import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/models/hat.dart';
import 'package:rolling_intelligence_headband/theme/app_theme.dart';
import 'package:rolling_intelligence_headband/views/mine_children/my_safety_hat.dart';
import 'package:rolling_intelligence_headband/views/mine_children/ai_config.dart';

void main() {
  testWidgets('personal device empty state remains readable and can refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 812),
            textScaler: TextScaler.linear(2),
          ),
          child: MySafetyHatPage(
            loadHat: () async {
              requests++;
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂未绑定安全帽'), findsOneWidget);
    expect(find.text('已绑定安全帽'), findsNothing);
    expect(find.text('设备状态'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('刷新绑定信息'));
    await tester.pumpAndSettle();
    expect(requests, 2);
  });

  testWidgets(
    'personal device error is not represented as unbound and retry recovers',
    (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MySafetyHatPage(
            loadHat: () async {
              if (count++ == 0) throw StateError('offline');
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('绑定信息加载失败'), findsOneWidget);
      expect(find.text('暂未绑定安全帽'), findsNothing);
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(find.text('暂未绑定安全帽'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('personal device normalizes numeric online status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MySafetyHatPage(
          loadHat: () async => Hat(
            id: '1',
            hatNumber: 'HAT-001',
            status: '1',
            electricityUsage: 86,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已绑定 · 在线'), findsOneWidget);
    expect(find.text('86%'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('当前绑定信息'), 250);
    expect(find.text('当前绑定信息'), findsOneWidget);
  });

  testWidgets('AI config empty save validates fields without persisting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const AIConfigPage()),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存配置'));
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 API Key'), findsOneWidget);
    expect(find.text('请输入完整的 http 或 https 服务地址'), findsOneWidget);
    expect(find.text('请输入模型名称'), findsOneWidget);
    expect(find.textContaining('配置已保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AI config dirty back can continue editing without losing input',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AIConfigPage()),
                ),
                child: const Text('打开配置'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开配置'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'unsaved-model');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('unsaved-model'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(find.text('打开配置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
