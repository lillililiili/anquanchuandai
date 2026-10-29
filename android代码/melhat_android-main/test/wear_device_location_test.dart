import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/device_location.dart';

void main() {
  final now = DateTime.parse('2026-10-21T06:00:00Z');
  final report = <String, dynamic>{
    'latitude': '35.4',
    'longitude': '112.5',
    'online': 1,
    'locationFreshness': 'CURRENT',
    'coordinateSystem': 'GCJ02',
    'locationReportedAt': '2026-10-21T05:59:50Z',
    'currentAssignment': null,
  };

  test('an unassigned device displays a received position', () {
    final view = deviceLocation(report, now: now);
    expect(view.position, '纬度 35.400000，经度 112.500000');
    expect(view.status, '近期上报');
    expect(view.reportedAt, '2026-10-21T05:59:50.000Z');
  });

  test('invalid and absent coordinates remain unavailable', () {
    for (final patch in [
      {'latitude': null},
      {'latitude': ''},
      {'latitude': false},
      {'longitude': 'NaN'},
      {'latitude': 91},
      {'longitude': -181},
      {'latitude': 0, 'longitude': 0},
    ]) {
      final view = deviceLocation({...report, ...patch}, now: now);
      expect(view.position, '未收到有效位置');
      expect(view.reportedAt, isNull);
    }
  });

  test('old and uncertain reports are retained without appearing current', () {
    for (final patch in [
      {'locationFreshness': 'STALE'},
      {'online': 0},
      {'locationReportedAt': '2026-10-21T05:00:00Z'},
      {'locationReportedAt': null},
      {'locationReportedAt': '2026-10-21T06:01:00Z'},
      {'locationFreshness': 'UNKNOWN'},
    ]) {
      final view = deviceLocation({...report, ...patch}, now: now);
      expect(view.position, contains('纬度 35.400000'));
      expect(view.status, startsWith('最后上报'));
    }
  });
}
