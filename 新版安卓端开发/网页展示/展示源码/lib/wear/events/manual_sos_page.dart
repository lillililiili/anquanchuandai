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
  String? _error;

  @override
  void dispose() {
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
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
          data: {
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
      if (mounted && session.scopeKey == scope) {
        setState(() => _error = '提交未确认：$error。填写内容已保留，可重试。');
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
              const Text(
                '填写现场情况，提交后直接进入管理员审批。仅你和管理员可查看。',
                style: TextStyle(color: WearColors.muted),
              ),
              const SizedBox(height: 16),
              WearCard(
                child: Column(
                  children: [
                    TextFormField(
                      key: const ValueKey('manual-sos-location'),
                      controller: _location,
                      enabled: !_submitting,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: '报警位置',
                        hintText: '例如：锅炉12米平台',
                      ),
                      validator: (value) =>
                          (value?.trim().isEmpty ?? true) ? '请填写报警位置' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('manual-sos-description'),
                      controller: _description,
                      enabled: !_submitting,
                      minLines: 4,
                      maxLines: 7,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: '报警说明',
                        hintText: '请描述现场情况和需要的帮助',
                      ),
                      validator: (value) =>
                          (value?.trim().isEmpty ?? true) ? '请填写报警说明' : null,
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
