import 'dart:convert';
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
  String? _image, _uuid, _captchaError;
  WearSession? _session;
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
    setState(() {
      _captchaLoading = true;
      _captchaError = null;
    });
    try {
      final data = jsonMap(
        await _session!.api.request('GET', '/captchaImage', raw: true),
      );
      if (!mounted) return;
      setState(() {
        _captchaEnabled = data['captchaEnabled'] != false;
        _image = data['img']?.toString();
        _uuid = data['uuid']?.toString();
        _code.clear();
      });
    } catch (e) {
      if (mounted && e is! StaleSessionException) {
        setState(() => _captchaError = '验证码信息未加载，可重试');
      }
    } finally {
      if (mounted) setState(() => _captchaLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_session!.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    try {
      await _session!.login(
        _username.text,
        _password.text,
        code: _captchaEnabled ? _code.text.trim() : null,
        uuid: _uuid,
      );
      if (mounted) _password.clear();
    } catch (_) {
      if (mounted && _captchaEnabled) _captcha();
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    return Scaffold(
      backgroundColor: WearColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/field-brand/cargo-v2/logo.png',
                            width: 52,
                            height: 52,
                            semanticLabel: 'ROLLING 标志',
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ROLLING 融瓴',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 19,
                                  ),
                                ),
                                Text(
                                  '智能穿戴管理平台',
                                  style: TextStyle(color: WearColors.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (MediaQuery.viewInsetsOf(context).bottom == 0)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            alignment: Alignment.bottomLeft,
                            children: [
                              Image.asset(
                                'assets/field-brand/cargo-v2/login-hero.png',
                                height: 190,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                excludeFromSemantics: true,
                              ),
                              const Positioned(
                                left: 18,
                                right: 18,
                                bottom: 18,
                                child: Text(
                                  '连接现场\n守护每个人',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    height: 1.4,
                                    fontWeight: FontWeight.w800,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 12,
                                        color: Colors.black87,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 25),
                      const WearPageHeader(
                        title: '登录工作台',
                        subtitle: '使用工作账号，进入所属厂站',
                      ),
                      WearCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _username,
                              enabled: !session.busy,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '账号',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? '请输入账号'
                                  : null,
                            ),
                            const SizedBox(height: 16),
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
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? '请输入密码'
                                  : null,
                            ),
                            if (_captchaEnabled) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _code,
                                enabled: !session.busy,
                                decoration: const InputDecoration(
                                  labelText: '验证码',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? '请输入验证码'
                                    : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              TextButton(
                                onPressed: session.busy ? null : _captcha,
                                child: _image == null
                                    ? const Text('加载验证码')
                                    : Image.memory(
                                        base64Decode(_image!),
                                        height: 42,
                                        semanticLabel: '验证码图片，点击刷新',
                                        errorBuilder: (_, _, _) =>
                                            const Text('刷新验证码'),
                                      ),
                              ),
                            ],
                            if (_captchaError != null)
                              TextButton.icon(
                                onPressed: _captcha,
                                icon: const Icon(Icons.refresh),
                                label: Text(_captchaError!),
                              ),
                            if (session.error != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  session.error!,
                                  style: const TextStyle(
                                    color: WearColors.danger,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: session.busy ? null : _submit,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: session.busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('进入工作台'),
                              ),
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
                      const SizedBox(height: 22),
                      const Text(
                        '安全帽与安全带统一管理\n数据权限以当前账号和厂站为准',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: WearColors.muted, height: 1.6),
                      ),
                    ],
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择工作厂站'),
        automaticallyImplyLeading: false,
        leading: session.siteId != null
            ? IconButton(
                tooltip: '返回工作台',
                onPressed: () => context.go('/workbench'),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const WearPageHeader(
              title: '今天在哪个厂站工作？',
              subtitle: '切换后，待办、人员、装备和通讯同步更新。',
            ),
            if (session.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  session.error!,
                  style: const TextStyle(color: WearColors.danger),
                ),
              ),
            if (session.sites.isEmpty)
              const WearEmpty(title: '暂无可访问的厂站', detail: '请联系管理员为此账号分配有效厂站。'),
            for (final site in session.sites)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WearCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    leading: const Icon(Icons.factory_outlined),
                    title: Text(textOf(site['name'])),
                    subtitle: Text(textOf(site['siteCode'])),
                    trailing: idOf(site['id']) == session.siteId
                        ? const Icon(
                            Icons.check_circle,
                            color: WearColors.primary,
                          )
                        : const Icon(Icons.chevron_right),
                    enabled: !session.busy,
                    onTap: () async {
                      try {
                        await session.selectSite(idOf(site['id']));
                        if (context.mounted) context.go('/workbench');
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
              onPressed: session.busy ? null : session.logout,
              child: const Text('退出当前账号'),
            ),
          ],
        ),
      ),
    );
  }
}
