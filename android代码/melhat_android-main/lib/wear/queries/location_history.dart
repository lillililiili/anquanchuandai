import 'package:flutter/material.dart';
import '../core.dart';
import '../location_map.dart';
import 'query_widgets.dart';

class LocationHistoryPage extends StatefulWidget {
  const LocationHistoryPage({super.key, required this.personId});
  final String personId;
  @override
  State<LocationHistoryPage> createState() => _LocationHistoryPageState();
}

class _LocationHistoryPageState extends State<LocationHistoryPage> {
  WearSession? _session;
  DateTime _date = DateTime.now().toUtc().add(const Duration(hours: 8));
  List<JsonMap> _rows = [];
  String? _cursor;
  bool _busy = true;
  Object? _error;
  int _request = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = WearScope.of(context);
    if (!identical(next, _session)) {
      _session = next;
      _load();
    }
  }

  Future<void> _load({bool more = false}) async {
    final session = _session!;
    final scope = session.scopeKey, request = ++_request;
    final from = DateTime.utc(
      _date.year,
      _date.month,
      _date.day,
    ).subtract(const Duration(hours: 8));
    setState(() {
      _busy = true;
      _error = null;
      if (!more) {
        _rows = [];
        _cursor = null;
      }
    });
    try {
      final data = jsonMap(
        await session.api.get(
          '/api/v1/locations/history',
          query: {
            'personId': widget.personId,
            'from': from.toIso8601String(),
            'to': from.add(const Duration(days: 1)).toIso8601String(),
            'limit': 500,
            if (more && _cursor != null) 'cursor': _cursor,
          },
        ),
      );
      if (!mounted || scope != session.scopeKey || request != _request) return;
      setState(() {
        _rows = [..._rows, ...jsonList(data['rows'])];
        _cursor = data['nextCursor'] as String?;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || scope != session.scopeKey || request != _request) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => QueryPage(
    title: '人员轨迹',
    subtitle: '按北京时间查询，按每条定位发生时的人员与厂站授权。',
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(
              '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}（北京时间）',
            ),
            onPressed: _busy
                ? null
                : () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (selected != null && mounted) {
                      _date = selected;
                      await _load();
                    }
                  },
          ),
        ),
        Expanded(
          child: QueryStateView(
            loading: _busy && _rows.isEmpty,
            error: _rows.isEmpty ? _error : null,
            empty: _rows.isEmpty,
            emptyTitle: '这一天没有授权范围内的定位记录',
            onRetry: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '已读取 ${_rows.length} 条 · 坐标系未知或定位质量不明的记录不绘图',
                  style: const TextStyle(color: WearColors.muted),
                ),
                for (final system in ['GCJ02', 'WGS84'])
                  if (_rows.any(
                    (r) =>
                        r['coordinateSystem'] == system &&
                        verifiedLocation(r) != null,
                  ))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: VerifiedLocationMap(rows: _rows, system: system),
                    ),
                if (_error != null)
                  TextButton(
                    onPressed: () => _load(more: true),
                    child: const Text('后续记录加载失败，点击重试'),
                  ),
                if (_cursor != null)
                  OutlinedButton(
                    onPressed: _busy || _rows.length >= 5000
                        ? null
                        : () => _load(more: true),
                    child: Text(
                      _busy
                          ? '正在读取…'
                          : _rows.length >= 5000
                          ? '已达 5000 条显示上限，请使用 PC 查询完整记录'
                          : '读取后续轨迹',
                    ),
                  ),
                for (final row in _rows)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      verifiedLocation(row) == null
                          ? Icons.location_off_outlined
                          : Icons.location_on_outlined,
                    ),
                    title: Text(formatTime(row['reportedAt'])),
                    subtitle: Text(
                      '${row['latitude'] ?? '未知'}, ${row['longitude'] ?? '未知'} · ${row['coordinateSystem'] ?? 'UNKNOWN'}\n设备 ${row['deviceId'] ?? '未知'} · ${row['locationSource'] ?? '未知来源'}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
