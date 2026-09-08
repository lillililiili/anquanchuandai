import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/views/home_children/check_in.dart';
import 'package:rolling_intelligence_headband/theme/app_theme.dart';
void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('check in statistics fit 320dp at $scale text', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale)), child: child!),
        home: const CheckInPage()));
      await tester.pumpAndSettle();
      expect(find.text('已签到'), findsOneWidget);
      expect(find.text('应签到'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('历史记录'));
      await tester.pumpAndSettle();
      expect(find.text('签到记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
