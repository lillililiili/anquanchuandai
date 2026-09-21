import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/field_brand.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('brand hero wraps at 375dp with text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(375, 812),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    FieldBrandMark(),
                    FieldHero(
                      scene: 'workbench-scene',
                      title: '现场工作台与人员安全管理',
                      subtitle: '查看当前设备与现场作业动态',
                    ),
                    FieldHero(
                      scene: 'track-scene',
                      title: '人员轨迹',
                      subtitle: '按人员与时间回看现场',
                      dark: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('现场工作台与人员安全管理'), findsOneWidget);
    });
  }
}
