import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/location_map.dart';

void main() {
  Map<String, dynamic> point(
    int minute, {
    String binding = 'a',
    int version = 1,
    bool gap = false,
  }) => {
    'deviceId': 'h',
    'personId': 'p',
    'bindingId': binding,
    'assignmentVersion': version,
    'latitude': 31.2,
    'longitude': 121.4,
    'coordinateSystem': 'GCJ02',
    'locationQuality': 'valid',
    'gap': gap,
    'reportedAt': '2026-10-29T01:${minute.toString().padLeft(2, '0')}:00Z',
  };
  test('invalid other-source points do not fragment valid source history', () {
    final unknownBelt = {
      ...point(1),
      'deviceId': 'b',
      'locationQuality': 'unknown',
    };
    expect(
      locationSegments([
        point(0),
        unknownBelt,
        point(2),
      ], 'GCJ02').map((s) => s.length),
      [2],
    );
    expect(
      locationSegments([
        point(0),
        {...unknownBelt, 'deviceId': 'h'},
        point(2),
      ], 'GCJ02').map((s) => s.length),
      [1, 1],
    );
    expect(
      locationSegments([
        point(0),
        {...point(1), 'deviceId': 'b'},
        point(2),
      ], 'GCJ02').map((s) => s.length),
      [1, 1, 1],
    );
    expect(
      locationSegments([
        point(0),
        {...unknownBelt, 'deviceId': ''},
        point(2),
      ], 'GCJ02').map((s) => s.length),
      [2],
    );
  });
  test(
    'out-of-order pages and replayed rows draw once in observation order',
    () {
      final rows = [
        {...point(2), 'id': 'third', 'latitude': 31.22},
        {...point(0), 'id': 'first', 'latitude': 31.20},
        {...point(1), 'id': 'second', 'latitude': 31.21},
        {...point(1), 'id': 'second', 'latitude': 31.21},
      ];
      final segments = locationSegments(rows, 'GCJ02');
      expect(segments, hasLength(1));
      expect(segments.single.map((p) => p.latitude), [31.20, 31.21, 31.22]);
      expect(rows.first['id'], 'third');
    },
  );
  test(
    'same hardware reissue, version change and explicit gaps stay separate',
    () {
      final segments = locationSegments([
        point(0),
        point(1),
        point(2, binding: 'b'),
        point(3, binding: 'b', version: 2),
        point(4, binding: 'b', version: 2, gap: true),
        point(5, binding: 'b', version: 2),
      ], 'GCJ02');
      expect(segments.map((s) => s.length), [2, 1, 1, 2]);
    },
  );
  test('collected and received bases never silently substitute each other', () {
    final row = {
      ...point(2),
      'locationTimeBasis': 'DEVICE_COLLECTED_AT',
      'collectedAt': '2026-10-29T01:00:00Z',
      'receivedAt': '2026-10-29T01:12:00Z',
    };
    expect(locationTimeValue(row), row['collectedAt']);
    expect(locationTimeLabel(row), '设备采集时间');
    expect(
      locationTimeValue({...row, 'locationTimeBasis': 'RECEIVED_AT'}),
      row['receivedAt'],
    );
    expect(
      locationTimeLabel({...row, 'locationTimeBasis': 'RECEIVED_AT'}),
      contains('采集时间未确认'),
    );
    expect(locationTimeValue({...row, 'locationTimeBasis': 'UNKNOWN'}), '');
    final unknown = {...row, 'locationTimeBasis': 'UNKNOWN'};
    expect(
      locationSegments([
        point(0),
        unknown,
        point(3),
      ], 'GCJ02').map((s) => s.length),
      [1, 1],
    );
  });
  test(
    'known collection basis without timestamp is not repaired from receipt time',
    () {
      final row = {
        ...point(0),
        'locationTimeBasis': 'DEVICE_COLLECTED_AT',
        'reportedAt': null,
        'receivedAt': '2026-10-29T01:12:00Z',
      };
      expect(locationTimeValue(row), '');
      expect(locationSegments([row], 'GCJ02'), isEmpty);
    },
  );
}
