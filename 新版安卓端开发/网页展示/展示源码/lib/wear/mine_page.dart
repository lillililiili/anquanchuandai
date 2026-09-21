import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core.dart';
import 'notifications.dart';
import 'package:flutter/services.dart';
import 'queries/my_equipment_page.dart';

class WearMinePage extends StatefulWidget {
  final WearNotifications notifications;
  const WearMinePage({super.key, required this.notifications});
  @override
  State<WearMinePage> createState() => _WearMinePageState();
}

class _WearMinePageState extends State<WearMinePage> {
  WearSession? _session;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = WearScope.of(context);
  }

  Future<void> _load() async {
    _session?.requestRefresh();
    if (mounted) setState(() {});
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
            animation: Listenable.merge([widget.notifications, _session!]),
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
                    key: const ValueKey('wear-page-hero-mine'),
                    height: WearHeaderLayout.height(context),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/field-brand/preview/mine_reference_hero.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 16,
                          child: const WearRollingWordmark(height: 25),
                        ),
                        Positioned(
                          top: 0,
                          right: 16,
                          width: 140 * unit,
                          child: Tooltip(
                            message: session.callActive.value
                                ? '通话中不能切换厂站'
                                : '切换厂站',
                            child: TextButton(
                              key: const ValueKey('mine-header-site'),
                              onPressed:
                                  session.busy || session.callActive.value
                                  ? null
                                  : () => context.go('/sites'),
                              style: TextButton.styleFrom(
                                foregroundColor: _muted,
                                minimumSize: const Size(48, 48),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 4 * unit,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Flexible(
                                    child: Text(
                                      session.siteName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  Icon(Icons.expand_more, size: 16 * unit),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          top: 32,
                          width: constraints.maxWidth * .46,
                          bottom: 12,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '你好，$name！',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: WearHeaderLayout.titleSize,
                                    height: 1.15,
                                    fontWeight: FontWeight.w800,
                                    color: WearColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '安全作业，平安每一天！',
                                  style: TextStyle(
                                    fontSize: WearHeaderLayout.subtitleSize,
                                    height: 1.35,
                                    color: WearColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 7 * unit,
                          top: 88,
                          child: Transform.rotate(
                            angle: -0.16,
                            child: Text(
                              '安全\n从我做起！',
                              textScaler: TextScaler.noScaling,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _blue,
                                fontSize: 11,
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
                                          '接警连接、通知权限与设备绑定',
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
                                      '查看状态',
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
                                () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const MyEquipmentPage(),
                                  ),
                                ),
                              ),
                              _menuRow(
                                Icons.settings,
                                const Color(0xFF9256F8),
                                '设置',
                                () => context.push('/settings'),
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
