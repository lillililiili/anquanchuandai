import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core.dart';
import 'notifications.dart';
import 'queries/queries.dart';

class WearMinePage extends StatefulWidget {
  final WearNotifications notifications;
  const WearMinePage({super.key, required this.notifications});
  @override
  State<WearMinePage> createState() => _WearMinePageState();
}

class _WearMinePageState extends State<WearMinePage> {
  WearSession? _session;
  List<JsonMap> _handovers = [];
  String? _error, _confirming;
  bool _loading = false;
  int _request = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (_session != session) {
      _session?.refreshTick.removeListener(_refresh);
      _session = session;
      session.refreshTick.addListener(_refresh);
      Future.microtask(_load);
    }
  }

  void _refresh() {
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = jsonList(await _session!.api.get('/api/v1/duty/handovers'));
      if (mounted && request == _request) setState(() => _handovers = rows);
    } catch (e) {
      if (mounted && request == _request && e is! StaleSessionException) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _confirm(JsonMap handover) async {
    if (_confirming != null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认接班'),
        content: Text(
          '确认接收 ${textOf(handover['fromUserName'])} 的交接责任？确认后请及时查看相关事件与作业。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('暂不接班'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认接班'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _confirming = idOf(handover['id']));
    try {
      await _session!.api.post(
        '/api/v1/duty/handovers/$_confirming/confirm',
        data: {},
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('接班已确认，请查看待处理事项')));
      }
      _session!.requestRefresh();
    } catch (e) {
      if (mounted && e is! StaleSessionException) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _confirming = null);
    }
  }

  String _payloadSummary(JsonMap row) {
    try {
      final payload = jsonMap(jsonDecode(textOf(row['payloadJson'], '{}')));
      return '${(payload['eventIds'] as List? ?? []).length} 条事件 · ${(payload['taskIds'] as List? ?? []).length} 项作业';
    } catch (_) {
      return '交接内容请查看工作台';
    }
  }

  @override
  void dispose() {
    _request++;
    _session?.refreshTick.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
        children: [
          WearBrandHero(
            title: '我的',
            subtitle:
                '你好，${textOf(session.me?['nickName'], textOf(session.me?['userName'], '值班员'))}！\n安全作业，平安每一天！',
            background: WearArt.mineHero,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          WearCard(
            child: Column(
              children: [
                _profileRow(
                  Icons.person_outline,
                  '姓名',
                  textOf(session.me?['nickName'], textOf(session.me?['userName'])),
                ),
                _profileRow(
                  Icons.badge_outlined,
                  '账号',
                  textOf(session.me?['userName']),
                ),
                _profileRow(Icons.factory_outlined, '厂站', session.siteName),
                _profileRow(
                  Icons.verified_user_outlined,
                  '角色',
                  session.roles
                      .map(
                        (role) =>
                            const {
                              'wear_duty': '值班员',
                              'wear_team_lead': '班组长',
                              'wear_reviewer': '复核员',
                              'wear_readonly': '只读',
                              'wear_device_admin': '设备管理员',
                              'wear_platform_admin': '平台管理员',
                              'admin': '管理员',
                            }[role] ??
                            role,
                      )
                      .join(' / '),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: widget.notifications,
            builder: (context, _) => WearCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '接警状态',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      WearBadge(
                        text: widget.notifications.socketConnected
                            ? '前台连接正常'
                            : '前台连接重试中',
                        color: widget.notifications.socketConnected
                            ? WearColors.primary
                            : WearColors.warning,
                      ),
                      WearBadge(
                        text: widget.notifications.permissionGranted
                            ? '通知权限已开启'
                            : '通知权限未开启',
                        color: widget.notifications.permissionGranted
                            ? WearColors.primary
                            : WearColors.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.notifications.status,
                    style: const TextStyle(color: WearColors.muted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: widget.notifications.requestPermission,
                        icon: const Icon(Icons.notifications_outlined),
                        label: const Text('开启通知'),
                      ),
                      TextButton(
                        onPressed: openAppSettings,
                        child: const Text('系统设置'),
                      ),
                      if (widget.notifications.configured &&
                          !widget.notifications.registered)
                        TextButton(
                          onPressed: widget.notifications.bind,
                          child: const Text('重试绑定'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const EquipmentPanel(),
          const SizedBox(height: 16),
          WearCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '值班交接',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新交接',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  WearEmpty(title: '交接加载失败', detail: _error, onRetry: _load)
                else if (_handovers.isEmpty && !_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      '暂无交接记录',
                      style: TextStyle(color: WearColors.muted),
                    ),
                  )
                else
                  for (final row in _handovers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${textOf(row['fromUserName'])} → ${textOf(row['toUserName'])}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${_payloadSummary(row)}\n${formatTime(row['createTime'])}',
                            style: const TextStyle(
                              color: WearColors.muted,
                              height: 1.6,
                            ),
                          ),
                          if (textOf(row['comment'], '').isNotEmpty)
                            Text(textOf(row['comment'])),
                          const SizedBox(height: 8),
                          WearBadge(
                            text: row['status'] == 'confirmed' ? '已接班' : '待接班',
                          ),
                          if (row['status'] == 'pending' &&
                              idOf(row['toUserId']) == session.userId &&
                              session.isDuty)
                            FilledButton(
                              onPressed: _confirming != null
                                  ? null
                                  : () => _confirm(row),
                              child: Text(
                                _confirming == idOf(row['id'])
                                    ? '正在确认…'
                                    : '确认接班',
                              ),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: session.callActive.value
                ? null
                : () => context.go('/sites'),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('切换厂站'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFE8E6),
              foregroundColor: WearColors.danger,
            ),
            onPressed: session.busy || session.callActive.value
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('退出当前账号？'),
                        content: const Text('将清除该账号在本机的草稿和缓存。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('保留登录'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('退出登录'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) await session.logout();
                  },
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Text(
              '智能穿戴管理平台 1.3.0\n真实通话、锁屏接警以联合验收记录为准',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WearColors.muted,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: WearColors.brand, size: 22),
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(color: WearColors.muted)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: WearColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
