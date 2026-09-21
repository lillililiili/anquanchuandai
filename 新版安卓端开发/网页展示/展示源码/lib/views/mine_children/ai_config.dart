import 'package:flutter/material.dart';
import '../../components/field_motion.dart';
import '../../store/ai_config_store.dart';
import '../../service/ai_agent.dart';

class AIConfigPage extends StatefulWidget {
  const AIConfigPage({super.key});
  @override
  State<AIConfigPage> createState() => _AIConfigPageState();
}

class _AIConfigPageState extends State<AIConfigPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _key, _url, _model;
  late String _saved;
  bool _saving = false, _visible = false, _allowPop = false, _leaving = false;
  String? _feedback;
  bool _failed = false;
  String get _snapshot => [_key.text, _url.text, _model.text].join('\u0000');
  bool get _dirty => _snapshot != _saved;
  @override
  void initState() {
    super.initState();
    final store = AIConfigStore.instance;
    _key = TextEditingController(text: store.apiKey);
    _url = TextEditingController(text: store.baseUrl);
    _model = TextEditingController(text: store.model);
    _saved = _snapshot;
    for (final c in [_key, _url, _model]) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_key, _url, _model]) {
      c.removeListener(_changed);
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _leave() async {
    if (_saving || _leaving) return;
    _leaving = true;
    var leave = !_dirty;
    if (!leave) {
      leave =
          await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: const Text('放弃未保存的修改？'),
              content: const Text('连接参数还没有保存。继续编辑可保留当前输入。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('继续编辑'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('放弃修改'),
                ),
              ],
            ),
          ) ??
          false;
    }
    _leaving = false;
    if (leave && mounted) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      await AIConfigStore.instance.saveConfig(
        apiKey: _key.text.trim(),
        baseUrl: _url.text.trim(),
        model: _model.text.trim(),
      );
      AIService.instance.reinit();
      if (!mounted) return;
      setState(() {
        _saved = _snapshot;
        _failed = false;
        _feedback = '配置已保存。服务是否可用以实际对话结果为准。';
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _failed = true;
          _feedback = '保存失败，输入已保留，请重试。';
        });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('清空 AI 配置？'),
        content: const Text('将清除 API Key、服务地址和模型名称。重新配置前，AI 对话将不可用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      await AIConfigStore.instance.resetToDefault();
      AIService.instance.reinit();
      if (!mounted) return;
      _key.clear();
      _url.clear();
      _model.clear();
      setState(() {
        _saved = _snapshot;
        _failed = false;
        _feedback = 'AI 配置已清空，请填写新的连接参数。';
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _failed = true;
          _feedback = '清空失败，请重试。';
        });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _allowPop || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI 配置'),
          leading: IconButton(
            tooltip: '返回',
            onPressed: _saving ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _reset,
              child: const Text('清空配置'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MotionEntrance(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [scheme.primaryContainer, scheme.surface],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: .15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.smart_toy_outlined,
                                color: scheme.primary,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '连接你的 AI 服务',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '填写管理员提供的连接参数。保存后，新对话请求会使用这组配置。',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('API Key'),
                        TextFormField(
                          controller: _key,
                          enabled: !_saving,
                          obscureText: !_visible,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? '请输入 API Key'
                              : null,
                          decoration: InputDecoration(
                            hintText: '输入 API Key',
                            suffixIcon: IconButton(
                              tooltip: _visible ? '隐藏 API Key' : '显示 API Key',
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _visible = !_visible),
                              icon: Icon(
                                _visible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _label('服务地址'),
                        TextFormField(
                          controller: _url,
                          enabled: !_saving,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            hintText: 'https://…/v1',
                          ),
                          validator: (v) {
                            final uri = Uri.tryParse(v?.trim() ?? '');
                            if (uri == null ||
                                !['http', 'https'].contains(uri.scheme) ||
                                uri.host.isEmpty)
                              return '请输入完整的 http 或 https 服务地址';
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _label('模型名称'),
                        TextFormField(
                          controller: _model,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            hintText: '输入服务支持的模型名称',
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? '请输入模型名称' : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_feedback != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _feedback!,
                        style: TextStyle(
                          color: _failed
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Text('保存配置'),
                ),
                const SizedBox(height: 12),
                Text(
                  _dirty ? '有尚未保存的修改' : '连接参数保存在当前设备',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
