import '../components/tech_surface.dart';
import '../components/field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/api/user.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import 'package:rolling_intelligence_headband/store/user_store.dart';
import '../components/field_brand.dart';
import '../utils/app_logger.dart';

class LoginView extends HookWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final usernameController = useTextEditingController();
    final passwordController = useTextEditingController();
    final errorMessage = useState<String?>(null);
    final loading = useState(false);
    final obscurePassword = useState(true);
    final userStore = useUserStore();

    Future<void> handleLogin() async {
      if (loading.value) return;
      final username = usernameController.text.trim();
      final password = passwordController.text;
      if (username.isEmpty || password.isEmpty) {
        errorMessage.value = '请输入用户名和密码';
        return;
      }
      FocusScope.of(context).unfocus();
      errorMessage.value = null;
      loading.value = true;
      try {
        final res = await UserApi.login(username, password);
        if (!context.mounted) return;
        if (!res.isSuccess) {
          errorMessage.value = res.msg.isNotEmpty ? res.msg : '登录失败，请检查账号和密码';
          return;
        }
        final loggedIn = await userStore.login(token: res.token);
        if (!loggedIn) {
          if (context.mounted) errorMessage.value = '登录状态保存失败，请重试';
          return;
        }
        try {
          final profile = await UserApi.getUserProfile();
          if (profile.isSuccess && profile.user != null) {
            await userStore.updateUserInfo(profile.user!);
          }
        } catch (e) {
          AppLogger.e('getUserProfile error', e);
        }
        if (context.mounted) context.replace(RouteNode.homeTab1);
      } catch (e) {
        if (context.mounted) errorMessage.value = '暂时无法登录，请检查网络后重试';
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final scheme = Theme.of(context).colorScheme;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!keyboardOpen)
                    const MotionEntrance(child: FieldLoginHero())
                  else
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const FieldBrandMark(size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '分体式安全帽',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  MotionEntrance(
                    index: 2,
                    child: Transform.translate(
                      offset: Offset(0, keyboardOpen ? 0 : -24),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: .6),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.onSurface.withValues(alpha: .04),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '欢迎回来',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '登录现场工作台，掌握作业动态',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '账号',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _LoginFocusBorder(
                                child: TextField(
                                  controller: usernameController,
                                  enabled: !loading.value,
                                  autofillHints: const [AutofillHints.username],
                                  decoration: const InputDecoration(
                                    hintText: '请输入工作账号',
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                      borderSide: BorderSide.none,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.person_outline,
                                      size: 20,
                                    ),
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                '密码',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _LoginFocusBorder(
                                child: TextField(
                                  controller: passwordController,
                                  enabled: !loading.value,
                                  autofillHints: const [AutofillHints.password],
                                  obscureText: obscurePassword.value,
                                  decoration: InputDecoration(
                                    hintText: '请输入密码',
                                    focusedBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                      borderSide: BorderSide.none,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline,
                                      size: 20,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: obscurePassword.value
                                          ? '显示密码'
                                          : '隐藏密码',
                                      onPressed: loading.value
                                          ? null
                                          : () => obscurePassword.value =
                                                !obscurePassword.value,
                                      icon: Icon(
                                        obscurePassword.value
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => handleLogin(),
                                ),
                              ),
                              if (errorMessage.value != null) ...[
                                const SizedBox(height: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    errorMessage.value!,
                                    style: TextStyle(color: scheme.error),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: loading.value ? null : handleLogin,
                                child: loading.value
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: scheme.onPrimary,
                                          semanticsLabel: '正在登录',
                                        ),
                                      )
                                    : const Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '登录并进入工作台',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(Icons.arrow_forward, size: 19),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Text(
                      '人员动态 · 设备状态 · 现场协同',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uses the same independent image and composition as the mobile web reference.
class FieldLoginHero extends StatelessWidget {
  const FieldLoginHero({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = Theme.of(context).scaffoldBackgroundColor;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: largeText ? 430 : 340),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/field-brand/login-scene.webp',
              fit: BoxFit.cover,
              alignment: const Alignment(0, .52),
              excludeFromSemantics: true,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background.withValues(alpha: .65),
                    background.withValues(alpha: .12),
                    background.withValues(alpha: 0),
                    background,
                  ],
                  stops: const [0, .32, .62, 1],
                ),
              ),
            ),
          ),
          const Positioned.fill(child: TechAura()),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 26, 26, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const FieldBrandMark(size: 46),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '分体式安全帽',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '现场安全管理',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '每一次作业，\n都安心可见。',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 29,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animate focus without replacing the editable subtree or its controller.
class _LoginFocusBorder extends HookWidget {
  const _LoginFocusBorder({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final focused = useState(false);
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => focused.value = value,
      child: AnimatedContainer(
        duration: MotionPolicy.duration(context, MotionPolicy.contentMs),
        curve: Curves.easeOutCubic,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused.value
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: child,
      ),
    );
  }
}
