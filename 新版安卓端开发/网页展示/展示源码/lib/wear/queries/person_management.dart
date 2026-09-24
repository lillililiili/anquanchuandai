import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core.dart';
import 'query_widgets.dart';
import 'query_utils.dart';
import 'management_widgets.dart';

class PersonEditorPage extends StatefulWidget {
  const PersonEditorPage({super.key, this.id});
  final String? id;
  @override
  State<PersonEditorPage> createState() => _PersonEditorPageState();
}

class _PersonEditorPageState extends State<PersonEditorPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _code = TextEditingController();
  WearSession? _session;
  JsonMap _original = {};
  List<JsonMap> _teams = [], _contractors = [];
  String? _team, _contractor, _from, _to;
  Set<String> _sites = {};
  bool _loading = true, _busy = false;
  Object? _error;
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
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = _session!.api;
      final results = await Future.wait([
        api.get('/api/v1/teams', query: {'status': 'all'}),
        api.get('/api/v1/contractors', query: {'status': 'all'}),
        if (widget.id != null) api.get('/api/v1/people/${widget.id}'),
      ]);
      if (!mounted) return;
      _teams = jsonList(results[0]);
      _contractors = jsonList(results[1]);
      _original = widget.id == null ? {} : jsonMap(results[2]);
      _name.text = _original['name']?.toString() ?? '';
      _code.text = _original['personCode']?.toString() ?? '';
      _team = _original['teamId']?.toString();
      _contractor = _original['contractorId']?.toString();
      _from = _original['validFrom']?.toString();
      _to = _original['validTo']?.toString();
      _sites = (_original['siteIds'] as List? ?? [_session!.siteId])
          .map(idOf)
          .toSet();
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_sites.isEmpty ||
        (_from != null && _to != null && _from!.compareTo(_to!) > 0)) {
      managementMessage(context, '请选择授权厂站，并确保结束日期不早于开始日期');
      return;
    }
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        'personCode': _code.text.trim(),
        'teamId': _team,
        'contractorId': _contractor,
        'validFrom': _from,
        'validTo': _to,
        'siteIds': _sites.toList(),
        'orgDeptId': _original['orgDeptId'],
        'accountUserId': _original['accountUserId'],
        'version': _original['version'],
      };
      if (widget.id == null) {
        await _session!.api.post('/api/v1/people', data: body);
      } else {
        await _session!.api.put('/api/v1/people/${widget.id}', data: body);
      }
      if (mounted) {
        managementMessage(context, '人员档案已保存');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) managementMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _options(
    String label,
    List<JsonMap> records,
    String? value,
    ValueChanged<String?> changed,
  ) {
    final options = records
        .where((r) => r['status'] == '0' || idOf(r['id']) == value)
        .toList();
    return DropdownButtonFormField<String>(
      initialValue: options.any((r) => idOf(r['id']) == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('未指定')),
        for (final row in options)
          DropdownMenuItem(
            value: idOf(row['id']),
            child: Text(textOf(row['name'])),
          ),
      ],
      onChanged: (v) => changed(v == '' ? null : v),
    );
  }

  @override
  Widget build(BuildContext context) => QueryPage(
    title: widget.id == null ? '新增人员' : '编辑人员',
    body: QueryStateView(
      loading: _loading,
      error: _error,
      empty: false,
      onRetry: _load,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ManagementSection(
              title: '基本信息',
              children: [
                ManagementField(controller: _name, label: '姓名', required: true),
                ManagementField(
                  controller: _code,
                  label: '人员编号',
                  required: true,
                ),
                _options('班组', _teams, _team, (v) => setState(() => _team = v)),
                _options(
                  '承包商',
                  _contractors,
                  _contractor,
                  (v) => setState(() => _contractor = v),
                ),
              ],
            ),
            ManagementSection(
              title: '有效期与厂站',
              children: [
                ManagementDate(
                  label: '开始',
                  value: _from,
                  onChanged: (v) => setState(() => _from = v),
                ),
                ManagementDate(
                  label: '结束',
                  value: _to,
                  onChanged: (v) => setState(() => _to = v),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final site in _session!.sites)
                      FilterChip(
                        label: Text(textOf(site['name'])),
                        selected: _sites.contains(idOf(site['id'])),
                        onSelected: (v) => setState(() {
                          v
                              ? _sites.add(idOf(site['id']))
                              : _sites.remove(idOf(site['id']));
                        }),
                      ),
                  ],
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_busy ? '保存中…' : '保存档案'),
            ),
          ],
        ),
      ),
    ),
  );
}

class OrganizationsPage extends StatefulWidget {
  const OrganizationsPage({super.key});
  @override
  State<OrganizationsPage> createState() => _OrganizationsPageState();
}

class _OrganizationsPageState extends State<OrganizationsPage> {
  WearSession? _session;
  List<JsonMap> _rows = [];
  String _kind = 'teams';
  bool _loading = true, _busy = false;
  Object? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      _session = WearScope.of(context);
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = jsonList(
        await _session!.api.get('/api/v1/$_kind', query: {'status': 'all'}),
      );
      if (mounted) {
        setState(() {
          _rows = rows;
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

  Future<void> _edit([JsonMap? row]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _OrganizationNameDialog(
        name: row?['name']?.toString() ?? '',
        title: '${row == null ? '新增' : '编辑'}${_kind == 'teams' ? '班组' : '承包商'}',
      ),
    );
    if (name == null || !mounted) return;
    await _write(
      () => row == null
          ? _session!.api.post(
              '/api/v1/$_kind',
              data: {
                'name': name,
                if (_kind == 'teams') 'siteId': _session!.siteId,
              },
            )
          : _session!.api.put(
              '/api/v1/$_kind/${row['id']}',
              data: {'name': name},
            ),
    );
  }

  Future<void> _write(Future<dynamic> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        managementMessage(context, '已保存');
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
    title: '班组与承包商',
    actions: [
      IconButton(
        tooltip: '新增',
        onPressed: _busy ? null : _edit,
        icon: const Icon(Icons.add),
      ),
    ],
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'teams', label: Text('班组')),
              ButtonSegment(value: 'contractors', label: Text('承包商')),
            ],
            selected: {_kind},
            onSelectionChanged: _busy || _loading
                ? null
                : (v) {
                    setState(() => _kind = v.first);
                    _load();
                  },
          ),
        ),
        Expanded(
          child: QueryStateView(
            loading: _loading,
            error: _error,
            onRetry: _load,
            empty: _rows.isEmpty,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final row in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: WearCard(
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(textOf(row['name'])),
                            subtitle: Text(row['status'] == '0' ? '启用' : '停用'),
                            trailing: IconButton(
                              tooltip: '编辑名称',
                              onPressed: _busy ? null : () => _edit(row),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final active = row['status'] == '0';
                                      if (await confirmManagement(
                                        context,
                                        active ? '停用此记录？' : '启用此记录？',
                                        textOf(row['name']),
                                      )) {
                                        await _write(
                                          () => _session!.api.put(
                                            '/api/v1/$_kind/${row['id']}',
                                            data: {
                                              'status': active ? '1' : '0',
                                            },
                                          ),
                                        );
                                      }
                                    },
                              child: Text(row['status'] == '0' ? '停用' : '启用'),
                            ),
                          ),
                        ],
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

class _OrganizationNameDialog extends StatefulWidget {
  const _OrganizationNameDialog({required this.name, required this.title});
  final String name, title;
  @override
  State<_OrganizationNameDialog> createState() =>
      _OrganizationNameDialogState();
}

class _OrganizationNameDialogState extends State<_OrganizationNameDialog> {
  late final _name = TextEditingController(text: widget.name);
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: '名称'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isNotEmpty) {
            Navigator.pop(context, _name.text.trim());
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

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

class PersonTransferPage extends StatefulWidget {
  const PersonTransferPage({super.key});
  @override
  State<PersonTransferPage> createState() => _PersonTransferPageState();
}

class _PersonTransferPageState extends State<PersonTransferPage> {
  static const _documents = MethodChannel('rolling/documents');
  bool _busy = false, _update = false;
  JsonMap? _result;
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        managementMessage(
          context,
          e is MissingPluginException ? '请在安卓端使用系统文件选择器' : e,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(bool template) async {
    final api = WearScope.of(context).api;
    final bytes = await api.request(
      template ? 'GET' : 'POST',
      template ? '/api/v1/people/import-template' : '/api/v1/people/export',
      data: template ? null : {},
      binary: true,
    );
    final saved = await _documents.invokeMethod<bool>('saveXlsx', {
      'name': template ? '人员导入模板.xlsx' : '人员档案.xlsx',
      'bytes': Uint8List.fromList((bytes as List).cast<int>()),
    });
    if (mounted && saved == true) managementMessage(context, '文件已保存');
  }

  Future<void> _import() async {
    final api = WearScope.of(context).api;
    final scope = WearScope.of(context).scopeKey;
    final file = await _documents.invokeMapMethod<String, dynamic>('openXlsx');
    if (file == null || !mounted) return;
    if (WearScope.of(context).scopeKey != scope) {
      throw const StaleSessionException();
    }
    final name = file['name']?.toString() ?? '';
    if (!name.toLowerCase().endsWith('.xlsx')) {
      throw const FormatException('请选择 .xlsx 文件');
    }
    if (!await confirmManagement(
      context,
      '导入人员档案',
      '$name\n${_update ? '相同人员编号将更新已有档案。' : '仅新增人员，不覆盖已有档案。'}',
    )) {
      return;
    }
    final result = jsonMap(
      await api.post(
        '/api/v1/people/import',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            (file['bytes'] as List).cast<int>(),
            filename: name,
          ),
          'updateExisting': _update,
        }),
      ),
    );
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) => QueryPage(
    title: '导入与导出',
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ManagementSection(
          title: 'Excel 导入',
          children: [
            const Text(
              '请按模板填写人员档案。支持 .xlsx，最多 5000 行、10 MB；校验失败会显示具体行号。',
              style: TextStyle(color: WearColors.muted),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(() => _download(true)),
              icon: const Icon(Icons.download_outlined),
              label: const Text('下载导入模板'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _update,
              onChanged: _busy ? null : (v) => setState(() => _update = v!),
              title: const Text('更新已存在的人员编号'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(_import),
              icon: const Icon(Icons.upload_file),
              label: const Text('选择文件并导入'),
            ),
            if (_result != null) ...[
              Text(
                '新增 ${intOf(_result!['created'])} · 更新 ${intOf(_result!['updated'])} · 跳过 ${intOf(_result!['skipped'])}',
              ),
              for (final error in jsonList(_result!['errors']))
                Text(
                  '第 ${error['row']} 行 · ${error['field']}：${error['reason']}',
                  style: const TextStyle(color: WearColors.warning),
                ),
            ],
          ],
        ),
        ManagementSection(
          title: '导出人员档案',
          children: [
            const Text(
              '导出当前厂站权限范围内的人员档案，选择保存位置后可分享文件。',
              style: TextStyle(color: WearColors.muted),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(() => _download(false)),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导出 Excel'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    ),
  );
}
