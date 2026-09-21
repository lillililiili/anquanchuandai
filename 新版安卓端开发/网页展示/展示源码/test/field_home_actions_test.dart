import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/field_home_actions.dart';

void main() {
  for (final config in [(320.0, 1.0), (375.0, 2.0)]) {
    testWidgets('home actions fit ${config.$1}dp with ${config.$2}x text', (tester) async {
      tester.view.physicalSize = Size(config.$1, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const longName = '厂区东侧设备维护与应急保障联合巡检作业分组';
      String selected = '';
      int searches = 0;
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(config.$2), disableAnimations: true),
        child: Scaffold(body: Padding(padding: const EdgeInsets.all(18),
          child: FieldHomeActions(groups: const {'', longName}, group: longName,
            enabled: true, onGroupChanged: (v) => selected = v,
            onSearch: () => searches++),
        )),
      )));
      final group = find.byType(FilledButton);
      final search = find.byType(OutlinedButton);
      expect(tester.getSize(group).height, greaterThanOrEqualTo(48));
      expect(tester.getTopLeft(search).dy, greaterThan(tester.getBottomLeft(group).dy));
      await tester.tap(group);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(2));
      await tester.tap(find.text('全部分组'));
      await tester.pumpAndSettle();
      expect(selected, '');
      await tester.tap(search);
      expect(searches, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('regular width is a row; disabled actions do nothing', (tester) async {
    int actions = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 375,
      child: FieldHomeActions(groups: const {''}, group: '', enabled: false,
        onGroupChanged: (_) => actions++, onSearch: () => actions++),
    ))));
    final group = find.byType(FilledButton);
    final search = find.byType(OutlinedButton);
    expect(tester.getTopLeft(group).dy, tester.getTopLeft(search).dy);
    expect(tester.getSize(search).width, 112);
    await tester.tap(group);
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(actions, 0);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
