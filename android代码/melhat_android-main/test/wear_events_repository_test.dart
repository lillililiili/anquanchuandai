import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_repository.dart';
import 'package:rolling_intelligence_headband/wear/events/event_state_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

WearApi _api(
  Future<void> Function(RequestOptions, RequestInterceptorHandler) onRequest,
) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: onRequest));
  return WearApi(
    dio: dio,
    token: () => 'token',
    siteId: () => '1',
    epoch: () => 0,
  );
}

void _ok(
  RequestOptions options,
  RequestInterceptorHandler handler,
  Object? data,
) {
  handler.resolve(
    Response(
      requestOptions: options,
      statusCode: 200,
      data: {'code': 200, 'msg': 'ok', 'data': data},
    ),
  );
}

Map<String, Object?> _row(
  int id, {
  String status = 'open',
  String type = 'sos',
}) => {
  'id': '$id',
  'status': status,
  'type': type,
  'severity': type == 'sos' ? 'high' : 'low',
  'version': 1,
};

void main() {
  test(
    'task event endpoint is filtered and paged locally with an exact total',
    () async {
      final rows = [
        for (var i = 1; i <= 25; i++)
          _row(
            i,
            status: i % 5 == 0 ? 'closed' : 'open',
            type: i.isEven ? 'geofence' : 'sos',
          ),
      ];
      final gateway = ApiEventGateway(
        _api((options, handler) async {
          expect(options.path, '/api/v1/work-tasks/8/events');
          _ok(options, handler, rows);
        }),
      );

      final page = await gateway.fetchPage(
        const EventFilters(taskId: '8', status: 'active', type: 'geofence'),
        2,
        5,
      );

      expect(page.total, 10);
      expect(page.current, 2);
      expect(page.records.map((item) => item.id), [
        '14',
        '16',
        '18',
        '22',
        '24',
      ]);
      expect(page.hasMore, isFalse);
    },
  );

  test(
    'server paging forwards filters and preserves authoritative total',
    () async {
      late Map<String, dynamic> query;
      final gateway = ApiEventGateway(
        _api((options, handler) async {
          query = options.queryParameters;
          _ok(options, handler, {
            'records': [_row(1, status: 'closed', type: 'fall')],
            'total': 31,
            'current': 3,
            'size': 10,
          });
        }),
      );

      final page = await gateway.fetchPage(
        const EventFilters(
          status: 'closed',
          type: 'fall',
          personId: '9',
          claimantUserId: '12',
          escalated: true,
        ),
        3,
        10,
      );

      expect(query, containsPair('current', 3));
      expect(query, containsPair('size', 10));
      expect(query, containsPair('status', 'closed'));
      expect(query, containsPair('type', 'fall'));
      expect(query, containsPair('personId', '9'));
      expect(query, containsPair('claimantUserId', '12'));
      expect(query, containsPair('escalated', 'true'));
      expect(query.containsKey('updatedAfter'), isFalse);
      expect(page.total, 31);
      expect(page.records.single.status, 'closed');
    },
  );

  test('409 is exposed as a conflict without retrying the write', () async {
    var writes = 0;
    final gateway = ApiEventGateway(
      _api((options, handler) async {
        writes++;
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 409,
            data: {'code': 409, 'msg': '已被认领，请刷新', 'data': null},
          ),
        );
      }),
    );

    await expectLater(
      gateway.execute(
        EventCommand.claim,
        WearEvent.fromJson(_row(1)),
        const EventDraft(),
      ),
      throwsA(isA<EventConflict>()),
    );
    expect(writes, 1);
  });

  test('task candidates use authoritative work-task paging', () async {
    final gateway = ApiEventGateway(
      _api((options, handler) async {
        expect(options.path, '/api/v1/work-tasks');
        expect(options.queryParameters, containsPair('current', 2));
        expect(options.queryParameters, containsPair('size', 10));
        _ok(options, handler, {
          'records': [
            {'id': '7', 'title': '受限空间巡检', 'status': 'in_progress'},
          ],
          'total': 11,
          'current': 2,
          'size': 10,
        });
      }),
    );

    final page = await gateway.fetchTaskCandidates(2, 10);
    expect(page.total, 11);
    expect(page.records.single.id, '7');
    expect(page.records.single.title, '受限空间巡检');
  });

  test('pending task match is confirmed once with event version', () async {
    var writes = 0;
    final gateway = ApiEventGateway(
      _api((options, handler) async {
        writes++;
        expect(options.path, '/api/v1/events/1/task');
        expect(options.data, {'taskId': '7', 'version': 4});
        _ok(options, handler, {
          ..._row(1),
          'version': 5,
          'taskId': '7',
          'taskMatch': 'matched',
        });
      }),
    );
    final event = WearEvent.fromJson({
      ..._row(1),
      'version': 4,
      'taskMatch': 'pending',
    });

    final result = await gateway.execute(
      EventCommand.assignTask,
      event,
      const EventDraft(taskId: '7'),
    );

    expect(result.taskId, '7');
    expect(result.taskMatch, 'matched');
    expect(writes, 1);
  });

  test(
    'shared preferences restores event drafts within account and site scope',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesEventStateStore(userId: '12', siteId: '1');
      await store.write(
        const EventWorkspaceState(
          filters: EventFilters(
            status: 'closed',
            type: 'sos',
            claimantUserId: '12',
            escalated: true,
          ),
          current: 2,
          selectedEventId: '91',
          scrollOffset: 144,
          drafts: {'91': EventDraft(closeReason: '误报')},
        ),
      );

      final recovered = await store.read();
      final keys = (await SharedPreferences.getInstance()).getKeys();
      expect(recovered?.selectedEventId, '91');
      expect(recovered?.drafts['91']?.closeReason, '误报');
      expect(recovered?.filters.claimantUserId, '12');
      expect(recovered?.filters.escalated, isTrue);
      expect(keys, contains('wear.12.events.1.draft.91'));
      expect(keys.every((key) => key.startsWith('wear.12.')), isTrue);
    },
  );

  test(
    'revoked logout writers cannot restore drafts after prefix cleanup',
    () async {
      SharedPreferences.setMockInitialValues({});
      final oldStore = SharedPreferencesEventStateStore(
        userId: 'logout-user',
        siteId: '1',
      );
      final queuedWrite = oldStore.write(
        const EventWorkspaceState(
          selectedEventId: '3',
          drafts: {'3': EventDraft(handleComment: '退出前草稿')},
        ),
      );

      await SharedPreferencesEventStateStore.revokeUser('logout-user');
      await queuedWrite;
      final prefs = await SharedPreferences.getInstance();
      for (final key
          in prefs
              .getKeys()
              .where((key) => key.startsWith('wear.logout-user.'))
              .toList()) {
        await prefs.remove(key);
      }
      await oldStore.write(
        const EventWorkspaceState(
          selectedEventId: 'late',
          drafts: {'late': EventDraft(handleComment: '晚到写入')},
        ),
      );
      expect(
        prefs.getKeys().where((key) => key.startsWith('wear.logout-user.')),
        isEmpty,
      );

      final reloginStore = SharedPreferencesEventStateStore(
        userId: 'logout-user',
        siteId: '1',
      );
      await reloginStore.write(
        const EventWorkspaceState(selectedEventId: 'new-session'),
      );
      expect((await reloginStore.read())?.selectedEventId, 'new-session');
    },
  );
}
