import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core.dart';

class WearDutyPage extends StatefulWidget {
  const WearDutyPage({super.key, this.settings = false});
  final bool settings;
  @override
  State<WearDutyPage> createState() => _WearDutyPageState();
}

class _WearDutyPageState extends State<WearDutyPage> {
  static const _blue = Color(0xFF0095FF);
  WearSession? _session;
  String? _scope, _error, _confirming;
  List<JsonMap> _handovers = [];
  bool _loading = true, _handoverBusy = false, _confirmedTab = false;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session) || _scope != session.scopeKey) {
      _session?.refreshTick.removeListener(_refresh);
      _session = session;
      _scope = session.scopeKey;
      _handovers = [];
      session.refreshTick.addListener(_refresh);
      _load();
    }
  }

  void _refresh() => unawaited(_load());
  Future<void> _load() async {
    final session = _session!;
    final scope = session.scopeKey;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = jsonList(await session.api.get('/api/v1/duty/handovers'));
      if (!mounted || request != _request || scope != session.scopeKey) return;
      setState(
        () => _handovers = rows
            .where(
              (row) =>
                  idOf(row['siteId']).isEmpty ||
                  idOf(row['siteId']) == session.siteId,
            )
            .toList(),
      );
    } catch (e) {
      if (!mounted || request != _request || scope != session.scopeKey) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request && scope == session.scopeKey) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _request++;
    _session?.refreshTick.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WearColors.background,
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: ValueKey(
            widget.settings ? 'settings-scroll' : 'handover-scroll',
          ),
          padding: const EdgeInsets.only(bottom: 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.settings
                    ? _settingsContent()
                    : _handoverContent(),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _header() => Column(
    children: [
      Row(
        children: [
          IconButton(
            tooltip: widget.settings ? '返回我的' : '返回上页',
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/me'),
            icon: const Icon(Icons.arrow_back_ios_new, size: 22),
          ),
          const WearRollingWordmark(height: 22),
        ],
      ),
      SizedBox(
        height: WearHeaderLayout.height(context),
        child: Stack(
          fit: StackFit.expand,
          children: [
            WearAssetImage(
              widget.settings
                  ? 'assets/field-brand/preview/mine_reference_hero.png'
                  : 'assets/field-brand/preview/work_reference_header.png',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                widget.settings ? 130 : 16,
                16,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '我的 / 设置',
                      style: TextStyle(fontSize: 10, color: WearColors.brand),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.settings ? '设置' : '值班交接',
                      style: const TextStyle(
                        fontSize: WearHeaderLayout.titleSize,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: WearColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.settings ? '工作环境与值班信息' : '待办清楚，交接有据',
                      style: const TextStyle(
                        fontSize: WearHeaderLayout.subtitleSize,
                        height: 1.35,
                        color: WearColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _notice(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFEDF7FF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFD5E9FD)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.verified_user_outlined,
          size: 22,
          color: Color(0xFF5988B5),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Color(0xFF5988B5),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _icon(IconData icon, Color color) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 23, color: color),
  );

  List<Widget> _settingsContent() {
    final session = _session!;
    final pending = _handovers.where((r) => r['status'] == 'pending').toList();
    final row = pending.firstOrNull ?? _handovers.firstOrNull;
    return [
      WearCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          key: const ValueKey('settings-switch-site'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          leading: _icon(Icons.business_outlined, _blue),
          title: const Text(
            '切换厂站',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '当前：${session.siteName}',
            style: const TextStyle(fontSize: 12, color: WearColors.muted),
          ),
          trailing: const Icon(Icons.chevron_right, color: WearColors.muted),
          enabled: !session.callActive.value,
          onTap: session.callActive.value ? null : () => context.push('/sites'),
        ),
      ),
      const SizedBox(height: 12),
      WearCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _icon(Icons.description_outlined, const Color(0xFF9564EF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '值班交接',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: WearColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _loading
                            ? '正在加载…'
                            : _error != null
                            ? '暂未获取交接信息'
                            : '最近记录中 ${pending.length} 条待确认',
                        style: const TextStyle(
                          fontSize: 12,
                          color: WearColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_loading && _error == null && row != null) _badge(row),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFE5EDF7)),
            if (_error != null)
              WearEmpty(title: '交接加载失败', detail: _error, onRetry: _load)
            else if (row != null) ...[
              _meta('交班人', textOf(row['fromUserName'])),
              _meta('接班人', textOf(row['toUserName'])),
              _meta('交接时间', formatTime(row['createTime'])),
            ] else if (!_loading)
              const Text(
                '暂无交接记录',
                style: TextStyle(fontSize: 12, color: WearColors.muted),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await context.push('/handovers');
                if (mounted) await _load();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: Color(0xFF9FD0FF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('查看交接记录'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _notice('通话进行中时，请先结束通话再切换厂站。'),
      const SizedBox(height: 18),
      const Text(
        '智能穿戴管理平台 1.3.0',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: WearColors.muted),
      ),
    ];
  }

  List<Widget> _handoverContent() {
    final rows = _handovers
        .where((r) => r['status'] == (_confirmedTab ? 'confirmed' : 'pending'))
        .toList();
    return [
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFE5F0FC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            for (final confirmed in [false, true])
              Expanded(
                child: TextButton(
                  key: ValueKey(
                    confirmed ? 'handover-confirmed' : 'handover-pending',
                  ),
                  onPressed: () => setState(() => _confirmedTab = confirmed),
                  style: TextButton.styleFrom(
                    backgroundColor: _confirmedTab == confirmed
                        ? Colors.white
                        : Colors.transparent,
                    foregroundColor: _confirmedTab == confirmed
                        ? _blue
                        : WearColors.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(confirmed ? '已接班' : '待接班'),
                ),
              ),
          ],
        ),
      ),
      if (_session!.isDuty)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _handoverBusy ? null : _startHandover,
            icon: const Icon(Icons.add, size: 18),
            label: Text(_handoverBusy ? '正在提交…' : '发起交接'),
          ),
        ),
      const SizedBox(height: 12),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null)
        WearEmpty(title: '交接加载失败', detail: _error, onRetry: _load)
      else if (!_loading && rows.isEmpty)
        WearCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              _confirmedTab ? '暂无已接班记录' : '暂无待接班记录',
              textAlign: TextAlign.center,
              style: const TextStyle(color: WearColors.muted),
            ),
          ),
        ),
      if (_error == null)
        for (final row in rows) ...[
          _handoverCard(row),
          const SizedBox(height: 12),
        ],
      const SizedBox(height: 8),
      _notice('确认接班前，请阅读交接事项；仅当班接收人可确认。'),
      const SizedBox(height: 10),
      const Text(
        '显示当前厂站最近 20 条交接记录',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: WearColors.muted),
      ),
    ];
  }

  Widget _meta(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(fontSize: 12, color: WearColors.muted),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: WearColors.ink),
          ),
        ),
      ],
    ),
  );

  Widget _badge(JsonMap row) {
    final confirmed = row['status'] == 'confirmed';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: confirmed ? const Color(0xFFE5F8F2) : const Color(0xFFFFF4DF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          confirmed
              ? '已接班'
              : row['status'] == 'pending'
              ? '待接班'
              : '状态未知',
          style: TextStyle(
            fontSize: 11,
            color: confirmed ? const Color(0xFF00A88A) : WearColors.warning,
          ),
        ),
      ),
    );
  }

  Widget _handoverCard(JsonMap row) {
    JsonMap? payload;
    try {
      payload = jsonMap(jsonDecode(textOf(row['payloadJson'], '{}')));
    } catch (_) {
      /* Missing snapshot is not a zero count. */
    }
    final confirmed = row['status'] == 'confirmed';
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _badge(row),
          const SizedBox(height: 10),
          Text(
            '${textOf(row['fromUserName'])} → ${textOf(row['toUserName'])}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: WearColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          _meta('交接时间', formatTime(row['createTime'])),
          if (confirmed) _meta('确认时间', formatTime(row['confirmedAt'])),
          _meta(
            '交接事件',
            payload?['eventIds'] is List
                ? '${(payload!['eventIds'] as List).length} 条'
                : '未提供',
          ),
          _meta(
            '关联作业',
            payload?['taskIds'] is List
                ? '${(payload!['taskIds'] as List).length} 项'
                : '未提供',
          ),
          const SizedBox(height: 10),
          _notice(
            textOf(row['comment'], '').isEmpty
                ? '未填写交接备注，请结合相关事件与作业核查。'
                : textOf(row['comment']),
          ),
          if (!confirmed) ...[
            const SizedBox(height: 12),
            if (idOf(row['toUserId']) == _session!.userId && _session!.isDuty)
              FilledButton(
                key: ValueKey('handover-confirm-${idOf(row['id'])}'),
                onPressed: _confirming != null ? null : () => _confirm(row),
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(_confirming == idOf(row['id']) ? '正在确认…' : '确认接班'),
              )
            else
              const Text(
                '等待指定接班人确认',
                style: TextStyle(fontSize: 12, color: WearColors.muted),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(JsonMap handover) async {
    final session = _session!;
    final scope = session.scopeKey;
    if (_confirming != null ||
        !session.isDuty ||
        handover['status'] != 'pending' ||
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
      if (mounted && e is! StaleSessionException) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _confirming = null);
      }
    }
  }

  Future<void> _startHandover() async {
    final session = _session;
    if (session == null || !session.isDuty || _handoverBusy) return;
    final scope = session.scopeKey;
    FocusScope.of(context).unfocus();
    setState(() => _handoverBusy = true);
    List<JsonMap> operators = const [];
    try {
      operators = jsonList(
        await session.api.get('/api/v1/duty/operators'),
      ).where((item) => idOf(item['userId']) != session.userId).toList();
    } catch (error) {
      if (error is StaleSessionException || !mounted) return;
      final message = error is WearApiException ? error.message : '交接未提交，请稍后重试';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    } finally {
      if (mounted) setState(() => _handoverBusy = false);
    }
    if (!mounted || session != _session || scope != session.scopeKey) return;
    setState(() => _handoverBusy = true);
    TextEditingController? comment;
    try {
      if (operators.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前厂站没有可接班的其他值班人员')));
        return;
      }

      final formKey = GlobalKey<FormState>();
      comment = TextEditingController();
      String? toUserId;
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '发起值班交接',
                    style: TextStyle(
                      color: WearColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '当前负责的事件与任务将由服务端自动生成交接快照。',
                    style: TextStyle(color: WearColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: toUserId,
                    decoration: const InputDecoration(labelText: '接班人'),
                    items: operators
                        .map(
                          (item) => DropdownMenuItem(
                            value: idOf(item['userId']),
                            child: Text(
                              textOf(item['nickName']).isNotEmpty
                                  ? textOf(item['nickName'])
                                  : textOf(item['userName'], '未命名值班员'),
                            ),
                          ),
                        )
                        .toList(),
                    validator: (value) => value == null ? '请选择接班人' : null,
                    onChanged: (value) => toUserId = value,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: comment,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: '交接备注（选填）',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      if (formKey.currentState?.validate() != true) return;
                      Navigator.pop(sheetContext, true);
                    },
                    child: const Text('提交交接'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final note = comment.text.trim();
      if (confirmed != true ||
          toUserId == null ||
          !mounted ||
          scope != session.scopeKey) {
        return;
      }
      await session.api.post(
        '/api/v1/duty/handovers',
        data: {'toUserId': toUserId, if (note.isNotEmpty) 'comment': note},
      );
      if (!mounted || session != _session || scope != session.scopeKey) return;
      session.requestRefresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('交接已发起，等待接班人确认')));
    } catch (error) {
      if (error is StaleSessionException || !mounted) return;
      final message = error is WearApiException ? error.message : '交接未提交，请稍后重试';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      if (error is WearApiException && error.code == 409) {
        session.requestRefresh();
      }
    } finally {
      final toDispose = comment;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toDispose?.dispose();
      });
      if (mounted && _handoverBusy) {
        setState(() => _handoverBusy = false);
      }
    }
  }
}
