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
  List<JsonMap> _shifts = [];
  JsonMap? _currentDuty;
  String _tab = 'pending';
  int _shiftPage = 1, _shiftTotal = 0;
  bool _moreShifts = false;
  bool _loading = true, _handoverBusy = false;
  DateTime _ledgerLoadedAt = DateTime.now();
  Timer? _clock;
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
      _shifts = [];
      _currentDuty = null;
      session.refreshTick.addListener(_refresh);
      _clock ??= Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && _currentDuty != null) setState(() {});
      });
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
      final ledger = widget.settings
          ? <String, dynamic>{}
          : jsonMap(await session.api.get('/api/v1/duty/shifts'));
      if (!mounted || request != _request || scope != session.scopeKey) return;
      setState(() {
        _shiftPage = 1;
        _shifts = jsonList(ledger['records']);
        _shiftTotal = int.tryParse('${ledger['total']}') ?? 0;
        _currentDuty = ledger['currentDuty'] is Map
            ? jsonMap(ledger['currentDuty'])
            : null;
        _ledgerLoadedAt = DateTime.now();
        _handovers = rows
            .where(
              (row) =>
                  idOf(row['siteId']).isEmpty ||
                  idOf(row['siteId']) == session.siteId,
            )
            .toList();
      });
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
    _clock?.cancel();
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
    final rows = _handovers.where((r) => r['status'] == _tab).toList();
    return [
      _currentDutyCard(),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFE5F0FC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            for (final tab in const {
              'pending': '待接班',
              'confirmed': '已接班',
              'cancelled': '已取消',
              'shifts': '值班明细',
            }.entries)
              Expanded(
                child: TextButton(
                  key: ValueKey('handover-${tab.key}'),
                  onPressed: () => setState(() => _tab = tab.key),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    backgroundColor: _tab == tab.key
                        ? Colors.white
                        : Colors.transparent,
                    foregroundColor: _tab == tab.key ? _blue : WearColors.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(tab.value, style: const TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
      if (!_loading &&
          _error == null &&
          _session!.canHandover &&
          (_currentDuty == null ||
              idOf(_currentDuty!['userId']) == _session!.userId))
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
      else if (!_loading && (_tab == 'shifts' ? _shifts.isEmpty : rows.isEmpty))
        WearCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              _tab == 'shifts'
                  ? '暂无值班明细，完成接班后开始记录'
                  : '暂无${const {'pending': '待接班', 'confirmed': '已接班', 'cancelled': '已取消'}[_tab]}记录',
              textAlign: TextAlign.center,
              style: const TextStyle(color: WearColors.muted),
            ),
          ),
        ),
      if (_error == null && _tab != 'shifts')
        for (final row in rows) ...[
          _handoverCard(row),
          const SizedBox(height: 12),
        ],
      if (_error == null && _tab == 'shifts') ...[
        for (final shift in _shifts) ...[
          _shiftCard(shift),
          const SizedBox(height: 12),
        ],
        if (_shifts.length < _shiftTotal)
          TextButton(
            onPressed: _moreShifts ? null : _loadMoreShifts,
            child: Text(_moreShifts ? '加载中…' : '加载更多值班明细'),
          ),
      ],
      const SizedBox(height: 8),
      _notice(
        _tab == 'shifts'
            ? '接班确认或管理员接管时记录起止时间；历史推算记录已单独标明。'
            : '取消仅对待接班生效；已完成的交接保留记录。',
      ),
      const SizedBox(height: 10),
      Text(
        _tab == 'shifts' ? '当前厂站值班明细 · 共 $_shiftTotal 条' : '显示当前厂站最近 20 条交接记录',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: WearColors.muted),
      ),
    ];
  }

  String _duration(JsonMap row) {
    if (row['endUnknown'] == true) return '无法计算';
    var seconds = int.tryParse('${row['durationSeconds']}') ?? 0;
    if (row['endedAt'] == null) {
      seconds += DateTime.now().difference(_ledgerLoadedAt).inSeconds;
    }
    final minutes = seconds < 0 ? 0 : seconds ~/ 60;
    if (minutes == 0) return '不足 1 分钟';
    if (minutes < 60) return '$minutes 分钟';
    return '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
  }

  Widget _currentDutyCard() => WearCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.schedule, size: 20, color: _blue),
            SizedBox(width: 8),
            Text(
              '当前值班',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading && _currentDuty == null)
          const Text('正在读取值班信息…')
        else if (_error != null)
          const Text('值班信息暂不可用，请重试', style: TextStyle(color: WearColors.muted))
        else if (_currentDuty == null)
          const Text('尚无已确认的值班记录', style: TextStyle(color: WearColors.muted))
        else ...[
          Text(
            textOf(_currentDuty!['userName']),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          _meta('开始时间', formatTime(_currentDuty!['startedAt'])),
          _meta('已值班', _duration(_currentDuty!)),
          if (_currentDuty!['changeType'] == 'legacy_confirmation')
            const Text(
              '开始时间依据历史接班确认记录',
              style: TextStyle(fontSize: 11, color: WearColors.muted),
            ),
        ],
        if (_session!.isDutyAdmin &&
            !_loading &&
            _error == null &&
            idOf(_currentDuty?['userId']) != _session!.userId) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('duty-takeover'),
            onPressed: _handoverBusy ? null : _takeover,
            icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
            label: const Text('管理员接管为自己'),
          ),
        ],
      ],
    ),
  );

  Widget _shiftCard(JsonMap row) => WearCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                textOf(row['userName']),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              row['endUnknown'] == true
                  ? '历史记录'
                  : row['endedAt'] == null
                  ? '值班中'
                  : '已结束',
              style: const TextStyle(fontSize: 12, color: _blue),
            ),
          ],
        ),
        _meta('开始时间', formatTime(row['startedAt'])),
        _meta(
          '结束时间',
          row['endUnknown'] == true
              ? '未记录'
              : row['endedAt'] == null
              ? '至今'
              : formatTime(row['endedAt']),
        ),
        _meta('值班时长', _duration(row)),
        _meta(
          '接班方式',
          row['changeType'] == 'takeover'
              ? '管理员接管'
              : '${row['changeType']}'.startsWith('legacy_')
              ? '历史确认记录推算'
              : '确认接班',
        ),
        if (textOf(row['reason']).isNotEmpty) _notice(textOf(row['reason'])),
      ],
    ),
  );

  Future<void> _loadMoreShifts() async {
    final session = _session!, scope = session.scopeKey, request = _request;
    setState(() => _moreShifts = true);
    try {
      final data = jsonMap(
        await session.api.get(
          '/api/v1/duty/shifts',
          query: {'current': _shiftPage + 1, 'size': 20},
        ),
      );
      if (!mounted || scope != session.scopeKey || request != _request) return;
      setState(() {
        _shiftPage++;
        _shifts.addAll(jsonList(data['records']));
      });
    } catch (e) {
      if (mounted && scope == session.scopeKey && e is! StaleSessionException) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _moreShifts = false);
    }
  }

  Future<String?> _operationReason(String title, String explanation) async {
    String reason = '';
    final form = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(explanation),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('duty-operation-reason'),
                  maxLength: 200,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '操作原因'),
                  onChanged: (v) => reason = v.trim(),
                  validator: (_) => reason.isEmpty ? '请填写操作原因' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, reason);
            },
            child: Text(title),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelHandover(JsonMap row) async {
    await _runOperation(
      '取消交接',
      '取消后当前值班人和责任保持不变，记录仍会保留。',
      '/api/v1/duty/handovers/${idOf(row['id'])}/cancel',
      {},
    );
  }

  Future<void> _takeover() async {
    await _runOperation(
      '确认接管',
      '将当前值班负责人转为您，同时接收其未完成的事件与作业。原待接班交接会自动取消，此操作会留痕。',
      '/api/v1/duty/takeover',
      {'expectedShiftId': _currentDuty?['id']},
    );
  }

  Future<void> _runOperation(
    String title,
    String explanation,
    String path,
    JsonMap data,
  ) async {
    if (_handoverBusy) return;
    final session = _session!, scope = session.scopeKey;
    setState(() => _handoverBusy = true);
    try {
      final reason = await _operationReason(title, explanation);
      if (reason == null || !mounted || scope != session.scopeKey) return;
      await session.api.post(path, data: {...data, 'reason': reason});
      if (!mounted || scope != session.scopeKey) return;
      session.requestRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(path.endsWith('/cancel') ? '交接已取消，记录已保留' : '已接管值班'),
        ),
      );
    } catch (e) {
      if (mounted && scope == session.scopeKey && e is! StaleSessionException) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
        if (e is WearApiException && e.code == 409) session.requestRefresh();
      }
    } finally {
      if (mounted) setState(() => _handoverBusy = false);
    }
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
              : row['status'] == 'cancelled'
              ? '已取消'
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
          if (row['audit'] is Map) ...[
            _meta('操作人', textOf(row['audit']['actorName'])),
            _meta(
              row['status'] == 'cancelled' ? '取消时间' : '接管时间',
              formatTime(row['audit']['actedAt']),
            ),
            _notice(textOf(row['audit']['reason'])),
          ],
          if (row['status'] == 'pending') ...[
            const SizedBox(height: 12),
            if (idOf(row['toUserId']) == _session!.userId &&
                _session!.canHandover)
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
            if (row['canCancel'] == true)
              OutlinedButton.icon(
                key: ValueKey('handover-cancel-${idOf(row['id'])}'),
                onPressed: _handoverBusy ? null : () => _cancelHandover(row),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('取消交接'),
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
        !session.canHandover ||
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
    if (session == null || !session.canHandover || _handoverBusy) return;
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
    String note = '';
    try {
      if (operators.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前厂站没有可接班的其他值班人员')));
        return;
      }

      final formKey = GlobalKey<FormState>();
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
                              item['userName'] == 'admin'
                                  ? '${textOf(item['nickName'], '管理员')}（admin）'
                                  : textOf(item['nickName']).isNotEmpty
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
                    onChanged: (value) => note = value.trim(),
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
      if (mounted && _handoverBusy) {
        setState(() => _handoverBusy = false);
      }
    }
  }
}
