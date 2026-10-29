import 'data.dart';

bool isDemoRecord(JsonMap row) =>
    row['demo'] == true ||
    const ['GUARDIAN_SEED', 'ADMIN_SEED'].contains(row['dataOrigin']) ||
    const ['DEMO', 'DEMO_WATCH'].contains(idOf(row['source']).toUpperCase());

bool isWatchRecord(JsonMap row) => const ['W', 'WATCH'].contains(
  idOf(row['typeCode'] ?? row['deviceType'] ?? row['type']).toUpperCase(),
);

bool hasRealDeviceSource(JsonMap row) => const [
  'PLATFORM',
  'DIRECT_HELMET',
  'DIRECT_BELT',
  'DIRECT_WATCH',
  'DEVICE',
].contains(idOf(row['source']).toUpperCase());

bool isDemoWatch(JsonMap row) =>
    isWatchRecord(row) && isDemoRecord(row) && !hasRealDeviceSource(row);

bool isRetainedDemoWatch(JsonMap row) =>
    [idOf(row['id']), idOf(row['ledgerId'])].contains('RL-W001') &&
    [
      'station',
      'siteId',
    ].every((key) => const ['', 'S1', 'site-1'].contains(idOf(row[key])));

bool isHelmetOrBeltRecord(JsonMap row) =>
    const ['H', 'B', 'HELMET', 'BELT'].contains(
      idOf(row['typeCode'] ?? row['deviceType'] ?? row['type']).toUpperCase(),
    );

/// A display-only guard for older API snapshots; never changes stored records.
JsonMap visibleBusinessState(JsonMap state) {
  final devices = jsonList(state['devices']);
  final showSimulatedWatch =
      jsonMap(state['businessConfig'])['simulatedWatchVisible'] != false;
  final hiddenIds = <String>{
    for (final d in devices)
      if (isHelmetOrBeltRecord(d) &&
              isDemoRecord(d) &&
              !hasRealDeviceSource(d) ||
          isDemoWatch(d) && (!showSimulatedWatch || !isRetainedDemoWatch(d)))
        ...[idOf(d['id']), idOf(d['ledgerId'])].where((id) => id.isNotEmpty),
  };
  final retainedWatchIds = <String>{
    for (final d in devices)
      if (showSimulatedWatch && isDemoWatch(d) && isRetainedDemoWatch(d))
        ...[idOf(d['id']), idOf(d['ledgerId'])].where((id) => id.isNotEmpty),
  };
  bool hiddenReference(JsonMap row) =>
      hiddenIds.contains(idOf(row['deviceId']));
  return {
    ...state,
    'devices': devices
        .where((d) => !hiddenIds.contains(idOf(d['id'])))
        .toList(),
    'vitals': jsonList(state['vitals'])
        .where(
          (row) =>
              hasRealDeviceSource(row) ||
              !hiddenReference(row) &&
                  (!isDemoRecord(row) ||
                      retainedWatchIds.contains(idOf(row['deviceId']))),
        )
        .toList(),
    for (final key in ['assignments', 'assignmentHistory', 'bindings'])
      key: jsonList(state[key]).where((row) => !hiddenReference(row)).toList(),
    'events': jsonList(state['events'])
        .where(
          (row) =>
              !(isDemoRecord(row) &&
                  !hasRealDeviceSource(row) &&
                  (isHelmetOrBeltRecord(row) ||
                      hiddenReference(row) ||
                      !showSimulatedWatch &&
                          (isWatchRecord(row) ||
                              row['type'] == '生命体征' ||
                              row['type'] == 'vitals'))),
        )
        .toList(),
  };
}
