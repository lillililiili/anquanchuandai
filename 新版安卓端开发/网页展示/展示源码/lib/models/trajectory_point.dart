import 'hat_location_record.dart';

/// 轨迹点数据模型
///
/// 包含轨迹回放所需的基础字段：经纬度和时间戳
class TrajectoryPoint {
  final double latitude;
  final double longitude;
  final String timestamp;
  final DateTime dateTime;

  const TrajectoryPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.dateTime,
  });

  /// 从 [HatLocationRecord] 转换
  factory TrajectoryPoint.fromHatLocationRecord(HatLocationRecord record) {
    final timestamp = record.timestamp ?? '';
    // 解析 "2026-03-30 17:19:00" 格式的日期时间
    DateTime? dateTime;
    if (timestamp.isNotEmpty) {
      // 尝试将空格替换为 T 以支持 ISO 8601 格式
      final isoFormat = timestamp.replaceAll(' ', 'T');
      dateTime = DateTime.tryParse(isoFormat);
    }

    return TrajectoryPoint(
      latitude: record.lat != null ? double.parse(record.lat!) : 0.0,
      longitude: record.lng != null ? double.parse(record.lng!) : 0.0,
      timestamp: timestamp,
      dateTime: dateTime ?? DateTime.now(),
    );
  }

  /// 从列表转换
  static List<TrajectoryPoint> fromList(List<HatLocationRecord> records) {
    return records.map((r) => TrajectoryPoint.fromHatLocationRecord(r)).toList();
  }
}
