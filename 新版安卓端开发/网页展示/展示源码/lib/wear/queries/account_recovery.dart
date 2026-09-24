import 'package:flutter/material.dart';
import '../core.dart';
import 'management_widgets.dart';
import 'query_widgets.dart';

class AccountRecoveryPage extends StatefulWidget {
  const AccountRecoveryPage({super.key});
  @override
  State<AccountRecoveryPage> createState() => _AccountRecoveryPageState();
}

class _AccountRecoveryPageState extends State<AccountRecoveryPage> {
  WearSession? _session;
  List<JsonMap> _rows = [];
  String _status = 'pending';
  bool _loading = true, _more = false;
  int _page = 1, _total = 0;
  Object? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      _session = WearScope.of(context);
      _load();
    }
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _session!.api.page(
        '/api/v1/account-recovery/requests',
        current: page,
        query: {'status': _status},
      );
      if (mounted) {
        setState(() {
          _rows = result.records;
          _page = page;
          _total = result.total;
          _more = result.hasMore;
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

  @override
  Widget build(BuildContext context) => QueryPage(
    title: '重置审批',
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('待审批')),
              ButtonSegment(value: 'approved', label: Text('已批准')),
              ButtonSegment(value: 'rejected', label: Text('已驳回')),
            ],
            selected: {_status},
            onSelectionChanged: _loading
                ? null
                : (v) {
                    setState(() => _status = v.first);
                    _load();
                  },
          ),
        ),
        Expanded(
          child: QueryStateView(
            loading: _loading,
            error: _error,
            empty: _rows.isEmpty,
            onRetry: _load,
            emptyTitle: '暂无此类申请',
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final row in _rows)
                  QueryRow(
                    title: textOf(row['realName']),
                    subtitle:
                        '${textOf(row['identifier'])} · ${textOf(row['createdAt'])}',
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _RecoveryReviewPage(request: row),
                        ),
                      );
                      if (mounted) _load(page: _page);
                    },
                  ),
              ],
            ),
          ),
        ),
        PagingFooter(
          current: _page,
          total: _total,
          hasMore: _more,
          busy: _loading,
          onPrevious: () => _load(page: _page - 1),
          onNext: () => _load(page: _page + 1),
        ),
      ],
    ),
  );
}

class _RecoveryReviewPage extends StatefulWidget {
  const _RecoveryReviewPage({required this.request});
  final JsonMap request;
  @override
  State<_RecoveryReviewPage> createState() => _RecoveryReviewPageState();
}

class _RecoveryReviewPageState extends State<_RecoveryReviewPage> {
  final _search = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController(),
      _reason = TextEditingController();
  List<JsonMap> _accounts = [];
  String? _selected;
  bool _busy = false, _verified = false;
  @override
  void initState() {
    super.initState();
    _search.text = widget.request['identifier']?.toString() ?? '';
  }

  @override
  void dispose() {
    for (final c in [_search, _password, _confirm, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _find() async {
    setState(() => _busy = true);
    try {
      final result = jsonList(
        await WearScope.of(context).api.get(
          '/api/v1/account-recovery/accounts',
          query: {'q': _search.text.trim()},
        ),
      );
      if (mounted) {
        setState(() {
          _accounts = result;
          _selected = null;
          _verified = false;
        });
      }
    } catch (e) {
      if (mounted) managementMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(bool approve) async {
    if (_reason.text.trim().isEmpty ||
        approve &&
            (!_verified ||
                _selected == null ||
                _password.text != _confirm.text ||
                !RegExp(
                  r'^(?=.*[A-Za-z])(?=.*\d).{8,20}$',
                ).hasMatch(_password.text))) {
      managementMessage(
        context,
        approve ? '请选择账号、核实身份，填写审批说明，并输入两次相同的 8–20 位字母数字密码' : '请填写驳回原因',
      );
      return;
    }
    if (!await confirmManagement(
      context,
      approve ? '批准并重置密码？' : '驳回申请？',
      approve ? '所选账号的旧登录将失效。请通过已核实的联系方式告知申请人账号和新密码。' : '此次申请将结束，原账号密码不变。',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await WearScope.of(context).api.post(
        '/api/v1/account-recovery/requests/${widget.request['id']}/${approve ? 'approve' : 'reject'}',
        data: {
          'reason': _reason.text.trim(),
          if (approve) 'targetUserId': _selected,
          if (approve) 'newPassword': _password.text,
        },
      );
      if (mounted) {
        managementMessage(context, approve ? '已批准，密码已重置' : '已驳回');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) managementMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.request;
    return QueryPage(
      title: '申请详情',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ManagementSection(
            title: '申请人信息',
            children: [
              DetailField(label: '姓名', value: textOf(row['realName'])),
              DetailField(label: '账号 / 编号', value: textOf(row['identifier'])),
              DetailField(label: '联系电话', value: textOf(row['contact'])),
              DetailField(label: '申请时间', value: textOf(row['createdAt'])),
              Text(textOf(row['reason'])),
            ],
          ),
          if (row['status'] == 'pending') ...[
            ManagementSection(
              title: '核实账号',
              children: [
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: '账号、姓名或人员编号',
                    suffixIcon: IconButton(
                      tooltip: '搜索账号',
                      onPressed: _busy ? null : _find,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => _find(),
                ),
                const Text(
                  '搜索后选择真实账号；重名时核对人员编号。最多显示 50 个结果，可细化搜索。',
                  style: TextStyle(fontSize: 12, color: WearColors.muted),
                ),
                for (final account in _accounts)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${textOf(account['nickName'])} · ${textOf(account['userName'])}',
                    ),
                    subtitle: Text(textOf(account['personCode'], '未关联人员档案')),
                    value: _selected == idOf(account['id']),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _selected = v! ? idOf(account['id']) : null;
                            _verified = false;
                          }),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('已线下核实申请人身份及账号归属'),
                  value: _verified,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _verified = v!),
                ),
              ],
            ),
            ManagementSection(
              title: '审批处理',
              children: [
                ManagementField(
                  controller: _password,
                  label: '新密码（8–20 位字母和数字）',
                  obscure: true,
                ),
                ManagementField(
                  controller: _confirm,
                  label: '再次输入新密码',
                  obscure: true,
                ),
                ManagementField(
                  controller: _reason,
                  label: '核实说明 / 驳回原因',
                  lines: 3,
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _review(true),
                  child: const Text('批准并重置密码'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _review(false),
                  child: const Text('驳回申请'),
                ),
              ],
            ),
          ] else
            ManagementSection(
              title: row['status'] == 'approved' ? '已批准' : '已驳回',
              children: [
                DetailField(label: '处理时间', value: textOf(row['reviewedAt'])),
                DetailField(label: '审批人 ID', value: textOf(row['reviewedBy'])),
                Text(textOf(row['reviewReason'])),
              ],
            ),
        ],
      ),
    );
  }
}
