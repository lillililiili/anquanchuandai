import 'package:flutter/material.dart';
import '../../api/hat.dart';
import '../../models/hat.dart';
import '../../store/user_store.dart';
import '../../components/field_brand.dart';

/// 个人设备区分加载、失败、未绑定和已绑定，避免空卡冒充业务数据。
class MySafetyHatPage extends StatefulWidget {
  const MySafetyHatPage({super.key, this.loadHat});
  final Future<Hat?> Function()? loadHat;
  @override
  State<MySafetyHatPage> createState() => _MySafetyHatPageState();
}

class _MySafetyHatPageState extends State<MySafetyHatPage> {
  Hat? _hat;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = UserStore.instance.userInfo?.userId;
      if (widget.loadHat == null && userId == null) {
        throw StateError('用户资料暂不可用');
      }
      final hat = widget.loadHat != null
          ? await widget.loadHat!()
          : await HatApi.getHatByUserId(userId.toString());
      if (!mounted) return;
      setState(() => _hat = hat);
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法读取绑定信息，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _value(String? value) =>
      value == null || value.trim().isEmpty ? '未提供' : value;
  String _percent(num? value) =>
      value == null ? '未提供' : value.toInt().toString() + '%';
  String get _status => switch (_hat?.status) {
    '1' || 'online' => '在线',
    '0' || 'offline' => '离线',
    _ => '未知',
  };
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的安全帽'),
        actions: [
          IconButton(
            tooltip: '刷新绑定信息',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null || _hat == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      if (_error == null)
                        const FieldSceneAccent(scene: 'helmet-card', size: 112)
                      else
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _error != null
                                ? Icons.cloud_off_outlined
                                : Icons.construction_outlined,
                            size: 40,
                            color: scheme.onSurface,
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        _error != null ? '绑定信息加载失败' : '暂未绑定安全帽',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _error ?? '当前账号没有绑定设备。请联系管理员完成绑定后，再查看设备状态。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(_error != null ? '重新加载' : '刷新绑定信息'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const FieldSceneAccent(scene: 'helmet-card', size: 56),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _value(_hat!.hatNumber),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '已绑定 · $_status',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _section('设备状态', [
                _row('剩余电量', _percent(_hat!.electricityUsage)),
                _row('存储空间', _percent(_hat!.storageUsage)),
                _row('设备状态', _status),
                _row('使用时长', '后台未提供'),
              ]),
              const SizedBox(height: 16),
              _section('设备与人员', [
                _row('设备编号', _value(_hat!.hatNumber)),
                _row('绑定人员', _value(_hat!.bindUserName)),
                _row('作业组', _value(_hat!.bindGroup)),
                _row('绑定时间', _value(_hat!.bindTime)),
              ]),
              const SizedBox(height: 16),
              _section('当前绑定信息', [
                Text(
                  _hat!.bindTime == null
                      ? '后台未提供绑定时间'
                      : _value(_hat!.bindTime) +
                            '\n安全帽 ' +
                            _value(_hat!.hatNumber) +
                            ' 绑定到 ' +
                            _value(_hat!.bindUserName),
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}
