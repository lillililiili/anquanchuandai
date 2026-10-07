import 'dart:convert';
import 'package:flutter/material.dart';
import 'core.dart';
import 'queries/management_widgets.dart';
import 'queries/query_widgets.dart';

class WearPasswordResetPage extends StatefulWidget {
  const WearPasswordResetPage({super.key, this.initialAccount = '', this.api});
  final String initialAccount;
  final WearApi? api;
  @override
  State<WearPasswordResetPage> createState() => _WearPasswordResetPageState();
}

class _WearPasswordResetPageState extends State<WearPasswordResetPage> {
  final _form = GlobalKey<FormState>();
  late final _account = TextEditingController(text: widget.initialAccount);
  final _name = TextEditingController(),
      _contact = TextEditingController(),
      _reason = TextEditingController(),
      _code = TextEditingController();
  late final _api =
      widget.api ??
      WearApi(token: () => null, siteId: () => null, epoch: () => 0);
  JsonMap? _captcha;
  bool _busy = false;
  String? _ticket;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    for (final c in [_account, _name, _contact, _reason, _code]) {
      c.dispose();
    }
    _api.invalidate();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final result = jsonMap(
        await _api.request('GET', '/captchaImage', raw: true),
      );
      if (mounted) {
        setState(() {
          _captcha = result;
          _code.clear();
        });
      }
    } catch (e) {
      if (mounted) managementMessage(context, e);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = jsonMap(
        await _api.post(
          '/api/v1/account-recovery/requests',
          data: {
            'identifier': _account.text.trim(),
            'realName': _name.text.trim(),
            'contact': _contact.text.trim(),
            'reason': _reason.text.trim(),
            'code': _code.text.trim(),
            'uuid': _captcha?['uuid'],
          },
        ),
      );
      if (mounted) setState(() => _ticket = idOf(result['id']));
    } catch (e) {
      if (mounted) {
        managementMessage(context, e);
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => QueryPage(
    title: '账号找回',
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_ticket != null)
          ManagementSection(
            title: '申请已提交',
            children: [
              const Text('请联系管理员核实身份。批准后由管理员告知账号及新密码；当前密码尚未改变。'),
              SelectableText('申请编号：$_ticket'),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回登录'),
              ),
            ],
          )
        else
          Form(
            key: _form,
            child: ManagementSection(
              title: '申请账号找回 / 密码重置',
              children: [
                const Text(
                  '忘记账号时可填写人员编号。管理员核实身份后审批。',
                  style: TextStyle(color: WearColors.muted),
                ),
                ManagementField(
                  controller: _account,
                  label: '账号或人员编号',
                  required: true,
                ),
                ManagementField(
                  controller: _name,
                  label: '真实姓名',
                  required: true,
                ),
                ManagementField(
                  controller: _contact,
                  label: '联系电话',
                  required: true,
                  keyboard: TextInputType.phone,
                ),
                ManagementField(
                  controller: _reason,
                  label: '申请说明',
                  required: true,
                  lines: 3,
                ),
                if (_captcha?['captchaEnabled'] != false)
                  Row(
                    children: [
                      Expanded(
                        child: ManagementField(
                          controller: _code,
                          label: '验证码',
                          required: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _busy ? null : _refresh,
                        child: _captcha?['img'] == null
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('加载验证码'),
                              )
                            : Image.memory(
                                base64Decode(_captcha!['img'].toString()),
                                width: 100,
                                height: 45,
                              ),
                      ),
                    ],
                  ),
                FilledButton(
                  onPressed: _busy || _captcha == null ? null : _submit,
                  child: Text(_busy ? '提交中…' : '提交申请'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
