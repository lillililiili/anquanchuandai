import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/mine_page.dart';
import 'wear_acceptance_fixture.dart';

class DelayedRemovalStore extends InMemorySharedPreferencesStore {
  DelayedRemovalStore(super.data, this.fail) : super.withData();
  final bool fail;
  final released = Completer<void>();
  bool entered = false;

  @override
  Future<bool> remove(String key) async {
    if (key.endsWith('.cache.proof')) {
      entered = true;
      await released.future;
      if (fail) throw StateError('isolated storage failure');
    }
    return super.remove(key);
  }
}

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'cache ${fail ? 'failure' : 'success'} feedback survives busy frame',
      (t) async {
        final session = await launchAcceptance(
          t,
          AcceptanceBackend(),
          account: 'member',
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('wear.${session.userId}.cache.proof', 'old view');
        final originalStore = SharedPreferencesStorePlatform.instance;
        final store = DelayedRemovalStore(await originalStore.getAll(), fail);
        SharedPreferencesStorePlatform.instance = store;
        addTearDown(() {
          if (!store.released.isCompleted) store.released.complete();
          SharedPreferencesStorePlatform.instance = originalStore;
        });
        GoRouter.of(t.element(find.byType(WearShell))).go('/me');
        await t.pumpAndSettle();
        final menu = find.text('清理业务缓存');
        await t.ensureVisible(menu);
        await t.tap(menu);
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(store.entered, true);
        expect(session.busy, true);
        expect(find.byType(WearMinePage), findsNothing);
        store.released.complete();
        await t.pumpAndSettle();
        expect(
          find.text(fail ? '缓存清理失败，请重试' : '已清理业务缓存，保留登录与未提交草稿'),
          findsOneWidget,
        );
        expect(session.busy, false);
        expect(t.takeException(), isNull);
      },
    );
  }
}
