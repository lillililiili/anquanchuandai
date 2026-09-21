import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import 'query_utils.dart';

/// Shared personal equipment reference, reachable from Mine and Workbench.
class MyEquipmentPage extends StatefulWidget {
  const MyEquipmentPage({super.key, this.backLabel = '返回我的'});

  final String backLabel;

  @override
  State<MyEquipmentPage> createState() => _MyEquipmentPageState();
}

class _MyEquipmentPageState extends State<MyEquipmentPage> {
  static const _ink = Color(0xFF112044);
  static const _muted = Color(0xFF6B89B3);
  static const _blue = Color(0xFF008FFF);
  static const _bg = Color(0xFFEEF8FF);
  // Compact reference: reduce natural layout height; never stretch artwork/text.
  WearSession? _session;
  String? _scope;
  List<JsonMap> _items = [];
  Object? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (_scope != session.scopeKey || !identical(session, _session)) {
      _session?.refreshTick.removeListener(_load);
      _session = session;
      _scope = session.scopeKey;
      session.refreshTick.addListener(_load);
      _items = [];
      _load();
    }
  }

  @override
  void dispose() {
    _session?.refreshTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final session = _session!;
    final scope = session.scopeKey;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await loadEquipmentWithTelemetry(
        session.api,
        '/api/v1/me/equipment',
      );
      if (!mounted || request != _request || scope != session.scopeKey) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          error is StaleSessionException ||
          request != _request ||
          scope != session.scopeKey) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  String _name(JsonMap item) => switch (item['typeCode']?.toString()) {
    'watch' => '智能手表',
    _ => deviceTypeLabel(item['typeCode']),
  };

  String _status(JsonMap item) => connectionLabel(item);

  @override
  Widget build(BuildContext context) {
    final rows = _items;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            key: const PageStorageKey('my-equipment-reference'),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _header(),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: WearEmpty(
                      title: '装备信息暂不可用',
                      detail: '请检查网络或访问权限后重试',
                      onRetry: _load,
                    ),
                  ),
                if (!_loading && _error == null && rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: WearEmpty(
                      title: '暂无领用装备',
                      detail: '当前账号尚未领用设备，以后台领用记录为准。',
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Column(
                    children: [
                      if (!_loading)
                        for (final item in rows) _card(item),
                      if (!_loading && _error == null) _historyRow(rows),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final session = _session!;
    final person = _items.isEmpty ? '' : textOf(_items.first['personName'], '');
    final name = person.isNotEmpty
        ? person
        : textOf(
            session.me?['nickName'],
            textOf(session.me?['userName'], '当前用户'),
          );
    final roles = session.roles
        .map(
          (r) =>
              const {
                'admin': '管理员',
                'wear_platform_admin': '平台管理员',
                'wear_duty': '值班员',
                'wear_team_lead': '班组长',
                'wear_readonly': '只读人员',
                'wear_reviewer': '复核员',
                'wear_device_admin': '设备管理员',
              }[r] ??
              r,
        )
        .join(' / ');
    return Container(
      key: const ValueKey('wear-page-hero-equipment'),
      height: WearHeaderLayout.height(context),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/field-brand/preview/equipment_reference_header.png',
          ),
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.only(bottom: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10, top: 2),
            child: Row(
              children: [
                IconButton(
                  tooltip: widget.backLabel,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: _ink,
                    size: 22,
                  ),
                ),
                const WearRollingWordmark(height: 23),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: LayoutBuilder(
              builder: (context, box) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) > 1.2;
                final profile = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const WearAssetImage(
                      WearArt.characterAvatar,
                      width: 43,
                      height: 43,
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            roles.isEmpty ? '当前人员' : roles,
                            style: const TextStyle(color: _muted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final title = Text(
                  '我的装备',
                  style: TextStyle(
                    color: _ink,
                    fontSize: WearHeaderLayout.titleSize,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                );
                if (largeText) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), profile],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 5, child: title),
                    const SizedBox(width: 5),
                    Expanded(flex: 4, child: profile),
                  ],
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 22),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '安全，从我做起！',
                style: TextStyle(
                  color: _blue,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(JsonMap item) {
    final type = item['typeCode']?.toString();
    final status = _status(item);
    final color = status == '在线'
        ? const Color(0xFF00C7A0)
        : status == '离线' || status == '数据陈旧'
        ? const Color(0xFFFFA000)
        : _muted;
    final time = item['lastReportedAt'] ?? item['lastTelemetryAt'];
    final timestamp = time == null ? '未知' : formatTime(time);
    final extra = type == 'belt' || type == 'watch';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('equipment-card-${idOf(item['deviceId'])}'),
          onTap: () => _openDevice(item),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 35,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                WearArt.equipment(type),
                                fit: BoxFit.cover,
                              ),
                              if (type == 'belt' && status != '在线')
                                const Positioned(
                                  left: 7,
                                  top: 9,
                                  child: Icon(
                                    Icons.warning_rounded,
                                    color: Color(0xFFFFA000),
                                    size: 24,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 61,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: extra ? 106 : 81,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _name(item),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      textOf(item['sn']),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: _muted,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 24,
                                    color: _muted,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${status == '连接中断' || status == '数据陈旧' ? '最后数据' : '更新'} $timestamp',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _muted,
                                ),
                              ),
                              if (item['telemetryUnavailable'] == true)
                                const Text(
                                  '设备状态暂不可用',
                                  style: TextStyle(fontSize: 10, color: _muted),
                                ),
                              if (extra)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: _notice(type == 'belt'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (type != 'watch')
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      type == 'belt'
                          ? '用于高处作业防护监测'
                          : type == 'helmet'
                          ? '用于人员定位与安全监测'
                          : '查看设备信息与领用记录',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(bool belt) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: belt ? const Color(0xFFFFF8EB) : const Color(0xFFEAF6FF),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(
        color: belt ? const Color(0xFFFFE2A3) : const Color(0xFFC3E4FF),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          belt ? Icons.error : Icons.info,
          color: belt ? const Color(0xFFFFA000) : _blue,
          size: 20,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                belt ? '断连不直接判定违规' : '传感能力待确认',
                style: TextStyle(
                  fontSize: 10,
                  color: belt ? const Color(0xFF845129) : _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                belt ? '挂接 / 受力状态待协议确认' : '具体功能以设备协议为准',
                style: const TextStyle(fontSize: 10, color: _muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _historyRow(List<JsonMap> rows) {
    final issued =
        rows.map((r) => r['issuedAt']?.toString()).whereType<String>().toList()
          ..sort();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _history(rows),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFE5F4FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment, color: _blue, size: 25),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '绑定历史',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      issued.isEmpty
                          ? '暂无当前领用记录'
                          : '本次领用 ${formatTime(issued.last)}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted),
            ],
          ),
        ),
      ),
    );
  }

  void _openDevice(JsonMap item) {
    final id = idOf(item['deviceId']);
    if (id.isNotEmpty) context.push('/devices/${Uri.encodeComponent(id)}');
  }

  Future<List<JsonMap>> _fetchHistory(List<JsonMap> rows) async {
    final session = _session!;
    final scope = session.scopeKey;
    final ids = rows
        .map((r) => idOf(r['personId']))
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return [];
    final results = await Future.wait(
      ids.map(
        (id) async => jsonList(
          await session.api.get(
            '/api/v1/people/${Uri.encodeComponent(id)}/assignments',
          ),
        ),
      ),
    );
    if (scope != session.scopeKey) throw StaleSessionException();
    return results.expand((r) => r).toList();
  }

  void _history(List<JsonMap> rows) {
    Future<List<JsonMap>>? future;
    final scope = _session!.scopeKey;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .65,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '绑定历史',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<JsonMap>>(
                    future: future ??= _fetchHistory(rows),
                    builder: (ctx, snapshot) {
                      if (scope != WearScope.of(ctx).scopeKey) {
                        return const Center(child: Text('账号或厂站已切换，请重新打开'));
                      }
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return WearEmpty(
                          title: '绑定历史暂不可用',
                          onRetry: () => update(() => future = null),
                        );
                      }
                      final records = snapshot.data ?? [];
                      if (records.isEmpty) {
                        return const Center(child: Text('暂无可查询的绑定历史'));
                      }
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: records
                            .map(
                              (row) => Card(
                                color: Colors.white,
                                child: ListTile(
                                  title: Text(
                                    '${_name(row)} · ${textOf(row['sn'])}',
                                  ),
                                  subtitle: Text(
                                    '领用 ${formatTime(row['issuedAt'])}\n${row['returnedAt'] == null ? '当前领用' : '归还 ${formatTime(row['returnedAt'])}'}${row['returnReason'] == null ? '' : '\n原因 ${textOf(row['returnReason'])}'}',
                                  ),
                                  isThreeLine: true,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
