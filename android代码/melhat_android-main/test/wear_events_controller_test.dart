import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_controller.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';

WearEvent _event({
  required String id,
  String status = 'open',
  int version = 1,
  String? claimant,
}) => WearEvent.fromJson({
  'id': id,
  'type': 'sos',
  'severity': 'high',
  'status': status,
  'claimantUserId': claimant,
  'version': version,
});

class MemoryEventStateStore implements EventStateStore {
  EventWorkspaceState? value;
  @override
  Future<EventWorkspaceState?> read() async => value;

  @override
  Future<void> write(EventWorkspaceState value) async {
    this.value = EventWorkspaceState.fromJson(value.toJson());
  }
}

class FakeEventGateway implements EventGateway {
  final pageRequests = <Completer<EventPageData>>[];
  final writes = <EventCommand>[];
  WearEvent detail = _event(id: '1');
  List<EventAction> actions = const [];
  Object? writeError;
  Completer<WearEvent>? heldWrite;

  @override
  Future<EventPageData> fetchPage(EventFilters filters, int current, int size) {
    final request = Completer<EventPageData>();
    pageRequests.add(request);
    return request.future;
  }

  @override
  Future<WearEvent> fetchDetail(String eventId) async => detail;

  @override
  Future<int> fetchInboxCount() async => 3;

  @override
  Future<TaskCandidatePage> fetchTaskCandidates(int current, int size) async =>
      TaskCandidatePage(
        records: const [],
        total: 0,
        current: current,
        size: size,
      );

  @override
  Future<List<EventAction>> fetchActions(String eventId) async => actions;

  @override
  Future<List<DutyOperator>> fetchOperators() async => const [];

  @override
  Future<WearEvent> execute(
    EventCommand command,
    WearEvent event,
    EventDraft draft,
  ) async {
    writes.add(command);
    if (writeError case final error?) throw error;
    if (heldWrite case final pending?) return pending.future;
    return detail;
  }
}

const actor = EventActor(
  userId: '12',
  roles: {'wear_duty'},
  permissions: {'wear:event:list', 'wear:event:query', 'wear:event:claim'},
);

void main() {
  test(
    'direct filtering preserves visible records and scroll while waiting',
    () async {
      final gateway = FakeEventGateway();
      final controller = EventController(
        gateway: gateway,
        store: MemoryEventStateStore(),
        scopeKey: 'direct',
        actor: actor,
      );
      addTearDown(controller.dispose);
      final initial = controller.reload();
      gateway.pageRequests.single.complete(
        EventPageData(
          records: [_event(id: 'old')],
          total: 1,
          current: 1,
          size: 20,
        ),
      );
      await initial;
      await controller.updateScroll(180);
      final change = controller.setFilters(
        const EventFilters(statuses: ['closed']),
        preserveViewport: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.records.single.id, 'old');
      expect(controller.scrollOffset, 180);
      gateway.pageRequests.last.complete(
        EventPageData(
          records: [_event(id: 'new')],
          total: 1,
          current: 1,
          size: 20,
        ),
      );
      await change;
      expect(controller.records.single.id, 'new');
      expect(controller.scrollOffset, 180);
    },
  );
  test(
    'restoring multi-select filters keeps all choices on initialization',
    () async {
      final store = MemoryEventStateStore()
        ..value = const EventWorkspaceState(
          filters: EventFilters(
            status: 'all',
            statuses: ['open', 'closed'],
            types: ['fall', 'impact'],
            alarmCodes: ['helmet.removal', 'belt.unhooked'],
            deviceTypes: ['helmet', 'belt'],
          ),
        );
      final gateway = FakeEventGateway();
      final controller = EventController(
        gateway: gateway,
        store: store,
        scopeKey: 'test',
        actor: actor,
      );
      addTearDown(controller.dispose);
      final pending = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      gateway.pageRequests.single.complete(
        const EventPageData(records: [], total: 0, current: 1, size: 20),
      );
      await pending;
      expect(controller.filters.statuses, ['open', 'closed']);
      expect(controller.filters.types, ['fall', 'impact']);
      expect(controller.filters.alarmCodes, [
        'helmet.removal',
        'belt.unhooked',
      ]);
    },
  );
  test(
    'latest page request wins when responses complete out of order',
    () async {
      final gateway = FakeEventGateway();
      final controller = EventController(
        gateway: gateway,
        store: MemoryEventStateStore(),
        scopeKey: 'user-12@site-a',
        actor: actor,
      );

      final first = controller.reload();
      final second = controller.setFilters(const EventFilters(type: 'fall'));
      await Future<void>.delayed(Duration.zero);
      gateway.pageRequests[1].complete(
        EventPageData(
          records: [_event(id: 'new')],
          total: 1,
          current: 1,
          size: 20,
        ),
      );
      await second;
      gateway.pageRequests[0].complete(
        EventPageData(
          records: [_event(id: 'old')],
          total: 1,
          current: 1,
          size: 20,
        ),
      );
      await first;

      expect(controller.records.single.id, 'new');
      expect(controller.filters.type, 'fall');
      controller.dispose();
    },
  );

  test('scope change drops stale results from the previous site', () async {
    final gateway = FakeEventGateway();
    final controller = EventController(
      gateway: gateway,
      store: MemoryEventStateStore(),
      scopeKey: 'user-12@site-a',
      actor: actor,
    );

    final oldLoad = controller.reload();
    final newLoad = controller.replaceScope(
      scopeKey: 'user-12@site-b',
      actor: actor,
      store: MemoryEventStateStore(),
    );
    await Future<void>.delayed(Duration.zero);
    gateway.pageRequests[1].complete(
      EventPageData(
        records: [_event(id: 'site-b')],
        total: 1,
        current: 1,
        size: 20,
      ),
    );
    await newLoad;
    gateway.pageRequests[0].complete(
      EventPageData(
        records: [_event(id: 'site-a')],
        total: 1,
        current: 1,
        size: 20,
      ),
    );
    await oldLoad;

    expect(controller.records.single.id, 'site-b');
    expect(controller.scopeKey, 'user-12@site-b');
    controller.dispose();
  });

  test('409 refreshes server truth and preserves the event draft', () async {
    final gateway = FakeEventGateway();
    final store = MemoryEventStateStore();
    final controller = EventController(
      gateway: gateway,
      store: store,
      scopeKey: 'user-12@site-a',
      actor: actor,
    );
    final load = controller.reload();
    gateway.pageRequests.single.complete(
      EventPageData(records: [_event(id: '1')], total: 1, current: 1, size: 20),
    );
    await load;
    await controller.select('1');
    await controller.updateDraft(
      '1',
      const EventDraft(handleComment: '现场已电话确认', photoPaths: ['camera.jpg']),
    );
    gateway.writeError = const EventConflict('其他组员已上报，请刷新');
    gateway.detail = _event(
      id: '1',
      status: 'claimed',
      version: 2,
      claimant: '77',
    );

    final write = controller.execute(EventCommand.handle);
    await Future<void>.delayed(Duration.zero);
    gateway.pageRequests.last.complete(
      EventPageData(records: [gateway.detail], total: 1, current: 1, size: 20),
    );
    expect(await write, isFalse);

    expect(controller.selected?.claimantUserId, '77');
    expect(controller.draftFor('1').handleComment, '现场已电话确认');
    expect(controller.conflictMessage, '其他组员已上报，请刷新');
    expect(gateway.writes, [EventCommand.handle]);
    controller.dispose();
  });

  test('an in-flight write blocks duplicate taps', () async {
    final gateway = FakeEventGateway();
    final controller = EventController(
      gateway: gateway,
      store: MemoryEventStateStore(),
      scopeKey: 'user-12@site-a',
      actor: actor,
    );
    final load = controller.reload();
    gateway.pageRequests.single.complete(
      EventPageData(records: [_event(id: '1')], total: 1, current: 1, size: 20),
    );
    await load;
    await controller.select('1');
    await controller.updateDraft('1', const EventDraft(handleComment: '传感器松动', photoPaths: ['camera.jpg']));
    gateway.heldWrite = Completer<WearEvent>();

    final first = controller.execute(EventCommand.handle);
    final duplicate = await controller.execute(EventCommand.handle);
    expect(duplicate, isFalse);
    expect(gateway.writes, [EventCommand.handle]);
    gateway.heldWrite!.complete(
      _event(id: '1', status: 'claimed', version: 2, claimant: '12'),
    );
    await Future<void>.delayed(Duration.zero);
    gateway.pageRequests.last.complete(
      EventPageData(
        records: [
          _event(id: '1', status: 'claimed', version: 2, claimant: '12'),
        ],
        total: 1,
        current: 1,
        size: 20,
      ),
    );
    expect(await first, isTrue);
    expect(gateway.writes, [EventCommand.handle]);
    controller.dispose();
  });

  test(
    'stored filters, selection, offset and drafts recover after restart',
    () async {
      final gateway = FakeEventGateway();
      final store = MemoryEventStateStore()
        ..value = EventWorkspaceState(
          filters: const EventFilters(status: 'closed', type: 'fall'),
          current: 2,
          selectedEventId: '9',
          scrollOffset: 180,
          drafts: const {'9': EventDraft(closeReason: '误报')},
        );
      gateway.detail = _event(id: '9', status: 'closed');
      final controller = EventController(
        gateway: gateway,
        store: store,
        scopeKey: 'user-12@site-a',
        actor: actor,
      );

      final init = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      gateway.pageRequests.single.complete(
        EventPageData(
          records: [_event(id: 'first')],
          total: 21,
          current: 1,
          size: 20,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      gateway.pageRequests.last.complete(
        EventPageData(
          records: [gateway.detail],
          total: 21,
          current: 2,
          size: 20,
        ),
      );
      await init;

      expect(controller.filters.status, 'closed');
      expect(controller.filters.type, 'fall');
      expect(controller.current, 2);
      expect(controller.total, 21);
      expect(controller.records.map((event) => event.id), ['first', '9']);
      expect(controller.selected?.id, '9');
      expect(controller.scrollOffset, 180);
      expect(controller.draftFor('9').closeReason, '误报');
      controller.dispose();
    },
  );
}
