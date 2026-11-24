import 'package:latlong2/latlong.dart';
import '../core.dart';
import '../location_map.dart';
import 'event_models.dart';

JsonMap _coordinates(WearEvent event) => {
  'latitude': event.locationLat,
  'longitude': event.locationLng,
  'coordinateSystem': event.coordinateSystem,
  'locationQuality': event.locationQuality,
};

LatLng? eventLocationPoint(WearEvent event) =>
    verifiedLocation(_coordinates(event));

typedef EventMapFix = ({LatLng point, String system});

/// A direct helmet's journal timestamps reception before its live session
/// timestamps the committed fix. Only compare the last observation in that
/// short interval. Other protocols must match the snapshot time exactly.
Future<EventMapFix?> historicalEventFix(WearApi api, WearEvent event) async {
  final raw = reportedCoordinates(_coordinates(event));
  final at = DateTime.tryParse(event.locationReportedAt);
  final occurred = DateTime.tryParse(event.occurredAt);
  final system = event.coordinateSystem;
  if (raw == null ||
      at == null ||
      !at.isUtc ||
      (occurred != null && at.isAfter(occurred)) ||
      event.deviceId.isEmpty ||
      event.siteId.isEmpty ||
      event.siteId != api.siteId() ||
      !const {'UNKNOWN', 'GCJ02', 'WGS84'}.contains(system) ||
      !const {
        '',
        'unknown',
        'valid',
        'good',
        'ok',
      }.contains(event.locationQuality.toLowerCase())) {
    return null;
  }
  final direct = event.protocol == 'direct-helmet';
  final from = direct ? at.subtract(const Duration(seconds: 5)) : at;
  final data = jsonMap(
    await api.get(
      '/api/v1/locations/history',
      query: {
        if (event.personId.isNotEmpty)
          'personId': event.personId
        else
          'deviceId': event.deviceId,
        'from': from.toIso8601String(),
        'to': at.add(const Duration(milliseconds: 1)).toIso8601String(),
        'limit': 1000,
      },
    ),
  );
  if (idOf(data['nextCursor']).isNotEmpty) return null;
  DateTime? latest;
  final candidates = <JsonMap>[];
  for (final row in jsonList(data['rows'])) {
    final time = DateTime.tryParse(
      idOf(row['locationReportedAt'] ?? row['reportedAt']),
    );
    if (row['deviceId'] != event.deviceId ||
        row['siteId'] != event.siteId ||
        idOf(row['personId']) != event.personId ||
        (event.bindingId.isNotEmpty && row['bindingId'] != event.bindingId) ||
        (direct && row['source'] != 'direct-helmet') ||
        time == null ||
        !time.isUtc ||
        time.isBefore(from) ||
        time.isAfter(at) ||
        (latest != null && time.isBefore(latest))) {
      continue;
    }
    if (latest == null || time.isAfter(latest)) {
      latest = time;
      candidates.clear();
    }
    candidates.add(row);
  }
  if (candidates.isEmpty) return null;
  final matchedSystem = idOf(candidates.first['coordinateSystem']);
  if ((system != 'UNKNOWN' && system != matchedSystem) ||
      candidates.any(
        (row) =>
            row['coordinateSystem'] != matchedSystem ||
            verifiedLocation(row) != raw ||
            row['locationSource'] == 'CACHED',
      )) {
    return null;
  }
  return (point: raw, system: matchedSystem);
}
