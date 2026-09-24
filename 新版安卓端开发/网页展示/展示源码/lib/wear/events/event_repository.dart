import 'package:dio/dio.dart';
import '../core.dart';
import 'event_controller.dart';
import 'event_models.dart';

class ApiEventGateway implements EventGateway {
  const ApiEventGateway(this.api);
  final WearApi api;

  Future<T> _fresh<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on StaleSessionException {
      throw const EventStaleScope();
    }
  }

  @override
  Future<EventPageData> fetchPage(
    EventFilters filters,
    int current,
    int size,
  ) async {
    return _fresh(() async {
      if (filters.taskId.isNotEmpty &&
          filters.severity.isEmpty &&
          filters.alarmCode.isEmpty &&
          filters.statuses.isEmpty &&
          filters.types.isEmpty &&
          filters.alarmCodes.isEmpty &&
          filters.deviceTypes.isEmpty) {
        final rows =
            jsonList(
              await api.get('/api/v1/work-tasks/${filters.taskId}/events'),
            ).map(WearEvent.fromJson).where((event) {
              return (filters.status == 'all' ||
                      ((filters.status.isEmpty || filters.status == 'active')
                          ? !event.isClosed
                          : event.status == filters.status)) &&
                  (filters.type.isEmpty || event.type == filters.type) &&
                  (filters.personId.isEmpty ||
                      event.personId == filters.personId) &&
                  (filters.claimantUserId.isEmpty ||
                      event.claimantUserId == filters.claimantUserId) &&
                  (!filters.escalated || event.escalated);
            }).toList();
        final maxPage = rows.isEmpty ? 1 : ((rows.length - 1) ~/ size) + 1;
        final safeCurrent = current.clamp(1, maxPage);
        final start = (safeCurrent - 1) * size;
        final end = (start + size).clamp(0, rows.length);
        return EventPageData(
          records: start >= rows.length ? const [] : rows.sublist(start, end),
          total: rows.length,
          current: safeCurrent,
          size: size,
        );
      }

      final page = await api.page(
        '/api/v1/events',
        current: current,
        size: size,
        query: {
          if (filters.statuses.isNotEmpty)
            'statuses': filters.statuses.join(','),
          if (filters.types.isNotEmpty) 'types': filters.types.join(','),
          if (filters.alarmCodes.isNotEmpty)
            'alarmCodes': filters.alarmCodes.join(','),
          if (filters.statuses.isEmpty &&
              filters.status.isNotEmpty &&
              filters.status != 'active')
            'status': filters.status,
          if (filters.severity.isNotEmpty) 'severity': filters.severity,
          if (filters.type.isNotEmpty) 'type': filters.type,
          if (filters.alarmCode.isNotEmpty) 'alarmCode': filters.alarmCode,
          if (filters.deviceTypes.isNotEmpty)
            'deviceTypes': filters.deviceTypes.join(','),
          if (filters.taskId.isNotEmpty) 'taskId': filters.taskId,
          if (filters.personId.isNotEmpty) 'personId': filters.personId,
          if (filters.claimantUserId.isNotEmpty)
            'claimantUserId': filters.claimantUserId,
          if (filters.escalated) 'escalated': 'true',
        },
      );
      return EventPageData(
        records: page.records.map(WearEvent.fromJson).toList(),
        total: page.total,
        current: page.current,
        size: page.size,
      );
    });
  }

  @override
  Future<int> fetchInboxCount() => _fresh(() async {
    final data = jsonMap(await api.get('/api/v1/events/inbox/count'));
    return intOf(data['count']);
  });

  @override
  Future<TaskCandidatePage> fetchTaskCandidates(int current, int size) =>
      _fresh(() async {
        final page = await api.page(
          '/api/v1/work-tasks',
          current: current,
          size: size,
        );
        return TaskCandidatePage(
          records: page.records.map(WorkTaskCandidate.fromJson).toList(),
          total: page.total,
          current: page.current,
          size: page.size,
        );
      });

  @override
  Future<WearEvent> fetchDetail(String eventId) => _fresh(
    () async =>
        WearEvent.fromJson(jsonMap(await api.get('/api/v1/events/$eventId'))),
  );

  @override
  Future<List<EventAction>> fetchActions(String eventId) => _fresh(
    () async => jsonList(
      await api.get('/api/v1/events/$eventId/actions'),
    ).map(EventAction.fromJson).toList(),
  );

  @override
  Future<List<DutyOperator>> fetchOperators() => _fresh(
    () async => jsonList(await api.get('/api/v1/duty/operators'))
        .map(DutyOperator.fromJson)
        .where((item) => item.userId.isNotEmpty)
        .toList(),
  );

  @override
  Future<WearEvent> execute(
    EventCommand command,
    WearEvent event,
    EventDraft draft,
  ) async {
    return _fresh(() async {
      final data = switch (command) {
        EventCommand.ack => null,
        EventCommand.claim ||
        EventCommand.confirm => <String, dynamic>{'version': event.version},
        EventCommand.handle => FormData.fromMap({
          'comment': draft.handleComment.trim(),
          'version': event.version,
          'files': await Future.wait(
            draft.photoPaths.map(
              (path) async => MultipartFile.fromFile(
                path,
                filename: path.replaceAll('\\', '/').split('/').last,
              ),
            ),
          ),
        }),
        EventCommand.transfer => <String, dynamic>{
          'toUserId': draft.transferUserId,
          'reason': draft.transferReason.trim(),
          'version': event.version,
        },
        EventCommand.close => <String, dynamic>{
          'reason': draft.closeReason.trim(),
          'version': event.version,
        },
        EventCommand.reopen => <String, dynamic>{
          'reason': draft.reopenReason.trim(),
          'version': event.version,
        },
        EventCommand.assignTask => <String, dynamic>{
          'taskId': draft.taskId,
          'version': event.version,
        },
      };
      try {
        final actionPath = command == EventCommand.assignTask
            ? 'task'
            : command == EventCommand.handle
            ? 'report'
            : command.name;
        return WearEvent.fromJson(
          jsonMap(
            await api.post(
              '/api/v1/events/${event.id}/$actionPath',
              data: data,
            ),
          ),
        );
      } on WearApiException catch (error) {
        if (error.code == 409) throw EventConflict(error.message);
        rethrow;
      }
    });
  }
}
