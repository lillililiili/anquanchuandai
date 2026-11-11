import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/main.dart' as production;
import 'package:rolling_intelligence_headband/config/backend_config.dart';
import 'package:rolling_intelligence_headband/wear/auth_pages.dart';
import 'package:rolling_intelligence_headband/wear/app.dart' show WearShell;
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_photos.dart';
import 'package:rolling_intelligence_headband/wear/queries/my_equipment_page.dart';
import 'package:rolling_intelligence_headband/wear/shared_backend.dart';
import '../test/png_fixture.dart';

// This target is compiled only into the separately guarded .qa APK. The host
// attaches to three real process launches without reinstalling or clearing data.
class _LifecycleEvidence extends WidgetsBindingObserver {
  final states = <AppLifecycleState>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => states.add(state);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final config = jsonMap(
    jsonDecode(const String.fromEnvironment('WEAR_QA_CONFIG')),
  );
  // Register synchronously: awaiting a platform channel in main can let the
  // integration binding finish with only tearDownAll and no business test.
  testWidgets('QA system acceptance through production entry', (t) async {
    final directory = await getApplicationSupportDirectory();
    final stateFile = File('${directory.path}/qa-system-state.json');
    final runId = idOf(config['runId']);
    final state = await stateFile.exists()
        ? jsonMap(jsonDecode(await stateFile.readAsString()))
        : <String, dynamic>{'runId': runId, 'phase': 'bootstrap'};
    final phase = idOf(state['phase']);
    Future<void> save() async {
      await stateFile.writeAsString(jsonEncode(state), flush: true);
    }

    expect(BackendConfig.mock, false);
    expect(Uri.parse(BackendConfig.baseUrl).host, '127.0.0.1');
    expect(Uri.parse(BackendConfig.baseUrl).port, 18085);
    expect(state['runId'] == runId && runId.isNotEmpty, true);
    expect(['bootstrap', 'restored', 'signedout'].contains(phase), true);
    final checks = <String>[];
    final shots = <String>[];
    final progress = <String>[];
    Future<void> checkpoint(String value) async {
      checks.add(value);
      await File('${directory.path}/qa-system-checkpoints.json').writeAsString(
        jsonEncode({
          'runId': runId,
          'package': 'com.rolling.intelligence_headband.qa',
          'phase': phase,
          'time': DateTime.now().toUtc().toIso8601String(),
          'passedChecks': checks,
        }),
        flush: true,
      );
      debugPrint('QA_SYSTEM_CHECKPOINT $phase $value');
    }

    final lifecycle = _LifecycleEvidence();
    WidgetsBinding.instance.addObserver(lifecycle);
    binding.reportData = {
      'phase': phase,
      'passedChecks': checks,
      'captureNames': shots,
      'progress': progress,
    };
    var converted = false;
    var commandCounter = 0;
    late final WearSession session;
    late final GoRouter router;
    Future<void> pump() => t.pump(const Duration(milliseconds: 200));
    Future<void> until(
      bool Function() predicate,
      String reason, {
      int seconds = 90,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!predicate() && DateTime.now().isBefore(end)) {
        await pump();
      }
      expect(predicate(), true, reason: reason);
    }

    Future<void> click(Finder finder) async {
      await until(() => finder.evaluate().isNotEmpty, 'Control must exist');
      await until(() {
        final w = t.widget(finder.first);
        return w is ButtonStyleButton
            ? w.onPressed != null
            : w is IconButton
            ? w.onPressed != null
            : true;
      }, 'Control must be enabled');
      await Scrollable.ensureVisible(t.element(finder.first), alignment: 0.5);
      await pump();
      await until(
        () => finder.hitTestable().evaluate().isNotEmpty,
        'Control must be hit-testable',
      );
      await t.tap(finder.hitTestable().first);
      await pump();
    }

    Future<void> enter(String key, String value) async {
      final finder = find.byKey(ValueKey(key));
      await until(() => finder.evaluate().isNotEmpty, 'Text field must exist');
      await Scrollable.ensureVisible(t.element(finder), alignment: 0.5);
      await t.enterText(finder, value);
      await pump();
    }

    Future<void> open(String path) async {
      FocusManager.instance.primaryFocus?.unfocus();
      router.go(path);
      await pump();
    }

    Future<void> shot(String name) async {
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await pump();
      await binding.takeScreenshot('$phase-$name');
      shots.add('$phase-$name');
    }

    Future<JsonMap> host(String action) async {
      final id = '$runId-$phase-${++commandCounter}';
      final request = File('${directory.path}/qa-system-command.json');
      await request.writeAsString(
        jsonEncode({'id': id, 'action': action, 'phase': phase}),
        flush: true,
      );
      final response = File('${directory.path}/qa-system-ack.json');
      final end = DateTime.now().add(
        Duration(seconds: action == 'manual_system_back' ? 300 : 180),
      );
      JsonMap ack = {};
      // Manual Back needs live frames so CUA can see the native navigation
      // before acknowledging it. A paused app must not depend on Flutter frames.
      while (DateTime.now().isBefore(end)) {
        if (await response.exists()) {
          try {
            ack = jsonMap(jsonDecode(await response.readAsString()));
          } catch (_) {
            ack = {};
          }
          if (ack['id'] == id) break;
        }
        if (action == 'manual_system_back') {
          await pump();
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      expect(ack['id'], id, reason: 'Host system action timed out: $action');
      expect(ack['ok'], true, reason: 'Host system action failed: $action');
      await pump();
      return ack;
    }

    Future<void> cleanEvent() async {
      final eventId = idOf(state['eventId']);
      if (eventId.isEmpty || state['eventClosed'] == true) return;
      final admin = jsonMap(config['admin']);
      final pc = Dio(
        BaseOptions(
          baseUrl: BackendConfig.baseUrl,
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      try {
        JsonMap unwrap(Object? value) {
          final m = jsonMap(value);
          return m.containsKey('code') && m.containsKey('data')
              ? jsonMap(m['data'])
              : m;
        }

        final login = unwrap(
          (await pc.post(
            '/api/guardian/v1/login',
            data: {'account': admin['username'], 'password': admin['password']},
          )).data,
        );
        pc.options.headers['X-Wearable-Token'] = login['token'];
        var event = unwrap(
          (await pc.get('/api/guardian/v1/events/$eventId')).data,
        );
        Future<void> command(String action, [JsonMap fields = const {}]) async {
          event = unwrap(
            (await pc.post(
              '/api/guardian/v1/events/$eventId/$action',
              data: {
                'expectedVersion': event['version'],
                'requestId': SharedBackend.requestId(),
                ...fields,
              },
            )).data,
          );
        }

        if (event['status'] != '已核验') {
          if (event['status'] == '待认领') await command('claim');
          if (jsonMap(event['assistance'])['status'] != 'ended') {
            if (jsonMap(event['assistance'])['status'] != 'active') {
              await command('assist-join');
            }
            await command('assist-end');
          }
          await command('verification', {
            'conclusion': '需现场处理',
            'situation': '隔离系统验收结束',
            'measures': '测试完成，无现场设备操作',
          });
        }
        expect(event['status'], '已核验');
        state['eventClosed'] = true;
        await save();
      } finally {
        pc.close();
      }
    }

    var succeeded = false;
    void step(String value) {
      progress.add(value);
      debugPrint('QA_SYSTEM_STEP $phase $value');
    }

    try {
      production.main();
      await pump();
      step('production-entry-started');
      if (phase == 'bootstrap') {
        await until(
          () => find.byType(WearLoginPage).evaluate().isNotEmpty,
          'Fresh QA install must show login',
        );
        final loginSession = WearScope.of(
          t.element(find.byType(WearLoginPage)),
        );
        await until(
          () =>
              loginSession.initialized &&
              !loginSession.busy &&
              find.byType(TextFormField).evaluate().length == 2 &&
              t
                  .widgetList<TextFormField>(find.byType(TextFormField))
                  .every((field) => field.enabled != false),
          'Real credential initialization must finish before typing into enabled fields',
        );
        expect(loginSession.error, isNull, reason: 'Initial credential read');
        step('login-initialized-and-fields-enabled');
        final account = jsonMap(config['member']);
        await t.enterText(
          find.byType(TextFormField).at(0),
          idOf(account['username']),
        );
        await pump();
        expect(
          t
                  .widget<TextFormField>(find.byType(TextFormField).at(0))
                  .controller!
                  .text ==
              idOf(account['username']),
          true,
          reason: 'UI account input must actually reach its controller',
        );
        await t.enterText(
          find.byType(TextFormField).at(1),
          idOf(account['password']),
        );
        await pump();
        expect(
          t
                  .widget<TextFormField>(find.byType(TextFormField).at(1))
                  .controller!
                  .text ==
              idOf(account['password']),
          true,
          reason: 'UI password input must actually reach its controller',
        );
        step('both-ui-inputs-confirmed-without-logging-values');
        await click(find.widgetWithText(FilledButton, '登录'));
        step('login-button-clicked');
        await until(
          () =>
              find.byType(WearShell).evaluate().isNotEmpty ||
              loginSession.error != null,
          'Actual UI login must reach authenticated UI or report its error',
        );
        expect(loginSession.error, isNull, reason: 'Actual UI login error');
      }
      if (phase == 'signedout') {
        await until(
          () => find.byType(WearLoginPage).evaluate().isNotEmpty,
          'UI logout must persist across actual process restart',
        );
        expect(await const SecureCredentialStore().read() == null, true);
        await checkpoint(
          'UI logout survives a second real cold start with SecureStorage empty',
        );
        await shot('cold-login');
        state['phase'] = 'complete';
        succeeded = true;
        await save();
        return;
      }
      await until(
        () => find.byType(WearShell).evaluate().isNotEmpty,
        'Production main must restore authenticated UI',
      );
      step('authenticated-ui-visible');
      session = WearScope.of(t.element(find.byType(WearShell).first));
      router = GoRouter.of(t.element(find.byType(WearShell).first));
      expect(session.credentials is SecureCredentialStore, true);
      expect(session.api.isMock, false);
      expect(session.api.usesSharedBackend, true);
      expect(session.personId, idOf(jsonMap(config['fixture'])['personId']));
      expect(
        (await session.credentials.read()) == session.token &&
            session.token != null,
        true,
      );
      await checkpoint(
        'Production main uses real SecureCredentialStore and actual member identity',
      );
      if (phase == 'bootstrap') {
        var event = jsonMap(
          await session.api.post(
            '/api/v1/events/manual-sos',
            data: {'requestId': SharedBackend.requestId()},
          ),
        );
        state['eventId'] = event['id'];
        state['draft'] = 'QA unsent draft $runId';
        await save();
        event = jsonMap(
          await session.api.post(
            '/api/v1/events/${event['id']}/report',
            data: FormData.fromMap({
              'version': event['version'],
              'comment': 'QA actual image $runId',
              'files': [
                MultipartFile.fromBytes(
                  validPngFixture(),
                  filename: 'qa-valid.png',
                ),
              ],
            }),
          ),
        );
        await open('/events?eventId=${event['id']}');
        await until(
          () =>
              t
                  .widgetList<RawImage>(find.byType(RawImage))
                  .where((w) => w.image?.width == 4 && w.image?.height == 4)
                  .length >=
              2,
          'Both actual event attachment views must decode the valid PNG',
        );
        expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
        await checkpoint(
          'Actual event page displays both authenticated PNG views',
        );
        await Scrollable.ensureVisible(
          t.element(find.byType(EventStoredPhotos).first),
          alignment: 0.5,
        );
        await shot('valid-stored-photos');
        await Scrollable.ensureVisible(
          t.element(find.byType(EventSubmittedPhotos).first),
          alignment: 0.5,
        );
        await shot('valid-submitted-photos');
        await enter('event-observation', idOf(state['draft']));
        final prefs = await SharedPreferences.getInstance();
        await until(
          () => prefs.getKeys().any(
            (key) => prefs.get(key).toString().contains(idOf(state['draft'])),
          ),
          'Draft must reach real SharedPreferences',
        );
        await open('/me');
        final beforeCacheScope = session.scopeKey;
        await click(find.text('清理业务缓存'));
        step('cache-menu-clicked');
        await until(
          () => !session.busy && session.scopeKey != beforeCacheScope,
          'Actual cache operation must complete and invalidate its view scope',
          seconds: 15,
        );
        step('cache-operation-completed');
        await shot('cache-menu-feedback');
        await until(
          () => find.text('已清理业务缓存，保留登录与未提交草稿').evaluate().isNotEmpty,
          'Actual cache menu must confirm cleanup',
          seconds: 5,
        );
        expect((await session.credentials.read()) == session.token, true);
        step('cache-cleaned-credentials-retained-reopening-event');
        await open('/events?eventId=${state['eventId']}');
        await until(
          () => find
              .byKey(const ValueKey('event-observation'))
              .evaluate()
              .isNotEmpty,
          'Draft field must reopen',
        );
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('event-observation')),
              )
              .controller!
              .text,
          state['draft'],
        );
        await checkpoint(
          'My-page cache cleanup preserves real stored credentials and unsent draft',
        );
        step('cache-draft-restored');
        await shot('draft-after-cache');
        state['phase'] = 'restored';
      } else {
        await checkpoint(
          'Real force-stop/cold launch restored identity without another login',
        );
        await open('/events?eventId=${state['eventId']}');
        await until(
          () => find
              .byKey(const ValueKey('event-observation'))
              .evaluate()
              .isNotEmpty,
          'Draft field must restore',
        );
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('event-observation')),
              )
              .controller!
              .text,
          state['draft'],
        );
        await checkpoint('Unsent draft survived real process restart');
        // Keep the real Android surface until CUA has performed system Back.
        // The SDK's screenshot conversion is reverted only at test teardown;
        // while waiting without pumping it can leave CUA seeing a stale image.
        // Cold-restoration evidence is the persisted checkpoint, not a later shot.
        await open('/me');
        await click(find.text('我的装备'));
        await until(
          () =>
              find.byType(MyEquipmentPage).evaluate().isNotEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty &&
              find.text('装备信息暂不可用').evaluate().isEmpty,
          'Equipment page must open and finish loading before real Back',
        );
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        step('equipment-loaded-awaiting-real-cua-back');
        await host('manual_system_back');
        await until(
          () =>
              find.byType(MyEquipmentPage).evaluate().isEmpty &&
              find.text('清理业务缓存').evaluate().isNotEmpty,
          'Actual system Back must return to My page',
        );
        await checkpoint(
          'CUA-operated Android Back returned from equipment to My page',
        );
        lifecycle.states.clear();
        final resumedReads = <String>[];
        session.api.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.method == 'GET' &&
                  lifecycle.states.contains(AppLifecycleState.paused) &&
                  lifecycle.states.last == AppLifecycleState.resumed &&
                  WidgetsBinding.instance.lifecycleState ==
                      AppLifecycleState.resumed) {
                resumedReads.add(options.path);
              }
              handler.next(options);
            },
          ),
        );
        final resume = await host('background_resume');
        expect(resume['sameProcess'], true);
        expect(lifecycle.states.contains(AppLifecycleState.paused), true);
        expect(lifecycle.states.last, AppLifecycleState.resumed);
        await until(
          () => session.me != null,
          'Identity must remain after real background/resume',
        );
        await until(
          () => resumedReads.contains('/api/guardian/v1/business-config'),
          'Resumed production app must read actual business configuration',
        );
        await checkpoint(
          'System Home/foreground transition resumed the same process and actual config reads',
        );
        final baselineMedia = MediaQuery.of(
          t.element(find.byType(WearShell).first),
        );
        final baselineLandscape =
            baselineMedia.size.width > baselineMedia.size.height;
        final baselineScale = baselineMedia.textScaler.scale(16) / 16;
        await host('font_large');
        await until(
          () =>
              MediaQuery.textScalerOf(
                    t.element(find.byType(WearShell).first),
                  ).scale(16) /
                  16 >
              1.35,
          'OS font setting must reach Flutter',
        );
        for (final route in [
          '/workbench',
          '/communications',
          '/events',
          '/me',
        ]) {
          await open(route);
          final ready = switch (route) {
            '/workbench' => find.text('我的事件记录'),
            '/communications' => find.byKey(
              const ValueKey('wear-communications-list'),
            ),
            '/events' => find.byKey(const ValueKey('wear-events-workspace')),
            _ => find.text('清理业务缓存'),
          };
          await until(
            () =>
                ready.evaluate().isNotEmpty &&
                find.byType(CircularProgressIndicator).evaluate().isEmpty &&
                find.byType(LinearProgressIndicator).evaluate().isEmpty,
            'Large-font route must show loaded content before capture: $route',
          );
          expect(
            t.takeException(),
            isNull,
            reason: 'System large font: $route',
          );
          await shot('large-${route.substring(1)}');
        }
        await host('rotate_landscape');
        await until(() {
          final size = MediaQuery.sizeOf(
            t.element(find.byType(WearShell).first),
          );
          return size.width > size.height;
        }, 'OS rotation must produce landscape layout');
        expect(t.takeException(), isNull);
        await shot('system-landscape');
        await host('restore_display');
        await until(() {
          final media = MediaQuery.of(t.element(find.byType(WearShell).first));
          return (media.size.width > media.size.height) == baselineLandscape &&
              (media.textScaler.scale(16) / 16 - baselineScale).abs() < 0.05;
        }, 'Original OS display configuration must return');
        await checkpoint(
          'Actual OS large-font and landscape changes render the tested pages',
        );
        await host('network_down');
        session.api.shared.clearReadCache();
        await open('/devices/${jsonMap(config['fixture'])['deviceCode']}');
        await until(
          () => find.text('加载失败').evaluate().isNotEmpty,
          'Removing only18085 must show real network failure',
        );
        await shot('network-failure');
        await host('network_up');
        await click(find.text('重新加载'));
        await until(
          () =>
              find.text('加载失败').evaluate().isEmpty &&
              find.text('设备类型').evaluate().isNotEmpty,
          'UI retry must load actual device after reverse restoration',
        );
        await shot('network-recovered');
        await checkpoint(
          'Only18085 disconnected; actual failure and UI retry recovered without fabricated data',
        );
        await cleanEvent();
        await open('/me');
        await click(find.text('退出登录'));
        await click(find.text('确认退出'));
        await until(
          () => find.byType(WearLoginPage).evaluate().isNotEmpty,
          'My-page logout must return to login',
        );
        expect(await const SecureCredentialStore().read() == null, true);
        await checkpoint('Actual My-page logout cleared real SecureStorage');
        await shot('ui-logout');
        state['phase'] = 'signedout';
      }
      succeeded = true;
      await save();
    } finally {
      if (phase == 'restored') {
        await host('network_up');
        await host('restore_display');
      }
      if (!succeeded || phase == 'restored') await cleanEvent();
      binding.reportData = {
        ...?binding.reportData,
        'nextPhase': state['phase'],
        'eventId': state['eventId'],
        'eventClosed': state['eventClosed'] == true,
      };
      WidgetsBinding.instance.removeObserver(lifecycle);
      await t.pumpWidget(const SizedBox.shrink());
      await pump();
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
