import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../core.dart';
import '../location_map.dart';
import 'event_models.dart';

JsonMap _location(WearEvent e) => {
  'latitude': e.locationLat,
  'longitude': e.locationLng,
  'coordinateSystem': e.coordinateSystem,
  'locationQuality': e.locationQuality,
  'reportedAt': e.locationReportedAt.isNotEmpty
      ? e.locationReportedAt
      : e.occurredAt,
  'deviceId': e.deviceId,
};
LatLng? eventLocationPoint(WearEvent event) =>
    verifiedLocation(_location(event));

/// Render only the immutable event snapshot, never the person's current point.
class EventLocationCard extends StatelessWidget {
  const EventLocationCard({super.key, required this.event});
  final WearEvent event;
  @override
  Widget build(BuildContext context) {
    final point = eventLocationPoint(event);
    return WearCard(
      key: const ValueKey('event-location-card'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '事件定位',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            '事件发生时的位置快照 · 非实时定位',
            style: TextStyle(fontSize: 12, color: WearColors.muted),
          ),
          const SizedBox(height: 12),
          if (point == null)
            const Padding(
              key: ValueKey('event-location-unavailable'),
              padding: EdgeInsets.all(16),
              child: Text('暂无有效定位：坐标系或定位质量未确认。可继续研判与处置。'),
            )
          else
            VerifiedLocationMap(
              rows: [_location(event)],
              system: event.coordinateSystem,
            ),
          if (event.locationLat.isNotEmpty && event.locationLng.isNotEmpty)
            SelectableText(
              '原始纬度 ${event.locationLat} · 经度 ${event.locationLng} · ${event.coordinateSystem}',
            ),
          const SizedBox(height: 8),
          Text(
            '来源设备 ${event.sn.isEmpty ? '未知' : event.sn} · ${formatTime(event.locationReportedAt.isEmpty ? event.occurredAt : event.locationReportedAt)}',
            style: const TextStyle(fontSize: 11, color: WearColors.muted),
          ),
        ],
      ),
    );
  }
}
