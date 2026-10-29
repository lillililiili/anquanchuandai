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
      !const ['valid', 'ok'].contains(row['locationQuality'])) {
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

/// Never join observations across missing fixes, a device change or a five-minute gap.
List<List<LatLng>> locationSegments(List<JsonMap> rows, String system) {
  final result = <List<LatLng>>[];
  List<LatLng>? segment;
  DateTime? previous;
  String? device;
  for (final row in rows) {
    final point = verifiedLocation(row);
    final time = DateTime.tryParse(
      idOf(row['reportedAt'] ?? row['locationReportedAt']),
    );
    if (point == null || row['coordinateSystem'] != system || time == null) {
      segment = null;
      previous = null;
      device = null;
      continue;
    }
    final difference = previous == null ? null : time.difference(previous);
    if (segment == null ||
        difference == null ||
        difference.isNegative ||
        difference > const Duration(minutes: 5) ||
        device != idOf(row['deviceId'])) {
      segment = [];
      result.add(segment);
    }
    segment.add(point);
    previous = time;
    device = idOf(row['deviceId']);
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
