import 'package:flutter/material.dart';

/// 快捷操作项模型
class QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  QuickAction({required this.icon, required this.label, this.onTap});
}

/// 告警记录模型
class AlarmRecord {
  final AlarmType type;
  final String detail;
  final DateTime time;

  AlarmRecord({required this.type, required this.detail, required this.time});

  String get timeString =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String get dateString => '${time.month}-${time.day}';
}

/// 告警类型枚举
enum AlarmType { sos, fall, heartRate, geoFence, lowBattery, offline }

extension AlarmTypeExtension on AlarmType {
  String get label {
    switch (this) {
      case AlarmType.sos:
        return 'SOS 求救';
      case AlarmType.fall:
        return '跌倒告警';
      case AlarmType.heartRate:
        return '心率异常';
      case AlarmType.geoFence:
        return '越界告警';
      case AlarmType.lowBattery:
        return '低电量';
      case AlarmType.offline:
        return '设备离线';
    }
  }

  IconData get icon {
    switch (this) {
      case AlarmType.sos:
        return Icons.sos;
      case AlarmType.fall:
        return Icons.accessibility_new;
      case AlarmType.heartRate:
        return Icons.favorite;
      case AlarmType.geoFence:
        return Icons.location_off;
      case AlarmType.lowBattery:
        return Icons.battery_alert;
      case AlarmType.offline:
        return Icons.wifi_off;
    }
  }

  Color get color {
    switch (this) {
      case AlarmType.sos:
        return Colors.red;
      case AlarmType.fall:
        return Colors.orange;
      case AlarmType.heartRate:
        return Colors.pink;
      case AlarmType.geoFence:
        return Colors.amber;
      case AlarmType.lowBattery:
        return Colors.brown;
      case AlarmType.offline:
        return Colors.grey;
    }
  }
}

/// 设备状态模型
class DeviceStatus {
  final String deviceName;
  final String userName;
  final bool isOnline;

  DeviceStatus({
    required this.deviceName,
    required this.userName,
    this.isOnline = true,
  });
}
