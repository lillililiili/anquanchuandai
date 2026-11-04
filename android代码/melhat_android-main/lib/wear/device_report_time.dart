import 'data.dart';

/// Device-reported history uses an explicit server time basis, never local guessing.
DateTime? deviceReportInstant(Object? value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(idOf(value));
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  if (parts[1] < 1 ||
      parts[1] > 12 ||
      parts[2] < 1 ||
      parts[2] > DateTime.utc(parts[0], parts[1] + 1, 0).day ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59 ||
      (int.tryParse(match.group(7) ?? '0') ?? 24) > 23 ||
      (int.tryParse(match.group(8) ?? '0') ?? 60) > 59) {
    return null;
  }
  return DateTime.tryParse(idOf(value));
}

String deviceReportTimeLabel(Object? value) =>
    deviceReportInstant(value) == null ? '未提供有效时间' : formatTime(value);
