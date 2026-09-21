import 'dart:math';
import 'package:flutter/material.dart';
import 'core.dart';

/// Request-page preview only: no unauthenticated reset-request API exists yet.
class WearPasswordResetPage extends StatefulWidget {
  const WearPasswordResetPage({super.key, this.initialAccount = ''});
  final String initialAccount;

  @override
  State<WearPasswordResetPage> createState() => _WearPasswordResetPageState();
}

class _WearPasswordResetPageState extends State<WearPasswordResetPage> {
  final _form = GlobalKey<FormState>();
  late final _account = TextEditingController(text: widget.initialAccount);
  final _code = TextEditingController();
  final _random = Random.secure();
  late String _captcha = _newCaptcha();
  static const _blue = Color(0xFF008FFF);

  String _newCaptcha() {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    return List.generate(4, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  void _refreshCaptcha() {
    var next = _newCaptcha();
    while (next == _captcha) {
      next = _newCaptcha();
    }
    setState(() {
      _captcha = next;
      _code.clear();
    });
  }

  Future<void> _submit() async {
    if (_form.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('申请服务待接入'),
        content: const Text('当前仅完成页面填写校验，申请尚未发送，密码未变更。请联系厂站管理员处理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _account.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WearColors.background,
    resizeToAvoidBottomInset: true,
    body: SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('password-reset-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回登录',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                  ),
                  const WearRollingWordmark(height: 22),
                  const Spacer(),
                  const Text(
                    '界面预览',
                    style: TextStyle(fontSize: 11, color: WearColors.muted),
                  ),
                ],
              ),
            ),
            _hero(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: _requestCard(),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _hero() => SizedBox(
    height: WearHeaderLayout.height(context),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const WearAssetImage(
          'assets/field-brand/preview/mine_reference_hero.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 150, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '账号与访问',
                  style: TextStyle(fontSize: 10, color: WearColors.brand),
                ),
                const SizedBox(height: 6),
                const Text(
                  '找回登录权限',
                  style: TextStyle(
                    fontSize: WearHeaderLayout.titleSize,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: WearColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '安全作业，平安每一天',
                  style: TextStyle(
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
  );

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      fontSize: 13,
      color: WearColors.muted,
      fontWeight: FontWeight.w400,
    ),
    filled: true,
    fillColor: const Color(0xFFF7FAFF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xFFD8E6F8)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xFFD8E6F8)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: _blue),
    ),
    errorMaxLines: 2,
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: WearColors.ink,
      ),
    ),
  );

  Widget _requestCard() => WearCard(
    padding: const EdgeInsets.all(16),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '填写重置申请，请联系管理员确认。',
            style: TextStyle(
              fontSize: 12,
              color: WearColors.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _label('工作账号'),
          TextFormField(
            key: const ValueKey('password-reset-account'),
            controller: _account,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            style: const TextStyle(fontSize: 14, color: WearColors.ink),
            decoration: _decoration('请输入需要重置的账号'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '请输入工作账号' : null,
          ),
          const SizedBox(height: 14),
          _label('图形验证码'),
          TextFormField(
            key: const ValueKey('password-reset-code'),
            controller: _code,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 14, color: WearColors.ink),
            onFieldSubmitted: (_) => _submit(),
            decoration: _decoration('请输入验证码').copyWith(
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _captcha,
                    key: const ValueKey('password-reset-challenge'),
                    style: const TextStyle(
                      fontSize: 16,
                      letterSpacing: 2,
                      color: WearColors.muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('password-reset-refresh'),
                    tooltip: '刷新验证码',
                    onPressed: _refreshCaptcha,
                    icon: const Icon(
                      Icons.refresh,
                      size: 18,
                      color: WearColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return '请输入验证码';
              return value.trim().toUpperCase() == _captcha
                  ? null
                  : '验证码不正确，请重新输入';
            },
          ),
          const SizedBox(height: 8),
          const Text(
            '演示验证码 · 申请服务尚未接入',
            style: TextStyle(fontSize: 11, color: WearColors.muted),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('password-reset-submit'),
            onPressed: _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('提交密码重置'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF7FF),
              border: Border.all(color: const Color(0xFFD8E6F8)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: Color(0xFF5687BE),
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '申请不代表密码已重置，请等待管理员确认。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF5687BE),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
