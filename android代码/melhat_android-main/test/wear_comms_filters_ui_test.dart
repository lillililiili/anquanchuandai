import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wear_comms_entry_test.dart' show openDevice;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('multiple phone selections stay in place and never dial on tap', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final router = await openDevice(
      tester,
      requests,
      phoneContacts: ['7', '8'],
    );
    router.go('/communications');
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('wear-communications-list'));
    final scroll = tester.widget<ListView>(list).controller!;
    final first = find.byKey(const ValueKey('contact-call-p:7'));
    final second = find.byKey(const ValueKey('contact-call-p:8'));
    await Scrollable.ensureVisible(tester.element(first), alignment: .4);
    await tester.pumpAndSettle();
    final before = scroll.offset;
    var i = 0;
    for (final icon in [first, second, first, second]) {
      await tester.tap(icon);
      await tester.pumpAndSettle();
      expect(find.text('${[1, 2, 1, 0][i++]} 项'), findsOneWidget);
      expect(scroll.offset, closeTo(before, .01));
    }
    expect(
      requests.where(
        (r) => r.method == 'POST' && !r.path.endsWith('/presence'),
      ),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
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
                widget is TextField && widget.decoration?.hintText == '搜索联系人',
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(requests.where((r) => r.method != 'GET'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'contacts open without a filter panel and search keeps reachable phone selections',
    (tester) async {
      final requests = <RequestOptions>[];
      final router = await openDevice(tester, requests, phoneContacts: ['0']);
      requests.clear();
      router.go('/communications');
      await tester.pumpAndSettle();
      expect(find.text('安全帽未关联'), findsWidgets);
      expect(find.textContaining('联系对象筛选'), findsNothing);
      expect(find.byKey(const ValueKey('inline-filter-toggle')), findsNothing);
      expect(find.textContaining('选择联系人后，可按设备能力'), findsNothing);
      expect(
        requests.where((r) => r.path.startsWith('/api/v1/work-tasks')),
        isEmpty,
      );
      expect(requests.where((r) => r.path == '/api/v1/lab/roster'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('contact-call-p:0')));
      await tester.pumpAndSettle();
      expect(find.text('1 项'), findsOneWidget);
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '搜索联系人',
      );
      await tester.enterText(search, '联系人07');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('contact-p:7')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('联系人00'), findsNothing);
      expect(find.text('1 项'), findsOneWidget);
      await tester.enterText(search, '不存在的联系人');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的联系人'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      expect(find.text('联系人00'), findsOneWidget);
      expect(
        requests.where(
          (r) => r.method != 'GET' && !r.path.endsWith('/presence'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
