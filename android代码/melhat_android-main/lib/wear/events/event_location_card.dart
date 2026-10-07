import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core.dart';
import 'event_models.dart';

/// Coordinates belong to the event snapshot, never the phone's current GPS.
LatLng? eventLocationPoint(WearEvent event) {
  final lat = double.tryParse(event.locationLat);
  final lng = double.tryParse(event.locationLng);
  if (lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat.abs() > 85.05112878 ||
      lng.abs() > 180) {
    return null;
  }
  return LatLng(lat, lng);
}

class EventLocationCard extends StatefulWidget {
  const EventLocationCard({super.key, required this.event});
  final WearEvent event;

  @override
  State<EventLocationCard> createState() => _EventLocationCardState();
}

class _EventLocationCardState extends State<EventLocationCard> {
  final _map = MapController();
  bool _tileFailed = false;
  int _retry = 0;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _tileError(Object _, Object error, StackTrace? stack) {
    if (_tileFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileFailed) setState(() => _tileFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final attempt = _retry;
    final point = eventLocationPoint(event);
    final session = WearScope.of(context);
    final quality = switch (event.locationQuality) {
      'ok' => '定位有效',
      'stale' => '定位已陈旧',
      _ => '定位质量未知',
    };
    return WearCard(
      key: const ValueKey('event-location-card'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: WearColors.brand,
                size: 20,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '事件定位',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: WearColors.ink,
                  ),
                ),
              ),
              WearBadge(
                text: point == null ? '位置未知' : quality,
                color: point != null && event.locationQuality == 'ok'
                    ? WearColors.brand
                    : WearColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '事件发生时的位置快照 · 非实时定位${event.demo ? ' · 演示数据' : ''}',
            style: const TextStyle(fontSize: 11, color: WearColors.muted),
          ),
          const SizedBox(height: 10),
          if (point == null)
            Container(
              key: const ValueKey('event-location-unavailable'),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6FC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.location_off_outlined,
                    size: 32,
                    color: WearColors.muted,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '暂无有效定位',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '设备未提供可用坐标，请联系现场人员核实；可继续研判与处置。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: WearColors.muted),
                  ),
                ],
              ),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 208,
                child: Stack(
                  children: [
                    FlutterMap(
                      key: ValueKey(
                        '${session.scopeKey}:${event.id}:${point.latitude}:${point.longitude}:$_retry',
                      ),
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: point,
                        initialZoom: 16,
                        minZoom: 3,
                        maxZoom: 19,
                        backgroundColor: const Color(0xFFEAF1F7),
                        interactionOptions: const InteractionOptions(
                          flags:
                              InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              '/api/v1/events/${Uri.encodeComponent(event.id)}/map-tiles/{z}/{x}/{y}',
                          panBuffer: 0,
                          tileProvider: _EventTileProvider(
                            session.api,
                          '${session.scopeKey}:$_retry',
                          ),
                        errorTileCallback: (tile, error, stack) {
                          if (attempt == _retry) _tileError(tile, error, stack);
                        },
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: point,
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.location_on,
                                size: 42,
                                color: event.locationQuality == 'ok'
                                    ? WearColors.danger
                                    : WearColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: IconButton.filledTonal(
                        tooltip: '回到事件位置',
                        onPressed: () => _map.move(point, 16),
                        icon: const Icon(Icons.my_location, size: 20),
                      ),
                    ),
                    const Positioned(
                      left: 4,
                      bottom: 4,
                      child: ColoredBox(
                        color: Color(0xE6FFFFFF),
                        child: Padding(
                          padding: EdgeInsets.all(3),
                          child: Text(
                            '© OpenStreetMap contributors',
                            style: TextStyle(
                              fontSize: 9,
                              color: WearColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_tileFailed)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '底图暂时无法加载，坐标仍可查看',
                      style: TextStyle(fontSize: 11, color: WearColors.warning),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _tileFailed = false;
                      _retry++;
                    }),
                    child: const Text('重试'),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            SelectableText(
              '纬度 ${point.latitude.toStringAsFixed(6)} · 经度 ${point.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 12, color: WearColors.ink),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '来源设备 ${event.sn.isEmpty ? '未知' : event.sn} · ${formatTime(event.occurredAt)}',
            style: const TextStyle(fontSize: 11, color: WearColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Tile requests use the same authenticated, cancellable main-backend API as
/// the event. Android never connects to an external map/device server directly.
class _EventTileProvider extends TileProvider {
  _EventTileProvider(this.api, this.scopeKey);
  final WearApi api;
  final String scopeKey;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _EventTileImage(api, scopeKey, getTileUrl(coordinates, options));
}

class _EventTileImage extends ImageProvider<_EventTileImage> {
  const _EventTileImage(this.api, this.scopeKey, this.path);
  final WearApi api;
  final String scopeKey, path;

  @override
  Future<_EventTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _EventTileImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final data = await api.get(path);
    if (data is! String || data.isEmpty) throw const FormatException('地图响应无效');
    return decode(await ui.ImmutableBuffer.fromUint8List(base64Decode(data)));
  }

  @override
  bool operator ==(Object other) =>
      other is _EventTileImage &&
      identical(api, other.api) &&
      scopeKey == other.scopeKey &&
      path == other.path;
  @override
  int get hashCode => Object.hash(api, scopeKey, path);
}
