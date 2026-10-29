/// Positions and timestamps describe received reports, not measurement accuracy.
({String position, String? reportedAt, String status}) deviceLocation(
  Map<String, dynamic> device, {
  DateTime? now,
}) {
  double? coordinate(Object? value, double limit) {
    if (value is! num && value is! String) return null;
    final number = double.tryParse(value.toString());
    return number != null && number.isFinite && number.abs() <= limit
        ? number
        : null;
  }

  final lat = coordinate(device['latitude'], 90);
  final lon = coordinate(device['longitude'], 180);
  if (lat == null || lon == null || (lat == 0 && lon == 0)) {
    return (position: '未收到有效位置', reportedAt: null, status: '未收到有效位置');
  }
  final reported = DateTime.tryParse('${device['locationReportedAt'] ?? ''}');
  final age = reported == null
      ? null
      : (now ?? DateTime.now()).difference(reported);
  final freshness = '${device['locationFreshness'] ?? ''}'.toUpperCase();
  final String status;
  if (device['online'] == false || device['online'] == 0) {
    status = '最后上报（设备离线）';
  } else if (freshness == 'STALE' ||
      (age != null && age > const Duration(minutes: 5))) {
    status = '最后上报（已过期）';
  } else if (freshness == 'CURRENT' && age != null && !age.isNegative) {
    status = '近期上报';
  } else {
    status = '最后上报（时效未知）';
  }
  return (
    position: '纬度 ${lat.toStringAsFixed(6)}，经度 ${lon.toStringAsFixed(6)}',
    reportedAt: reported?.toUtc().toIso8601String(),
    status:
        device['coordinateSystem'] == 'UNKNOWN' ||
            device['coordinateSystem'] == null
        ? '$status · 坐标系未确认（原始坐标）'
        : status,
  );
}
