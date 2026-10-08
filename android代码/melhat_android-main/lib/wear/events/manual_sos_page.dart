import 'dart:math';
import 'package:flutter/material.dart';
import '../core.dart';

class ManualSosPage extends StatefulWidget {
  const ManualSosPage({super.key});

  @override
  State<ManualSosPage> createState() => _ManualSosPageState();
}

class _ManualSosPageState extends State<ManualSosPage> {
  final _form = GlobalKey<FormState>();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _requestId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  bool _submitting = false;
  JsonMap? _pendingBody;
  String? _error;

  @override
  void dispose() {
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认发起 SOS 求助？'),
        content: Text(
          WearScope.of(context).api.isMock
              ? '当前为本地模拟，不会通知真实值守人员。位置和详细情况可在求助后补充。'
              : '将向当前厂站提交人员求助，值守人员可在共用平台查看处理。位置和详细情况可在求助后补充。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认求助'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final session = WearScope.of(context);
    final scope = session.scopeKey;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final event = jsonMap(
        await session.api.post(
          '/api/v1/events/manual-sos',
          data: _pendingBody ??= {
            'requestId': _requestId,
            'location': _location.text.trim(),
            'description': _description.text.trim(),
          },
        ),
      );
      if (!mounted || session.scopeKey != scope) return;
      final id = idOf(event['id']);
      if (id.isEmpty) throw const FormatException('未获取到报警记录，请重试确认');
      session.requestRefresh();
      Navigator.of(context).pop(id);
    } catch (error) {
      if (error is WearApiException &&
          error.code >= 400 &&
          error.code < 500 &&
          error.code != 409) {
        _pendingBody = null;
      }
      if (mounted && session.scopeKey == scope) {
        setState(() => _error = '提交未确认：$error。重试会确认原求助，详细情况可在创建成功后补充。');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      backgroundColor: WearColors.background,
      appBar: AppBar(title: const Text('手动 SOS 报警')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '确认即可提交求助，位置和详细情况可以后补。没有安全帽、定位或语音也可文字跟进。${WearScope.of(context).api.isMock ? '当前为本地模拟。' : ''}',
                style: const TextStyle(color: WearColors.muted),
              ),
              const SizedBox(height: 16),
              WearCard(
                child: Column(
                  children: [
                    TextFormField(
                      key: const ValueKey('manual-sos-location'),
                      controller: _location,
                      enabled: !_submitting && _pendingBody == null,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: '位置说明（选填）',
                        hintText: '例如：锅炉12米平台',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('manual-sos-description'),
                      controller: _description,
                      enabled: !_submitting && _pendingBody == null,
                      minLines: 4,
                      maxLines: 7,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: '求助说明（选填）',
                        hintText: '请描述现场情况和需要的帮助',
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFB42318)),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('manual-sos-submit'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD92D20),
                ),
                onPressed: _submitting ? null : _submit,
                icon: const Icon(Icons.sos),
                label: Text(_submitting ? '正在提交…' : '提交 SOS 报警'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
