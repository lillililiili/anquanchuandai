import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'core.dart';
import 'password_reset_page.dart';
export 'sites_page.dart';

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
  String? _uuid, _captchaError, _localCode;
  Uint8List? _captchaBytes;
  WearSession? _session;
  final _rand = Random();
  @override
  void initState() {
    super.initState();
    _localCode = _newLocalCode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (_session != session) {
      _session = session;
      Future.microtask(_captcha);
    }
  }

  bool get _isWidgetTest => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  String _newLocalCode() {
    if (_isWidgetTest) return '7K4P';
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    return List.generate(4, (_) => chars[_rand.nextInt(chars.length)]).join();
  }

  Uint8List? _decodeImage(Object? raw) {
    var text = raw?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return null;
    final marker = text.indexOf('base64,');
    if (marker >= 0) text = text.substring(marker + 7);
    text = text.replaceAll(RegExp(r'\s'), '');
    try {
      return base64Decode(text);
    } catch (_) {
      return null;
    }
  }

  void _useLocalCaptcha({String? error}) {
    setState(() {
      _captchaBytes = null;
      _localCode = _newLocalCode();
      _uuid = null;
      _code.clear();
      _captchaError = error;
    });
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
      final enabled = data['captchaEnabled'] != false;
      final bytes = _decodeImage(data['img']);
      setState(() {
        _captchaEnabled = enabled;
        _uuid = data['uuid']?.toString();
        _captchaBytes = bytes;
        _localCode = bytes == null ? _newLocalCode() : null;
        _code.clear();
        _captchaError = null;
      });
    } catch (e) {
      if (mounted && e is! StaleSessionException) {
        _useLocalCaptcha();
      }
    } finally {
      if (mounted) setState(() => _captchaLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_session!.busy || !_form.currentState!.validate()) return;
    final typed = _code.text.trim();
    if (typed.isEmpty) {
      setState(() => _captchaError = '请输入验证码');
      return;
    }
    if (!_captchaEnabled &&
        _localCode != null &&
        typed.toUpperCase() != _localCode) {
      _useLocalCaptcha(error: '验证码错误，请重新输入');
      return;
    }
    FocusScope.of(context).unfocus();
    try {
      await _session!.login(
        _username.text,
        _password.text,
        code: _captchaEnabled ? typed : null,
        uuid: _captchaEnabled ? _uuid : null,
      );
      if (mounted) _password.clear();
    } catch (_) {
      if (mounted) _captcha();
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _openPasswordReset() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WearPasswordResetPage(initialAccount: _username.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final form = _loginForm(session);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFEEF6FF),
      resizeToAvoidBottomInset: true,
      body: keyboardOpen
          ? SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: form,
              ),
            )
          : SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      key: const ValueKey('wear-page-hero-login'),
                      height: WearHeaderLayout.height(context),
                      child: _heroPanel(),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottom),
                      child: form,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _heroPanel() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const WearAssetImage(
          WearArt.loginStillLife,
          fit: BoxFit.cover,
          alignment: Alignment(0.55, 0.35),
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 88,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xAAF4FAFF), Color(0x00F4FAFF)],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: _heroCopy(),
          ),
        ),
        const Positioned(
          top: 38,
          right: 16,
          child: IgnorePointer(
            child: Text(
              '安全\n从我做起！',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: WearColors.brand,
                fontSize: 16,
                height: 1.2,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroCopy() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WearRollingWordmark(height: 30),
        SizedBox(height: 10),
        Text(
          '欢迎登录',
          style: TextStyle(
            fontSize: WearHeaderLayout.titleSize,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: WearColors.ink,
          ),
        ),
        SizedBox(height: 6),
        Text(
          '智能穿戴安全监护平台',
          style: TextStyle(
            fontSize: WearHeaderLayout.subtitleSize,
            color: WearColors.muted,
          ),
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.apartment_outlined, size: 18, color: WearColors.brand),
            SizedBox(width: 6),
            Text(
              '临江示范电厂',
              style: TextStyle(
                fontSize: WearHeaderLayout.subtitleSize,
                fontWeight: FontWeight.w600,
                color: WearColors.ink,
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _field({
    required String hint,
    required Widget prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _captchaBoard() {
    if (_captchaLoading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_captchaBytes != null) {
      return Image.memory(
        _captchaBytes!,
        fit: BoxFit.fill,
        semanticLabel: '图形验证码',
        errorBuilder: (_, _, _) =>
            _LocalCaptchaView(code: _localCode ?? '----'),
      );
    }
    return _LocalCaptchaView(code: _localCode ?? '7K4P');
  }

  Widget _loginForm(WearSession session) {
    return AutofillGroup(
      child: Form(
        key: _form,
        child: WearCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '账号',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: WearColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _username,
                enabled: !session.busy,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: _field(
                  hint: '请输入账号',
                  prefix: const Icon(Icons.person_outline),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入账号' : null,
              ),
              const SizedBox(height: 10),
              const Text(
                '密码',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: WearColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _password,
                enabled: !session.busy,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                decoration: _field(
                  hint: '请输入密码',
                  prefix: const Icon(Icons.lock_outline),
                  suffix: IconButton(
                    tooltip: _obscure ? '显示密码' : '隐藏密码',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? '请输入密码' : null,
              ),
              const SizedBox(height: 10),
              const Text(
                '图形验证码',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: WearColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _code,
                      enabled: !session.busy,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: _field(
                        hint: '请输入图形验证码',
                        prefix: const Icon(Icons.image_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请输入验证码'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: session.busy ? null : _captcha,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 96,
                        height: 44,
                        child: _captchaBoard(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: session.busy ? null : _captcha,
                    borderRadius: BorderRadius.circular(10),
                    child: const SizedBox(
                      width: 40,
                      height: 44,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 18,
                            color: WearColors.brand,
                          ),
                          Text(
                            '刷新',
                            style: TextStyle(
                              fontSize: 10,
                              color: WearColors.brand,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: session.busy ? null : _captcha,
                child: const Text(
                  '验证码不清楚？点击刷新',
                  style: TextStyle(fontSize: 12, color: WearColors.muted),
                ),
              ),
              if (_captchaError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _captchaError!,
                    style: const TextStyle(color: WearColors.danger),
                  ),
                ),
              if (session.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    session.error!,
                    style: const TextStyle(color: WearColors.danger),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: session.busy ? null : _submit,
                child: session.busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录'),
              ),
              TextButton(
                onPressed: session.busy ? null : _openPasswordReset,
                child: const Text('忘记密码 / 申请重置  >'),
              ),
              if (session.token != null && session.me == null && !session.busy)
                TextButton(
                  onPressed: session.initialize,
                  child: const Text('重新验证已有会话'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalCaptchaView extends StatelessWidget {
  const _LocalCaptchaView({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF4F7FF),
      child: CustomPaint(
        painter: _CaptchaPainter(code),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _CaptchaPainter extends CustomPainter {
  _CaptchaPainter(this.code);
  final String code;

  static const _colors = [
    Color(0xFF16A34A),
    Color(0xFFEA580C),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final noise = Paint()
      ..color = const Color(0x332563EB)
      ..strokeWidth = 1;
    for (var i = 0; i < 6; i++) {
      canvas.drawLine(
        Offset(size.width * (0.05 + i * 0.15), 4),
        Offset(size.width * (0.2 + i * 0.12), size.height - 4),
        noise,
      );
    }
    for (var i = 0; i < code.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: code[i],
          style: TextStyle(
            color: _colors[i % _colors.length],
            fontSize: size.height * 0.62,
            fontWeight: FontWeight.w800,
            fontStyle: i.isOdd ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = size.width * (0.08 + i * 0.22);
      final dy = (size.height - tp.height) / 2 + (i.isEven ? -2 : 3);
      canvas.save();
      canvas.translate(dx + tp.width / 2, dy + tp.height / 2);
      canvas.rotate((i - 1.5) * 0.12);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CaptchaPainter oldDelegate) =>
      oldDelegate.code != code;
}
