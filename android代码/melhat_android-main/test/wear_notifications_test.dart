import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/notifications.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, transport, reply;

class ControlledPush extends Fake implements JPushFlutterInterface {
  Completer<void>? stopGate;
  Completer<String>? registrationGate;
  final operations = <String>[];
  @override
  Future<void> stopPush() async {
    operations.add('stop');
    await stopGate?.future;
  }

  @override
  Future<void> clearAllNotifications() async {
    operations.add('clear');
  }

  @override
  Future<void> resumePush() async {
    operations.add('resume');
  }

  @override
  Future<String> getRegistrationID() async {
    operations.add('registration');
    return registrationGate?.future ?? Future.value('provider-registration');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'late native logout cannot delete or stop a new account binding',
    () async {
      final mutations = <String>[];
      final session = WearSession(
        credentials: MemoryCredentials('old-token'),
        dio: transport((r) {
          if (r.path == '/api/v1/me') return reply(identity());
          mutations.add('${r.method}:${r.headers['Authorization']}');
          return reply({});
        }),
      );
      addTearDown(session.dispose);
      await session.initialize();
      final push = ControlledPush()..stopGate = Completer<void>();
      final notices = WearNotifications.withPush(
        session: session,
        openEvent: (_) async {},
        push: push,
      );
      addTearDown(notices.dispose);
      final unbind = notices.unbind();
      await Future<void>.delayed(Duration.zero);
      expect(push.operations, ['stop']);
      session.expire();
      session.me = identity(user: '20');
      session.siteId = '1';
      session.token = 'new-token';
      final bind = notices.bind();
      push.stopGate!.complete();
      await unbind;
      await bind;
      expect(push.operations, ['stop', 'stop', 'resume']);
      expect(mutations, ['PUT:Bearer new-token']);
      expect(notices.registered, true);
    },
  );

  test(
    'a new binding is retried after an old account native operation finishes',
    () async {
      final mutations = <String>[];
      final newBound = Completer<void>();
      final session = WearSession(
        credentials: MemoryCredentials('old-token'),
        dio: transport((r) {
          if (r.path == '/api/v1/me') return reply(identity());
          mutations.add('${r.method}:${r.headers['Authorization']}');
          if (!newBound.isCompleted) newBound.complete();
          return reply({});
        }),
      );
      addTearDown(session.dispose);
      await session.initialize();
      final push = ControlledPush()..stopGate = Completer<void>();
      final notices = WearNotifications.withPush(
        session: session,
        openEvent: (_) async {},
        push: push,
      );
      addTearDown(notices.dispose);
      final ready = Completer<void>();
      notices.addListener(() {
        if (notices.registered && session.userId == '20' && !ready.isCompleted) {
          ready.complete();
        }
      });
      final oldBind = notices.bind();
      await Future<void>.delayed(Duration.zero);
      session.expire();
      session.me = identity(user: '20');
      session.siteId = '1';
      session.token = 'new-token';
      await notices.bind();
      push.stopGate!.complete();
      await oldBind;
      await newBound.future.timeout(const Duration(seconds: 2));
      await ready.future.timeout(const Duration(seconds: 2));
      expect(mutations, ['PUT:Bearer new-token']);
      expect(notices.registered, true);
    },
  );

  test(
    'notification blocked by an active call can be retried after hanging up',
    () async {
      final session = WearSession(
        credentials: MemoryCredentials('token'),
        dio: transport((_) => reply(identity())),
      );
      addTearDown(session.dispose);
      await session.initialize();
      var blocked = true;
      var opened = 0;
      final notices = WearNotifications(
        session: session,
        openEvent: (_) async {
          if (blocked) throw const WearApiException(409, '请先结束通话');
          opened++;
        },
      );
      addTearDown(notices.dispose);
      notices.receive({
        'eventId': '1',
        'siteId': '2',
        'notificationId': 'n-retry',
      }, opened: true);
      await Future<void>.delayed(Duration.zero);
      expect(notices.latest?.eventId, '1');
      expect(notices.error, contains('结束通话'));
      blocked = false;
      notices.openLatest();
      await Future<void>.delayed(Duration.zero);
      expect(opened, 1);
      expect(notices.error, null);
    },
  );
  test('logout DELETE waits for the pending binding PUT to finish', () async {
    final writes = <String>[];
    final putStarted = Completer<void>();
    final putFinished = Completer<void>();
    final session = WearSession(
      credentials: MemoryCredentials('token'),
      dio: transport((r) async {
        if (r.path == '/api/v1/me') return reply(identity());
        writes.add(r.method);
        if (r.method == 'PUT') {
          putStarted.complete();
          await putFinished.future;
        }
        return reply({});
      }),
    );
    addTearDown(session.dispose);
    await session.initialize();
    final push = ControlledPush();
    final notices = WearNotifications.withPush(
      session: session,
      openEvent: (_) async {},
      push: push,
    );
    addTearDown(notices.dispose);
    final bind = notices.bind();
    await putStarted.future;
    session.busy = true;
    final unbind = notices.unbind();
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['PUT']);
    putFinished.complete();
    await bind;
    await unbind;
    expect(writes, ['PUT', 'DELETE']);
    expect(push.operations.contains('resume'), false);
    expect(notices.registered, false);
  });
  test(
    'first RID callback never blocks logout or stops registration early',
    () async {
      final session = WearSession(
        credentials: MemoryCredentials('token'),
        dio: transport(
          (r) => r.path == '/api/v1/me' ? reply(identity()) : reply({}),
        ),
      );
      addTearDown(session.dispose);
      await session.initialize();
      final push = ControlledPush()..registrationGate = Completer<String>();
      final notices = WearNotifications.withPush(
        session: session,
        openEvent: (_) async {},
        push: push,
        registrationId: '',
      );
      addTearDown(notices.dispose);
      await notices.bind().timeout(const Duration(seconds: 2));
      expect(push.operations, ['registration']);
      expect(notices.registered, false);
      session.busy = true;
      await notices.unbind().timeout(const Duration(seconds: 2));
      expect(push.operations.contains('stop'), false);
      session.expire();
      push.registrationGate!.complete('first-registration');
      await Future<void>.delayed(Duration.zero);
      expect(push.operations, contains('stop'));
      expect(push.operations.contains('resume'), false);
    },
  );
}
