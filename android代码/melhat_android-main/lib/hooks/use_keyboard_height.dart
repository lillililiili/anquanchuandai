import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// 获取键盘高度（逻辑像素）
///
/// 通过 WidgetsBindingObserver 监听 didChangeMetrics 触发 setState，
/// 从 PlatformDispatcher 直接读取物理像素并转换为逻辑像素，
/// 避免 MediaQuery InheritedWidget 时序问题。
///
/// 使用示例:
/// ```dart
/// final keyboardHeight = useKeyboardHeight();
/// ```
double useKeyboardHeight([List<Object?>? keys]) {
  return use(_KeyboardHeightHook(keys));
}

class _KeyboardHeightHook extends Hook<double> {
  const _KeyboardHeightHook([List<Object?>? keys]) : super(keys: keys);

  @override
  HookState<double, Hook<double>> createState() => _KeyboardHookState();
}

class _KeyboardHookState extends HookState<double, _KeyboardHeightHook>
    with WidgetsBindingObserver {
  double _keyboardHeight = 0.0;

  @override
  void initHook() {
    super.initHook();
    _keyboardHeight = _readKeyboardHeight();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  double _readKeyboardHeight() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) {
      final raw = view.viewInsets.bottom;
      final dpr = view.devicePixelRatio;
      if (dpr > 0) {
        return raw / dpr;
      }
    }
    return 0.0;
  }

  @override
  void didChangeMetrics() {
    final newHeight = _readKeyboardHeight();
    if (newHeight != _keyboardHeight) {
      _keyboardHeight = newHeight;
      setState(() {});
    }
  }

  @override
  double build(BuildContext context) => _keyboardHeight;
}
