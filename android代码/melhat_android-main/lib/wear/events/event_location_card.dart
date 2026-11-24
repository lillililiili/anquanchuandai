import 'package:flutter/material.dart';
import '../core.dart';
import '../location_map.dart';
import 'event_location.dart';
import 'event_models.dart';

export 'event_location.dart' show eventLocationPoint;

/// Render only the immutable event snapshot, never the person's current point.
class EventLocationCard extends StatefulWidget {
  const EventLocationCard({super.key, required this.event, required this.api});
  final WearEvent event;
  final WearApi api;
  @override
  State<EventLocationCard> createState() => _EventLocationCardState();
}

class _EventLocationCardState extends State<EventLocationCard> {
  Future<EventMapFix?>? _history;

  void _load() {
    _history = eventLocationPoint(widget.event) == null
        ? historicalEventFix(widget.api, widget.event)
        : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EventLocationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event != widget.event || oldWidget.api != widget.api) _load();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
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
            '事件发生时的设备上报位置',
            style: TextStyle(fontSize: 12, color: WearColors.muted),
          ),
          const SizedBox(height: 12),
          if (point != null)
            VerifiedLocationMap.point(
              point: point,
              system: event.coordinateSystem,
            )
          else
            FutureBuilder<EventMapFix?>(
              future: _history,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final fix = snapshot.data;
                if (fix != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VerifiedLocationMap.point(
                        point: fix.point,
                        system: fix.system,
                      ),
                      const Text(
                        '已与事发时的设备定位记录核对',
                        style: TextStyle(fontSize: 12, color: WearColors.muted),
                      ),
                    ],
                  );
                }
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  if (error is WearApiException &&
                      const {401, 403, 404}.contains(error.code)) {
                    return const Text('当前账号无法读取该时段的设备定位。');
                  }
                  return TextButton.icon(
                    onPressed: () => setState(_load),
                    icon: const Icon(Icons.refresh),
                    label: const Text('定位记录读取失败，点击重试'),
                  );
                }
                return const Text(
                  '未找到能核实这组坐标的事发定位记录。',
                  key: ValueKey('event-location-unavailable'),
                );
              },
            ),
          if (event.locationLat.isNotEmpty && event.locationLng.isNotEmpty)
            SelectableText(
              '原始纬度 ${event.locationLat} · 经度 ${event.locationLng}',
            ),
          const SizedBox(height: 8),
          Text(
            '来源设备 ${textOf(event.sn, textOf(event.deviceId, '未知'))}${event.locationReportedAt.isEmpty ? '' : ' · ${formatTime(event.locationReportedAt)}'}',
            style: const TextStyle(fontSize: 11, color: WearColors.muted),
          ),
        ],
      ),
    );
  }
}
