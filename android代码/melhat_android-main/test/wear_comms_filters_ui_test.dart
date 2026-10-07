import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wear_comms_entry_test.dart' show openDevice;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final action in ['呼叫', '文字播报']) {
    testWidgets(
      'multi-select keeps contacts in place while checking and unchecking ($action)',
      (tester) async {
        final requests = <RequestOptions>[];
        final router = await openDevice(tester, requests);
        router.go('/communications');
        await tester.pumpAndSettle();
        expect(find.text('多选'), findsNothing);
        expect(find.text('清空'), findsOneWidget);
        await tester.pumpAndSettle();
        if (action == '文字播报') {
          await tester.ensureVisible(find.text('联系人00'));
          await tester.tap(find.text('联系人00'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('文字播报'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('清空'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('清空'));
          await tester.pumpAndSettle();
        }
        final list = find.byKey(const ValueKey('wear-communications-list'));
        final scroll = tester.widget<ListView>(list).controller!;
        await tester.scrollUntilVisible(
          find.text('联系人07'),
          250,
          scrollable: find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        final anchor = find.text('联系人07');
        final position = tester.getTopLeft(anchor);
        final offset = scroll.offset;
        var tapIndex = 0;
        for (final name in ['联系人07', '联系人08', '联系人07', '联系人08']) {
          expect(find.text(name).hitTestable(), findsOneWidget);
          await tester.tap(find.text(name));
          await tester.pumpAndSettle();
          expect(find.text('${[1, 2, 1, 0][tapIndex++]} 项'), findsOneWidget);
          expect(scroll.offset, closeTo(offset, .01));
          expect(tester.getTopLeft(anchor), position);
        }
        expect(find.text('0 项'), findsOneWidget);
        expect(requests.where((r) => r.method != 'GET'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('contacts return to the page top after scrolling one viewport', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final router = await openDevice(tester, requests);
    router.go('/communications');
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('wear-communications-list'));
    final scroll = tester.widget<ListView>(list).controller!;
    final button = find.byTooltip('回到顶部');
    expect(button, findsNothing);
    scroll.jumpTo(scroll.position.viewportDimension);
    await tester.pumpAndSettle();
    expect(button, findsNothing);
    scroll.jumpTo(scroll.position.viewportDimension + 20);
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    final position = tester.getTopRight(button);
    expect(
      tester
          .getBottomRight(
            find.ancestor(of: button, matching: find.byType(Positioned)).first,
          )
          .dy,
      closeTo(tester.getBottomRight(list).dy - 16, .01),
    );
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopRight(button), position);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(button, findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.hintText == '搜索人员或设备',
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(requests.where((r) => r.method != 'GET'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'inline filters clear hidden selections and preserve search/navigation',
    (tester) async {
      final requests = <RequestOptions>[];
      final router = await openDevice(tester, requests);
      router.go('/communications');
      await tester.pumpAndSettle();
      expect(find.text('安全帽未关联'), findsWidgets);
      expect(requests.where((r) => r.path == '/api/v1/lab/roster'), isEmpty);
      await tester.tap(find.text('联系人00'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final toggle = find.byKey(const ValueKey('inline-filter-toggle'));
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      final watch = find.byKey(const ValueKey('filter-device-watch'));
      await tester.ensureVisible(watch);
      await tester.tap(watch);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的人员或设备'), findsOneWidget);
      expect(find.text('0 项'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      final reset = find.byKey(const ValueKey('filter-reset'));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(find.text('联系人00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
