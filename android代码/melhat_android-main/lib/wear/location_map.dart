import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'core.dart';

bool isCurrentLocation(JsonMap row, {DateTime? now}) {
  if (row['locationFreshness'] != 'CURRENT') return false;
  final time = DateTime.tryParse(
    idOf(row['locationReportedAt'] ?? row['reportedAt']),
  );
  final age = time == null ? null : (now ?? DateTime.now()).difference(time);
  return age != null && !age.isNegative && age <= const Duration(minutes: 5);
}

LatLng? verifiedLocation(JsonMap row) {
  if (!const ['GCJ02', 'WGS84'].contains(row['coordinateSystem']) ||
      !const [
        'valid',
        'ok',
        'good',
      ].contains(idOf(row['locationQuality']).toLowerCase())) {
    return null;
  }
  final lat = double.tryParse('${row['latitude'] ?? row['locationLat']}');
  final lon = double.tryParse('${row['longitude'] ?? row['locationLng']}');
  if (lat == null ||
      lon == null ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() > 85.05112878 ||
      lon.abs() > 180 ||
      lat == 0 && lon == 0) {
    return null;
  }
  return LatLng(lat, lon);
}

String locationTimeValue(JsonMap row) {
  final basis =
      row['locationTimeBasis'] ??
      (row['collectedAt'] != null ? 'DEVICE_COLLECTED_AT' : 'RECEIVED_AT');
  return switch (basis) {
    'DEVICE_COLLECTED_AT' => idOf(row['collectedAt'] ?? row['reportedAt']),
    'RECEIVED_AT' => idOf(
      row['receivedAt'] ?? row['reportedAt'] ?? row['locationReportedAt'],
    ),
    _ => '',
  };
}

String locationTimeLabel(JsonMap row) => switch (row['locationTimeBasis'] ??
    (row['collectedAt'] != null ? 'DEVICE_COLLECTED_AT' : 'RECEIVED_AT')) {
  'DEVICE_COLLECTED_AT' => '设备采集时间',
  'RECEIVED_AT' => '平台接收时间（采集时间未确认）',
  _ => '时间依据未确认',
};

String _locationBinding(JsonMap row) =>
    '${idOf(row['personId'])}/${idOf(row['bindingId'] ?? row['assignmentId'] ?? row['locationAssignmentId'])}/${idOf(row['assignmentVersion'] ?? row['locationAssignmentVersion'])}';

/// Never join observations across missing fixes, changed issuance or reported gaps.
List<List<LatLng>> locationSegments(List<JsonMap> rows, String system) {
  final result = <List<LatLng>>[];
  List<LatLng>? segment;
  DateTime? previous;
  String? device;
  String? binding;
  final invalidDevices = <String>{};
  final seen = <String>{};
  // Stable time ordering within known-time runs. A record with no known time
  // remains a boundary in its received order; do not invent its observation time.
  final ordered = <JsonMap>[];
  final timed = <({JsonMap row, DateTime time, int index})>[];
  void flush() {
    timed.sort((a, b) {
      final order = a.time.compareTo(b.time);
      return order == 0 ? a.index.compareTo(b.index) : order;
    });
    ordered.addAll(timed.map((p) => p.row));
    timed.clear();
  }

  for (var index = 0; index < rows.length; index++) {
    final row = rows[index],
        time = DateTime.tryParse(locationTimeValue(rows[index]));
    if (time == null) {
      flush();
      ordered.add(row);
    } else {
      timed.add((row: row, time: time, index: index));
    }
  }
  flush();
  for (final row in ordered) {
    final point = verifiedLocation(row);
    final time = DateTime.tryParse(locationTimeValue(row));
    final rowDevice = idOf(row['deviceId']);
    if (point == null || time == null) {
      // A belt's unverified fix says nothing about the helmet's continuity.
      if (rowDevice.isNotEmpty) invalidDevices.add(rowDevice);
      continue;
    }
    if (row['coordinateSystem'] != system) {
      segment = null;
      previous = null;
      device = null;
      binding = null;
      continue;
    }
    final key = idOf(row['id']).isNotEmpty
        ? idOf(row['id'])
        : '$rowDevice/${_locationBinding(row)}/${time.toIso8601String()}/${point.latitude}/${point.longitude}';
    if (!seen.add(key)) continue;
    final interrupted = invalidDevices.remove(rowDevice);
    final difference = previous == null ? null : time.difference(previous);
    if (segment == null ||
        difference == null ||
        difference.isNegative ||
        difference > const Duration(minutes: 5) ||
        device != rowDevice ||
        binding != _locationBinding(row) ||
        interrupted ||
        row['gap'] == true) {
      segment = [];
      result.add(segment);
    }
    segment.add(point);
    previous = time;
    device = rowDevice;
    binding = _locationBinding(row);
  }
  return result;
}

class VerifiedLocationMap extends StatefulWidget {
  const VerifiedLocationMap({
    super.key,
    required this.rows,
    required this.system,
    this.interactive = true,
  });
  final List<JsonMap> rows;
  final String system;
  final bool interactive;
  @override
  State<VerifiedLocationMap> createState() => _VerifiedLocationMapState();
}

class _VerifiedLocationMapState extends State<VerifiedLocationMap> {
  bool _failed = false;
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final segments = locationSegments(widget.rows, widget.system);
    final all = segments.expand((s) => s).toList();
    if (all.isEmpty) return const Text('暂无可绘制定位；原始坐标仍保留，待坐标系与质量确认。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 250,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              key: ValueKey(
                '${widget.system}:$_attempt:${all.first}:${all.last}:${all.length}',
              ),
              options: MapOptions(
                interactionOptions: InteractionOptions(
                  flags: widget.interactive
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
                ),
                initialCenter: all.last,
                initialZoom: 16,
                initialCameraFit: all.length > 1
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(all),
                        padding: const EdgeInsets.all(28),
                        maxZoom: 17,
                      )
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: widget.system == 'GCJ02'
                      ? 'https://webst01.is.autonavi.com/appmaptile?style=7&x={x}&y={y}&z={z}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.melhat.wear',
                  errorTileCallback: (_, error, stack) {
                    if (!_failed) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _failed = true);
                      });
                    }
                  },
                ),
                PolylineLayer(
                  polylines: [
                    for (final segment in segments)
                      if (segment.length > 1)
                        Polyline(
                          points: segment,
                          color: WearColors.brand,
                          strokeWidth: 4,
                        ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final segment in segments)
                      Marker(
                        point: segment.last,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: WearColors.danger,
                          size: 36,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Text(
          '${widget.system == 'GCJ02' ? '高德地图' : '© OpenStreetMap contributors'} · ${widget.system} · 中断处不连线',
          style: const TextStyle(fontSize: 11, color: WearColors.muted),
        ),
        if (_failed)
          TextButton.icon(
            onPressed: () => setState(() {
              _failed = false;
              _attempt++;
            }),
            icon: const Icon(Icons.refresh),
            label: const Text('底图加载失败，点位数据仍可查看 · 重试'),
          ),
      ],
    );
  }
}
