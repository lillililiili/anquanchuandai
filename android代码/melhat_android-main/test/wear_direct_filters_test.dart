import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/inline_filters.dart';

void main() {
  testWidgets('direct choices coalesce, stay in place and require no apply', (
    tester,
  ) async {
    final calls = <Map<String, Set<String>>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineFilters(
            title: '筛选',
            groups: const [
              InlineFilterGroup('device', '设备', {
                'helmet': '安全帽',
                'belt': '安全带',
              }),
            ],
            value: const {},
            onApply: (value, _) => calls.add(value),
          ),
        ),
      ),
    );
    final toggle = find.byKey(const ValueKey('inline-filter-toggle'));
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final hat = find.byKey(const ValueKey('filter-device-helmet'));
    final belt = find.byKey(const ValueKey('filter-device-belt'));
    final before = tester.getRect(belt);
    expect(find.text('应用筛选'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(hat);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<FilterChip>(hat).selected, true);
    expect(tester.getRect(belt), before);
    await tester.tap(belt);
    await tester.pump(const Duration(milliseconds: 299));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls.single['device'], {'helmet', 'belt'});
    await tester.tap(hat);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls.length, 1, reason: '离开页面取消尚未发出的筛选');
  });

  testWidgets('expanded options remain open after immediate parent feedback', (
    tester,
  ) async {
    var selection = <String, Set<String>>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => InlineFilters(
              title: '筛选',
              initiallyExpanded: true,
              groups: [
                InlineFilterGroup('type', '类型', {
                  for (var i = 0; i < 12; i++) '$i': '告警$i',
                }),
              ],
              value: selection,
              onApply: (value, _) => update(() => selection = value),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('filter-expand-type')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('filter-search-type'));
    await tester.enterText(search, '告警11');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-type-11')).last);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(selection['type'], {'11'});
    expect(search, findsOneWidget);
    expect(find.byKey(const ValueKey('expanded-type-11')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
