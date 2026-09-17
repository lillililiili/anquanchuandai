import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core.dart';

class WearLoginPage extends StatefulWidget {
  const WearLoginPage({super.key});
  @override
  State<WearLoginPage> createState() => _WearLoginPageState();
}

class _WearLoginPageState extends State<WearLoginPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController(),
      _password = TextEditingController(),
      _code = TextEditingController();
  bool _obscure = true, _captchaEnabled = false, _captchaLoading = false;
  bool _captchaReady = false;
  String? _uuid, _captchaError;
  Uint8List? _captchaBytes;
  WearSession? _session;
  int _captchaGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (_session != session) {
      _session = session;
      Future.microtask(_captcha);
    }
  }

  Future<void> _captcha() async {
    if (_captchaLoading || !mounted) return;
    final generation = ++_captchaGeneration;
    setState(() {
      _captchaLoading = true;
      _captchaReady = false;
      _captchaError = null;
    });
    try {
      final data = jsonMap(
        await _session!.api.request('GET', '/captchaImage', raw: true),
      );
      if (!mounted || generation != _captchaGeneration) return;
      final enabled = data['captchaEnabled'] != false;
      Uint8List? bytes;
      if (enabled) {
        final text =
            data['img']
                ?.toString()
                .split('base64,')
                .last
                .replaceAll(RegExp(r'\s'), '') ??
            '';
        bytes = base64Decode(text);
        if (bytes.isEmpty || idOf(data['uuid']).isEmpty) {
          throw const FormatException('验证码数据不完整');
        }
      }
      setState(() {
        _captchaEnabled = enabled;
        _captchaReady = true;
        _uuid = data['uuid']?.toString();
        _captchaBytes = bytes;
        _code.clear();
      });
    } catch (e) {
      if (mounted && generation == _captchaGeneration) {
        setState(() {
          _captchaError = '登录验证加载失败，请检查连接后重试';
          _captchaBytes = null;
          _uuid = null;
        });
      }
    } finally {
      if (mounted && generation == _captchaGeneration) {
        setState(() => _captchaLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_session!.busy ||
        !_captchaReady ||
        _captchaLoading ||
        _captchaError != null ||
        !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    try {
      await _session!.login(
        _username.text,
        _password.text,
        code: _captchaEnabled ? _code.text.trim() : null,
        uuid: _captchaEnabled ? _uuid : null,
      );
      if (mounted) _password.clear();
    } catch (_) {
      if (mounted) _captcha();
    }
  }

  @override
  void dispose() {
    _captchaGeneration++;
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _help() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '登录帮助',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.key_outlined),
              title: Text('忘记密码'),
              subtitle: Text('请联系所在厂站管理员核验身份并重置密码。此处不会提交或保存新密码。'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.domain_outlined),
              title: Text('没有可用厂站'),
              subtitle: Text('请管理员为账号分配厂站与相应岗位权限。'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.wifi_off_outlined),
              title: Text('无法连接服务'),
              subtitle: Text('检查网络及服务连接。恢复后点击验证码重试，或重新进入值班台。'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const WearRollingWordmark(height: 24),
        actions: const [WearThemeButton(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    child: WearCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.shield_outlined, size: 32),
                          const SizedBox(height: 18),
                          const Text(
                            '智能穿戴管理平台',
                            style: TextStyle(
                              fontSize: 25,
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '电厂作业现场 · 安全帽 / 安全带 / 后续穿戴设备',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _username,
                            enabled: !session.busy,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '账号',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? '请输入账号' : null,
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _password,
                            enabled: !session.busy,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: _captchaEnabled
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (!_captchaEnabled) _submit();
                            },
                            decoration: InputDecoration(
                              labelText: '密码',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscure ? '显示密码' : '隐藏密码',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? '请输入密码' : null,
                          ),
                          if (_captchaEnabled && _captchaBytes != null) ...[
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _code,
                              enabled: !session.busy,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: '图形验证码',
                                prefixIcon: Icon(Icons.verified_user_outlined),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? '请输入验证码'
                                  : null,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Image.memory(
                                    _captchaBytes!,
                                    height: 48,
                                    fit: BoxFit.contain,
                                    semanticLabel: '图形验证码',
                                    errorBuilder: (_, _, _) =>
                                        const Text('验证码无法显示，请刷新'),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: session.busy ? null : _captcha,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('换一张'),
                                ),
                              ],
                            ),
                          ],
                          if (_captchaLoading)
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: LinearProgressIndicator(),
                            ),
                          if (_captchaError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _captchaError!,
                                    style: TextStyle(color: colors.error),
                                  ),
                                  TextButton.icon(
                                    onPressed: _captcha,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('重试登录验证'),
                                  ),
                                ],
                              ),
                            ),
                          if (session.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                session.error!,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed:
                                session.busy ||
                                    !_captchaReady ||
                                    _captchaLoading ||
                                    _captchaError != null
                                ? null
                                : _submit,
                            child: Text(session.busy ? '正在验证身份…' : '进入值班台'),
                          ),
                          TextButton(
                            onPressed: _help,
                            child: const Text('登录遇到问题'),
                          ),
                          if (session.token != null &&
                              session.me == null &&
                              !session.busy)
                            TextButton(
                              onPressed: session.initialize,
                              child: const Text('重新验证已有会话'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WearSitesPage extends StatelessWidget {
  const WearSitesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    final requested = GoRouterState.of(context).uri.queryParameters['returnTo'];
    final destination =
        const ['/communications', '/events', '/me'].contains(requested)
        ? requested!
        : '/communications';
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择工作厂站'),
        actions: const [WearThemeButton()],
        automaticallyImplyLeading: false,
        leading: session.siteId == null
            ? null
            : IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(destination);
                  }
                },
              ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '选择本次工作范围。通讯、告警和人员位置将同步切换。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (session.error != null)
              Text(
                session.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (session.sites.isEmpty)
              const WearEmpty(title: '暂无可访问的厂站', detail: '请联系管理员分配厂站。'),
            for (final site in session.sites)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WearCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    leading: const Icon(Icons.factory_outlined),
                    title: Text(textOf(site['name'])),
                    subtitle: Text(textOf(site['siteCode'])),
                    trailing: Icon(
                      idOf(site['id']) == session.siteId
                          ? Icons.check_circle_outline
                          : Icons.chevron_right,
                    ),
                    enabled: !session.busy && !session.callActive.value,
                    onTap: () async {
                      try {
                        await session.selectSite(idOf(site['id']));
                        if (context.mounted) context.go(destination);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      }
                    },
                  ),
                ),
              ),
            if (session.busy) const Center(child: CircularProgressIndicator()),
            TextButton(
              onPressed: session.busy || session.callActive.value
                  ? null
                  : session.logout,
              child: const Text('退出当前账号'),
            ),
          ],
        ),
      ),
    );
  }
}
