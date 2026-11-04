import 'data.dart';

/// Work mode changes presentation only. Stored evidence and device sources stay intact.
JsonMap withoutWorkBusiness(JsonMap row) {
  final result = Map<String, dynamic>.from(row);
  for (final key in const [
    'workId',
    'workName',
    'taskId',
    'taskMatch',
    'supervisor',
    'supervisorName',
    'supervisorId',
    'leader',
    'leaderName',
    'leaderId',
    'workSnapshot',
    'externalId',
    'externalRecordId',
    'externalSource',
    'externalSystem',
    'externalStatus',
    'sourceEventId',
    'externalClosureStatus',
  ]) {
    result.remove(key);
  }
  if (result['snapshot'] is Map) {
    result['snapshot'] = withoutWorkBusiness(jsonMap(result['snapshot']));
  }
  return result;
}

JsonMap projectWorkBusiness(JsonMap state) {
  if (jsonMap(state['businessConfig'])['workBusinessEnabled'] != false) {
    return state;
  }
  return {
    ...state,
    'works': <JsonMap>[],
    for (final key in const ['events', 'media'])
      key: jsonList(state[key]).map(withoutWorkBusiness).toList(),
  };
}

bool localWork(JsonMap work) => work['source'] == 'LOCAL';

/// Old read models have no planned bounds; keep those records readable.
bool currentWorkTime(JsonMap work, {DateTime? now}) {
  final start = DateTime.tryParse(idOf(work['plannedStartAt']));
  final end = DateTime.tryParse(idOf(work['plannedEndAt']));
  final instant = now ?? DateTime.now();
  return (start == null || !instant.isBefore(start)) &&
      (end == null || instant.isBefore(end));
}
