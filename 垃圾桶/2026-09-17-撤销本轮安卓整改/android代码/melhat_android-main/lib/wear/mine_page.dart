import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core.dart';
import 'notifications.dart';
import 'queries/people.dart';
import 'queries/query_widgets.dart';

class WearMinePage extends StatelessWidget {
  final WearNotifications notifications;
  const WearMinePage({super.key, required this.notifications});

  void _open(BuildContext context, Widget page) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = textOf(
      session.me?['nickName'],
      textOf(session.me?['userName'], '值班员'),
    );
    final roles = session.roles
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
        .join(' / ');
    return WearPageBackground(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          WearCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colors.surfaceContainerHighest,
                      foregroundColor: colors.onSurface,
                      child: const Icon(Icons.person_outline),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '账号  ${textOf(session.me?['userName'])}',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                DetailField(label: '当前厂站', value: session.siteName),
                DetailField(
                  label: '授权角色',
                  value: roles.isEmpty ? '暂无角色信息' : roles,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          QueryRow(
            title: '我的装备',
            subtitle: '本人实际领用的装备与领用记录',
            leading: const Icon(Icons.safety_check_outlined),
            onTap: () => _open(context, const _MyEquipmentPage()),
          ),
          ListenableBuilder(
            listenable: notifications,
            builder: (context, _) => QueryRow(
              title: '接警设置',
              subtitle:
                  '${notifications.socketConnected ? '前台连接正常' : '前台连接重试中'} · ${notifications.permissionGranted ? '通知已开启' : '通知未开启'}',
              leading: const Icon(Icons.notifications_outlined),
              onTap: () => _open(
                context,
                _NotificationSettingsPage(notifications: notifications),
              ),
            ),
          ),
          QueryRow(
            title: '值班交接',
            subtitle: '查看责任范围与接班确认',
            leading: const Icon(Icons.swap_horiz),
            onTap: () => _open(context, const _HandoversPage()),
          ),
          const SizedBox(height: 20),
          QueryRow(
            title: '外观',
            subtitle: dark ? '当前为深色' : '当前为浅色',
            leading: const Icon(Icons.contrast),
            trailing: const WearThemeButton(),
          ),
          QueryRow(
            title: '帮助与说明',
            subtitle: '接警、装备与位置使用说明',
            leading: const Icon(Icons.help_outline),
            onTap: () => _open(context, const _HelpPage()),
          ),
          const SizedBox(height: 24),
          ListenableBuilder(
            listenable: session.callActive,
            builder: (context, _) => OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: colors.error),
              onPressed: session.busy || session.callActive.value
                  ? null
                  : () => _logout(context, session),
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WearSession session) async {
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
  }
}

class _MyEquipmentPage extends StatelessWidget {
  const _MyEquipmentPage();
  @override
  Widget build(BuildContext context) => QueryPage(
    title: '我的装备',
    subtitle: '仅展示当前账号关联人员的实际领用装备。',
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: const [EquipmentPanel()],
    ),
  );
}

class _NotificationSettingsPage extends StatelessWidget {
  const _NotificationSettingsPage({required this.notifications});
  final WearNotifications notifications;
  @override
  Widget build(BuildContext context) => QueryPage(
    title: '接警设置',
    body: ListenableBuilder(
      listenable: notifications,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          WearCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailField(
                  label: '前台连接',
                  value: notifications.socketConnected ? '连接正常' : '正在重试',
                ),
                DetailField(
                  label: '通知权限',
                  value: notifications.permissionGranted ? '已开启' : '未开启',
                ),
                DetailField(
                  label: '推送绑定',
                  value: notifications.registered ? '已绑定' : '未绑定',
                ),
                const SizedBox(height: 12),
                Text(
                  notifications.status,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!notifications.permissionGranted)
            FilledButton.icon(
              onPressed: notifications.requestPermission,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('开启通知权限'),
            ),
          OutlinedButton.icon(
            onPressed: openAppSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('打开系统设置'),
          ),
          if (notifications.configured && !notifications.registered)
            OutlinedButton(
              onPressed: notifications.bind,
              child: const Text('重试推送绑定'),
            ),
          const SizedBox(height: 16),
          const WearCard(
            child: Text(
              '锁屏与后台接警还受系统通知、后台运行限制及推送服务影响。连接或绑定成功不代表每条通知均已送达；发现异常请联系管理员核对。',
            ),
          ),
        ],
      ),
    ),
  );
}

class _HelpPage extends StatelessWidget {
  const _HelpPage();
  @override
  Widget build(BuildContext context) => QueryPage(
    title: '帮助与说明',
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        QuerySection(
          title: '联系人员',
          children: [
            WearCard(
              child: Text(
                '在通讯中按人员选择，再确认可用终端和语音、视频或播报方式。同一人员可领用多件装备；没有通讯能力的装备可通过其持有人联系。',
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        QuerySection(
          title: '接警与交接',
          children: [
            WearCard(
              child: Text(
                '从告警查看事件、联系人员并执行已授权操作。结束通话不会完成事件处置。交接发起后，须由接班人确认才会转移责任。',
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        QuerySection(
          title: '位置与装备状态',
          children: [
            WearCard(
              child: Text('位置显示来源和最后上报时间。楼层未知时不会推算楼层；数据陈旧或装备离线不等于发生未挂钩等违规。'),
            ),
          ],
        ),
        SizedBox(height: 20),
        QuerySection(
          title: '账号与权限帮助',
          children: [
            WearCard(
              child: Text('账号、厂站授权或人员关联有误时，请联系所在单位管理员。提供账号和问题发生时间，勿提供密码。'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _HandoversPage extends StatefulWidget {
  const _HandoversPage();
  @override
  State<_HandoversPage> createState() => _HandoversPageState();
}

class _HandoversPageState extends State<_HandoversPage> {
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
    final session = _session!;
    final scope = session.scopeKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = jsonList(await session.api.get('/api/v1/duty/handovers'));
      if (mounted && request == _request && scope == session.scopeKey) {
        setState(() => _handovers = rows);
      }
    } catch (e) {
      if (mounted &&
          request == _request &&
          scope == session.scopeKey &&
          e is! StaleSessionException) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && request == _request && scope == session.scopeKey) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirm(JsonMap handover) async {
    final session = _session!;
    final scope = session.scopeKey;
    if (_confirming != null ||
        !session.isDuty ||
        idOf(handover['toUserId']) != session.userId) {
      return;
    }
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
    if (approved != true || !mounted || scope != session.scopeKey) return;
    setState(() => _confirming = idOf(handover['id']));
    try {
      await session.api.post(
        '/api/v1/duty/handovers/$_confirming/confirm',
        data: {},
      );
      if (mounted && scope == session.scopeKey) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('接班已确认，请查看待处理事项')));
      }
      if (scope == session.scopeKey) session.requestRefresh();
    } catch (e) {
      if (mounted && scope == session.scopeKey && e is! StaleSessionException) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted && scope == session.scopeKey) {
        setState(() => _confirming = null);
      }
    }
  }

  String _payloadSummary(JsonMap row) {
    try {
      final payload = jsonMap(jsonDecode(textOf(row['payloadJson'], '{}')));
      return '${(payload['eventIds'] as List? ?? []).length} 条事件 · ${(payload['taskIds'] as List? ?? []).length} 项作业';
    } catch (_) {
      return '交接范围暂不可读，请联系交班人核对';
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
    return QueryPage(
      title: '值班交接',
      subtitle: '接班人确认前，原责任保持不变。',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (session.isDuty) ...[
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _CreateHandoverPage(),
                    ),
                  );
                  if (mounted) _load();
                },
                icon: const Icon(Icons.add),
                label: const Text('发起交接'),
              ),
              const SizedBox(height: 16),
            ],
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              WearEmpty(title: '交接加载失败', detail: _error, onRetry: _load)
            else if (_handovers.isEmpty && !_loading)
              const WearEmpty(title: '暂无交接记录')
            else
              for (final row in _handovers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: WearCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${textOf(row['fromUserName'])} → ${textOf(row['toUserName'])}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(_payloadSummary(row)),
                        Text(
                          formatTime(row['createTime']),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (textOf(row['comment'], '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(textOf(row['comment'])),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: WearBadge(
                            text: switch (row['status']) {
                              'confirmed' => '已接班',
                              'pending' => '待接班',
                              _ => '状态未知',
                            },
                          ),
                        ),
                        if (row['status'] == 'pending' &&
                            idOf(row['toUserId']) == session.userId &&
                            session.isDuty)
                          FilledButton(
                            onPressed: _confirming != null
                                ? null
                                : () => _confirm(row),
                            child: Text(
                              _confirming == idOf(row['id']) ? '正在确认…' : '确认接班',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _CreateHandoverPage extends StatefulWidget {
  const _CreateHandoverPage();
  @override
  State<_CreateHandoverPage> createState() => _CreateHandoverPageState();
}

class _CreateHandoverPageState extends State<_CreateHandoverPage> {
  final _formKey = GlobalKey<FormState>();
  final _comment = TextEditingController();
  WearSession? _session;
  List<JsonMap> _operators = const [];
  String? _toUserId;
  Object? _error;
  bool _loading = true, _sending = false;
  int _request = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (_session != session) {
      _session = session;
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    _comment.dispose();
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
      final rows = jsonList(await session.api.get('/api/v1/duty/operators'));
      if (!mounted || request != _request || scope != session.scopeKey) return;
      setState(() {
        _operators = rows
            .where((row) => idOf(row['userId']) != session.userId)
            .toList();
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

  Future<void> _submit() async {
    if (_sending ||
        !_session!.isDuty ||
        _formKey.currentState?.validate() != true) {
      return;
    }
    final session = _session!;
    final scope = session.scopeKey;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await session.api.post(
        '/api/v1/duty/handovers',
        data: {
          'toUserId': _toUserId,
          if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
        },
      );
      if (!mounted || scope != session.scopeKey) return;
      session.requestRefresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('交接已发起，等待接班人确认')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted ||
          error is StaleSessionException ||
          scope != session.scopeKey) {
        return;
      }
      setState(() => _error = error);
      if (error is WearApiException && error.code == 409) {
        session.requestRefresh();
      }
    } finally {
      if (mounted && scope == session.scopeKey) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => QueryPage(
    title: '发起值班交接',
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const WearCard(child: Text('交接范围为当前负责的事件与作业，提交后由接班人确认。')),
        const SizedBox(height: 20),
        if (_loading)
          const LinearProgressIndicator()
        else if (_operators.isEmpty)
          WearEmpty(
            title: _error == null ? '暂无可接班的其他值班人员' : '接班人加载失败',
            detail: _error?.toString(),
            onRetry: _load,
          )
        else
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _toUserId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '接班人'),
                  items: _operators
                      .map(
                        (row) => DropdownMenuItem(
                          value: idOf(row['userId']),
                          child: Text(
                            textOf(row['nickName'], textOf(row['userName'])),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _toUserId = value),
                  validator: (value) => value == null ? '请选择接班人' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _comment,
                  readOnly: _sending,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: '交接备注（选填）',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error is WearApiException
                          ? (_error as WearApiException).message
                          : '提交未完成，请重试。已保留填写内容。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: Text(_sending ? '提交中…' : '提交交接'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
