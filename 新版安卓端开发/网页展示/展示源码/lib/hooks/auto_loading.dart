import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// 泛型 run 函数类型
typedef RunFunction = Future<T> Function<T>(Future<T> future);

/// 自动管理 loading 状态的 Hook 返回类
///
/// 对应 TS 中的 `[Ref<boolean>, (promise) => promise]`
///
/// 使用类而不是 record 的原因：
/// Dart 的 record 在包含函数类型时，模式匹配会出现类型推断问题。
/// 这是 Dart 语言的已知限制，使用类是唯一可靠的方式。
class AutoLoadingState {
  /// loading 状态（只读）
  final bool loading;

  /// run 方法：接收一个 Future，在其执行期间自动管理 loading 状态
  final RunFunction run;

  /// 内部 ValueNotifier（用于 Hook 内部管理）
  final ValueNotifier<bool> _loadingNotifier;

  AutoLoadingState._({
    required this.loading,
    required this.run,
    required ValueNotifier<bool> loadingNotifier,
  }) : _loadingNotifier = loadingNotifier;

  /// 释放资源（当 Hook 销毁时调用）
  void dispose() => _loadingNotifier.dispose();
}

/// 自动管理 loading 状态的 Hook
///
/// 在给 run 方法传入一个 Future，会在 Future 执行前将 loading 状态设为 true，
/// 在执行完成后（无论成功或失败）将 loading 状态设为 false。
///
/// 这是对 TS 版本 `useAutoLoading` 的 Dart 风格移植。
///
/// ## 使用示例:
/// ```dart
/// final state = useAutoLoading();
///
/// // 直接使用 state.run 包裹 Future
/// final result = await state.run(UserApi.login(username, password));
///
/// // 在 UI 中使用 state.loading
/// ElevatedButton(
///   onPressed: state.loading ? null : () async {
///     await state.run(someAsyncOperation());
///   },
///   child: Text(state.loading ? '加载中...' : '点击'),
/// )
/// ```
AutoLoadingState useAutoLoading({bool defaultLoading = false}) {
  // 使用 ValueNotifier 存储 loading 状态
  final loadingNotifier = useValueNotifier<bool>(defaultLoading);
  final context = useContext();

  // run 方法：接收一个 Future，在其执行期间自动管理 loading 状态
  final run = useMemoized(() {
    return <T>(Future<T> requestPromise) async {
      loadingNotifier.value = true;
      try {
        return await requestPromise;
      } finally {
        if (context.mounted) {
          loadingNotifier.value = false;
        }
      }
    };
  }, []);

  // 使用 useValueListenable 获取当前的 loading 值
  final isLoading = useValueListenable(loadingNotifier);

  // 返回状态对象
  return AutoLoadingState._(
    loading: isLoading,
    run: run,
    loadingNotifier: loadingNotifier,
  );
}
