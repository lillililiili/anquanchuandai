import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_controller.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'wear_events_controller_test.dart'
    show FakeEventGateway, MemoryEventStateStore, actor;

EventPageData page(List<String> ids, int current, {int total = 5}) =>
    EventPageData(
      records: ids
          .map((id) => WearEvent.fromJson({'id': id, 'status': 'open'}))
          .toList(),
      total: total,
      current: current,
      size: 2,
    );

void main() {
  late FakeEventGateway gateway;
  late EventController controller;
  setUp(() {
    gateway = FakeEventGateway();
    controller = EventController(
      gateway: gateway,
      store: MemoryEventStateStore(),
      scopeKey: 'site-1',
      actor: actor,
      pageSize: 2,
    );
  });
  tearDown(() => controller.dispose());

  Future<void> firstPage() async {
    final first = controller.reload();
    gateway.pageRequests.last.complete(page(['1', '2'], 1));
    await first;
  }

  test(
    'append keeps earlier events, removes duplicates and guards concurrent loads',
    () async {
      await firstPage();
      final more = controller.loadMore();
      await controller.loadMore();
      expect(gateway.pageRequests.length, 2);
      gateway.pageRequests.last.complete(page(['2', '3'], 2));
      await more;
      expect(controller.records.map((e) => e.id), ['1', '2', '3']);
      final last = controller.loadMore();
      gateway.pageRequests.last.complete(page(['4', '5'], 3));
      await last;
      expect(controller.records.map((e) => e.id), ['1', '2', '3', '4', '5']);
      expect(controller.hasMore, isFalse);
      await controller.loadMore();
      expect(gateway.pageRequests.length, 3);
    },
  );

  test('failed append preserves rows and retries the same batch', () async {
    await firstPage();
    final failed = controller.loadMore();
    gateway.pageRequests.last.completeError(StateError('offline'));
    await failed;
    expect(controller.records.length, 2);
    expect(controller.current, 1);
    expect(controller.loadMoreError, isNotNull);
    final retry = controller.loadMore();
    gateway.pageRequests.last.complete(page(['3', '4'], 2));
    await retry;
    expect(controller.loadMoreError, isNull);
    expect(controller.records.map((e) => e.id), ['1', '2', '3', '4']);
  });

  test('filter change invalidates an in-flight append', () async {
    await firstPage();
    final old = controller.loadMore();
    final oldRequest = gateway.pageRequests.last;
    final fresh = controller.setFilters(const EventFilters(type: 'sos'));
    await Future<void>.delayed(Duration.zero);
    gateway.pageRequests.last.complete(page(['new'], 1, total: 1));
    await fresh;
    oldRequest.complete(page(['old'], 2));
    await old;
    expect(controller.records.map((e) => e.id), ['new']);
    expect(controller.loadingMore, isFalse);
  });

  test(
    'refresh rebuilds the loaded prefix without losing earlier pages',
    () async {
      await firstPage();
      final more = controller.loadMore();
      gateway.pageRequests.last.complete(page(['3', '4'], 2));
      await more;
      final refresh = controller.reload();
      gateway.pageRequests.last.complete(page(['new', '1'], 1));
      await Future<void>.delayed(Duration.zero);
      gateway.pageRequests.last.complete(page(['2', '3'], 2));
      await refresh;
      expect(controller.records.map((e) => e.id), ['new', '1', '2', '3']);
      expect(controller.current, 2);
    },
  );

  test(
    'empty trailing batch terminates automatic loading despite stale total',
    () async {
      await firstPage();
      final more = controller.loadMore();
      gateway.pageRequests.last.complete(page([], 2));
      await more;
      expect(controller.hasMore, isFalse);
      expect(controller.records.length, 2);
    },
  );
}
