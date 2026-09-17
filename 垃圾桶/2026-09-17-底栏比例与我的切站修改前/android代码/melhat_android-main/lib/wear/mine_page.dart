import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core.dart';
import 'notifications.dart';
import 'package:flutter/services.dart';
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
  final _detailTick = ValueNotifier<int>(0);
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
    _detailTick.value++;
    try {
      final rows = jsonList(await _session!.api.get('/api/v1/duty/handovers'));
      if (mounted && request == _request) setState(() => _handovers = rows);
    } catch (e) {
      if (mounted && request == _request && e is! StaleSessionException) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
        _detailTick.value++;
      }
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
    _detailTick.value++;
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
      if (mounted) {
        setState(() => _confirming = null);
        _detailTick.value++;
      }
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
    _detailTick.dispose();
    _session?.refreshTick.removeListener(_refresh);
    super.dispose();
  }

  static const _blue = Color(0xFF008FFF);
  static const _ink = Color(0xFF112044);
  static const _muted = Color(0xFF6F89AE);

  String _roleLabel(WearSession session) => session.roles
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

  void _openDetail(String title, Widget Function(BuildContext) contents) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          backgroundColor: const Color(0xFFEEF7FF),
          appBar: AppBar(
            title: Text(title),
            leading: IconButton(
              tooltip: '返回我的',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: AnimatedBuilder(
            animation: Listenable.merge([
              _detailTick,
              widget.notifications,
              _session!,
            ]),
            builder: (ctx, _) => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SizedBox(width: double.infinity, child: contents(ctx)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _leaveAccount({required bool switching}) async {
    final session = _session!;
    if (session.busy || session.callActive.value) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(switching ? '切换当前账号？' : '退出当前账号？'),
        content: Text(
          switching ? '退出当前账号并返回登录页，当前账号的本机草稿和缓存将被清除。' : '退出后将清除当前账号的本机草稿和缓存。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(switching ? '确认切换' : '确认退出'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && !session.callActive.value) {
      await session.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    final name = textOf(
      session.me?['nickName'],
      textOf(session.me?['userName'], '值班员'),
    );
    final role = _roleLabel(session);
    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = (constraints.maxWidth / 390).clamp(0.85, 1.3);
        return RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            key: const PageStorageKey('mine-reference'),
            physics: const AlwaysScrollableScrollPhysics(),
            child: ColoredBox(
              color: const Color(0xFFEEF8FF),
              child: Column(
                children: [
                  SizedBox(
                    height:
                        (225 +
                            (MediaQuery.textScalerOf(context).scale(1) - 1)
                                    .clamp(0, 2) *
                                110) *
                        unit,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/field-brand/preview/mine_reference_hero.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.bottomCenter,
                          ),
                        ),
                        Positioned(
                          top: 16 * unit,
                          left: 22 * unit,
                          child: const WearRollingWordmark(height: 25),
                        ),
                        Positioned(
                          top: 24 * unit,
                          right: 16 * unit,
                          child: Text(
                            session.siteName,
                            style: TextStyle(
                              fontSize: 11 * unit,
                              color: _muted,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 23 * unit,
                          top: 65 * unit,
                          width: 171 * unit,
                          bottom: 8 * unit,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '我的',
                                style: TextStyle(
                                  fontSize: 34 * unit,
                                  height: 1.15,
                                  fontWeight: FontWeight.w900,
                                  color: _ink,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '你好，',
                                style: TextStyle(
                                  fontSize: 16 * unit,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                              Text(
                                '$name！',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 23 * unit,
                                  height: 1.3,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                              SizedBox(height: 7 * unit),
                              Text(
                                '安全作业，平安每一天！',
                                style: TextStyle(
                                  fontSize: 11 * unit,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 7 * unit,
                          top: 117 * unit,
                          child: Transform.rotate(
                            angle: -0.16,
                            child: Text(
                              '安全\n从我做起！',
                              textScaler: TextScaler.noScaling,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _blue,
                                fontSize: 13 * unit,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      15 * unit,
                      0,
                      15 * unit,
                      20 * unit,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _surface(
                          Column(
                            children: [
                              _profileRow(
                                Icons.person_outline,
                                '姓名',
                                name,
                                blue: true,
                                suffix: role,
                              ),
                              _profileRow(
                                Icons.person_outline,
                                '账号',
                                textOf(session.me?['userName']),
                                blue: true,
                              ),
                              _profileRow(
                                Icons.business_outlined,
                                '厂站',
                                session.siteName,
                              ),
                              _profileRow(
                                Icons.engineering_outlined,
                                '角色',
                                role,
                              ),
                              _profileRow(
                                Icons.badge_outlined,
                                'SIP ID',
                                textOf(session.me?['sipId'], '未分配'),
                                last: true,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 11 * unit),
                        _surface(
                          InkWell(
                            onTap: () =>
                                _openDetail('通讯服务', (_) => _notificationCard()),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 13 * unit,
                                vertical: 13 * unit,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cell_tower,
                                    color: const Color(0xFFFF9800),
                                    size: 34 * unit,
                                  ),
                                  SizedBox(width: 10 * unit),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '通讯服务',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: _ink,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'SIP / Agora兼容性待验证',
                                          style: TextStyle(
                                            fontSize: 10.5 * unit,
                                            color: _muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF4D1),
                                      border: Border.all(
                                        color: const Color(0xFFFFDE87),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '!  待联调',
                                      style: TextStyle(
                                        color: Color(0xFFF39800),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: _muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 11 * unit),
                        _surface(
                          Column(
                            children: [
                              _menuRow(
                                Icons.safety_check,
                                const Color(0xFF00BC75),
                                '我的装备',
                                () => _openDetail(
                                  '我的装备',
                                  (_) => const EquipmentPanel(),
                                ),
                              ),
                              _menuRow(
                                Icons.settings,
                                const Color(0xFF9256F8),
                                '设置',
                                () =>
                                    _openDetail('设置', (ctx) => _settings(ctx)),
                              ),
                              _menuRow(
                                Icons.chat,
                                _blue,
                                '帮助与反馈',
                                () => _openDetail('帮助与反馈', (ctx) => _help(ctx)),
                                last: true,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12 * unit),
                        OutlinedButton.icon(
                          onPressed: session.busy || session.callActive.value
                              ? null
                              : () => _leaveAccount(switching: true),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 44),
                            foregroundColor: _blue,
                            side: const BorderSide(color: _blue),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          icon: const Icon(Icons.login, size: 22),
                          label: const Text(
                            '切换账号',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(height: 10 * unit),
                        FilledButton.icon(
                          onPressed: session.busy || session.callActive.value
                              ? null
                              : () => _leaveAccount(switching: false),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 44),
                            elevation: 0,
                            backgroundColor: const Color(0xFFFFE9EF),
                            foregroundColor: const Color(0xFFEF1644),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          icon: const Icon(Icons.logout, size: 22),
                          label: const Text(
                            '退出登录',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _surface(Widget child) => Material(
    color: Colors.white.withValues(alpha: 0.96),
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _profileRow(
    IconData icon,
    String label,
    String value, {
    bool blue = false,
    bool last = false,
    String? suffix,
  }) {
    final accent = blue ? _blue : const Color(0xFF9564EF);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 23),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: last
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Color(0xFFE9F0F8)),
                      ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      label,
                      style: const TextStyle(color: _muted, fontSize: 14),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (suffix != null &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.1)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          suffix,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
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

  Widget _menuRow(
    IconData icon,
    Color color,
    String title,
    VoidCallback onTap, {
    bool last = false,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFE9F0F8))),
        ),
        child: Row(
          children: [
            title == '我的装备'
                ? const CustomPaint(
                    size: Size(27, 27),
                    painter: _MineHelmetPainter(),
                  )
                : Icon(icon, color: color, size: 27),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: _muted, size: 23),
          ],
        ),
      ),
    ),
  );

  Widget _settings(BuildContext ctx) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _surface(
        ListTile(
          leading: const Icon(Icons.factory_outlined),
          title: const Text('切换厂站'),
          trailing: const Icon(Icons.chevron_right),
          enabled: !_session!.callActive.value,
          onTap: _session!.callActive.value
              ? null
              : () {
                  Navigator.of(ctx).pop();
                  context.go('/sites');
                },
        ),
      ),
      const SizedBox(height: 16),
      _handoverCard(),
      const SizedBox(height: 16),
      const Text(
        '智能穿戴管理平台 1.3.0',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 12),
      ),
    ],
  );

  Widget _help(BuildContext ctx) => _surface(
    Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '使用帮助',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          const Text(
            '我的装备：查看当前账号关联人员的设备和绑定记录。\n\n通讯服务：查看接警连接、通知权限和绑定状态。\n\n设置：切换厂站、查看并确认值班交接。\n\n账号操作：确认后退出当前账号；通话中请先结束通话。',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 18),
          const Text(
            '遇到问题时，可复制以下诊断信息交给管理员；不会包含密码或登录凭证。',
            style: TextStyle(color: _muted, height: 1.5),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined),
            label: const Text('复制诊断信息'),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text:
                      '智能穿戴管理平台 1.3.0\n厂站：${_session!.siteName}\n通知：${widget.notifications.status}',
                ),
              );
              if (ctx.mounted) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('诊断信息已复制')));
              }
            },
          ),
        ],
      ),
    ),
  );

  Widget _notificationCard() => ListenableBuilder(
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
              TextButton(onPressed: openAppSettings, child: const Text('系统设置')),
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
  );

  Widget _handoverCard() {
    final session = _session!;
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '值班交接',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
              child: Text('暂无交接记录', style: TextStyle(color: WearColors.muted)),
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
                          _confirming == idOf(row['id']) ? '正在确认…' : '确认接班',
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _MineHelmetPainter extends CustomPainter {
  const _MineHelmetPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 28);
    final green = Paint()..color = const Color(0xFF00BD75);
    canvas.drawPath(
      Path()
        ..moveTo(4, 21)
        ..lineTo(4, 15)
        ..quadraticBezierTo(4, 6, 14, 5)
        ..quadraticBezierTo(24, 6, 24, 15)
        ..lineTo(24, 21)
        ..close(),
      green,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 3, 4, 18),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF00A765),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 20, 26, 5),
        const Radius.circular(2.5),
      ),
      green,
    );
    canvas.drawLine(
      const Offset(5, 23),
      const Offset(23, 23),
      Paint()
        ..color = const Color(0xFF00965D)
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MineHelmetPainter oldDelegate) => false;
}
