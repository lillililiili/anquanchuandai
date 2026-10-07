import 'package:flutter/material.dart';
import '../core.dart';
import 'query_widgets.dart';
import 'query_utils.dart';
import 'management_widgets.dart';

class PersonEquipmentPage extends StatefulWidget {
  const PersonEquipmentPage({super.key, required this.id});
  final String id;
  @override
  State<PersonEquipmentPage> createState() => _PersonEquipmentPageState();
}

class _PersonEquipmentPageState extends State<PersonEquipmentPage> {
  WearSession? _session;
  List<JsonMap> _assigned = [], _devices = [];
  final _search = TextEditingController();
  bool _loading = true, _busy = false, _more = false;
  int _page = 1;
  Object? _error;
  final Map<String, String> _keys = {};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      _session = WearScope.of(context);
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assigned = jsonList(
        await _session!.api.get('/api/v1/people/${widget.id}/equipment'),
      );
      final devices = await _session!.api.page(
        '/api/v1/devices',
        current: page,
        query: {'assetStatus': 'in_stock', 'sn': _search.text.trim()},
      );
      if (mounted) {
        setState(() {
          _assigned = assigned;
          _devices = devices.records;
          _more = devices.hasMore;
          _page = page;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _assign(JsonMap row, bool returning) async {
    if (!await confirmManagement(
      context,
      returning ? '确认归还装备？' : '确认分配装备？',
      '${deviceTypeLabel(row['typeCode'])} · ${textOf(row['sn'])}',
    )) {
      return;
    }
    final action = '${returning ? 'return' : 'issue'}-${row['id']}';
    final key = _keys.putIfAbsent(
      action,
      () => 'android-${DateTime.now().microsecondsSinceEpoch}-$action',
    );
    setState(() => _busy = true);
    try {
      await _session!.api.post(
        returning
            ? '/api/v1/assignments/${row['id']}/return'
            : '/api/v1/assignments',
        data: {
          'idempotencyKey': key,
          if (returning) 'reason': '人员档案装备归还',
          if (!returning) 'personId': widget.id,
          if (!returning) 'deviceId': row['id'],
        },
      );
      _keys.remove(action);
      if (mounted) {
        managementMessage(context, returning ? '装备已归还' : '装备已分配');
        await _load();
      }
    } catch (e) {
      if (mounted) managementMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => QueryPage(
    title: '装备分配',
    subtitle: '仅显示当前厂站可分配的库存装备。',
    body: QueryStateView(
      loading: _loading,
      error: _error,
      empty: false,
      onRetry: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ManagementSection(
            title: '当前装备 · ${_assigned.length}',
            children: [
              if (_assigned.isEmpty) const Text('暂无领用装备'),
              for (final row in _assigned)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(deviceTypeLabel(row['typeCode'])),
                  subtitle: Text(textOf(row['sn'])),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _assign(row, true),
                    child: const Text('归还'),
                  ),
                ),
            ],
          ),
          ManagementSection(
            title: '分配新装备',
            children: [
              TextField(
                controller: _search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: '输入设备编号搜索',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
              if (_devices.isEmpty) const Text('没有可分配的库存装备'),
              for (final row in _devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(deviceTypeLabel(row['typeCode'])),
                  subtitle: Text(textOf(row['sn'])),
                  trailing: OutlinedButton(
                    onPressed: _busy ? null : () => _assign(row, false),
                    child: const Text('分配'),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _page > 1 && !_busy
                        ? () => _load(page: _page - 1)
                        : null,
                    child: const Text('上一页'),
                  ),
                  Text('第 $_page 页'),
                  TextButton(
                    onPressed: _more && !_busy
                        ? () => _load(page: _page + 1)
                        : null,
                    child: const Text('下一页'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
