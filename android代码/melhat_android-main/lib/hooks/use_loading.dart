import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// 定义异步函数类型 - 无参版本（推荐）
/// 这是 Dart 风格的类型定义，参考 Vue Composition API 中的 `() => Promise<T>`
///
/// 使用闭包方式传递参数，避免了 Dart 不支持可变参数泛型的问题。
typedef AsyncFun<T> = Future<T> Function();

/// 定义带参异步函数类型（保留用于需要显式参数的场景）
typedef ApiFun<TData, TParams> = Future<TData> Function(TParams params);

/// 控制 loading 状态的自动切换 Hook 返回类型（无参版本）
typedef AutoRequestResult<T> = ({ValueNotifier<bool> loading, AsyncFun<T> run});

/// 控制 loading 状态的自动切换 Hook（无参版本 - 推荐）
///
/// 这是 Dart 风格的设计，参考 Vue Composition API 中的 useRequest 模式。
/// 与 TS 不同，Dart 不支持可变参数泛型，因此采用闭包方式传递参数。
///
/// ## 使用示例:
/// ```dart
/// // 方式 1: 直接传入 API 调用闭包
/// final result = useAutoRequestRef(() => UserApi.login(username, password));
///
/// // 方式 2: 先保存函数引用，稍后调用
/// final result = useAutoRequestRef(() => someApi.call());
/// await result.run(); // 手动调用
/// ```
AutoRequestResult<T> useAutoRequestRef<T>(
  AsyncFun<T> fun, {
  bool initialLoading = false,
  void Function(T)? onSuccess,
}) {
  final loadingNotifier = useValueNotifier<bool>(initialLoading);
  final context = useContext();

  // 对应 run 函数
  final run = useMemoized(() {
    return () async {
      loadingNotifier.value = true;
      try {
        final res = await fun();
        if (onSuccess != null) {
          onSuccess(res);
        }
        return res;
      } finally {
        if (context.mounted) {
          loadingNotifier.value = false;
        }
      }
    };
  }, [fun, onSuccess]);

  return (loading: loadingNotifier, run: run);
}

/// 带参数的 useAutoRequestRef 变体
///
/// 当需要显式传递参数时使用此版本。
/// 对于多参数情况，可以使用记录类型 (param1, param2) 或自定义参数对象。
///
/// ## 使用示例:
/// ```dart
/// // 单参数
/// final result = useAutoRequestRefWithParams((param) => api.call(param));
/// await result.run('someValue');
///
/// // 多参数 (使用记录类型)
/// final result = useAutoRequestRefWithParams<APIResponse<LoginResult>, (String, String)>(
///   (params) => UserApi.login(params.$1, params.$2),
/// );
/// await result.run(('admin', '123456'));
/// ```
AutoRequestResultWithParams<TData, TParams>
useAutoRequestRefWithParams<TData, TParams>(
  ApiFun<TData, TParams> fun, {
  bool initialLoading = false,
  void Function(TData)? onSuccess,
}) {
  final loadingNotifier = useValueNotifier<bool>(initialLoading);
  final context = useContext();

  final run = useMemoized(() {
    return (TParams params) async {
      loadingNotifier.value = true;
      try {
        final res = await fun(params);
        if (onSuccess != null) {
          onSuccess(res);
        }
        return res;
      } finally {
        if (context.mounted) {
          loadingNotifier.value = false;
        }
      }
    };
  }, [fun, onSuccess]);

  return (loading: loadingNotifier, run: run);
}

/// 带参数的 Hook 返回类型
typedef AutoRequestResultWithParams<TData, TParams> = ({
  ValueNotifier<bool> loading,
  ApiFun<TData, TParams> run,
});

/// 自定义一个返回解包状态的 Hook（无参版本 - 推荐）
({bool loading, AsyncFun<T> run}) useAutoRequest<T>(
  AsyncFun<T> fun, {
  bool initialLoading = false,
  void Function(T)? onSuccess,
}) {
  final result = useAutoRequestRef<T>(
    fun,
    initialLoading: initialLoading,
    onSuccess: onSuccess,
  );

  // 内部解包
  final isLoading = useValueListenable(result.loading);

  return (loading: isLoading, run: result.run);
}

/// 带参数的 useAutoRequest 变体
({bool loading, void Function(TParams) run})
useAutoRequestWithParams<TData, TParams>(
  ApiFun<TData, TParams> fun, {
  bool initialLoading = false,
  void Function(TData)? onSuccess,
}) {
  final result = useAutoRequestRefWithParams<TData, TParams>(
    fun,
    initialLoading: initialLoading,
    onSuccess: onSuccess,
  );

  final isLoading = useValueListenable(result.loading);

  return (loading: isLoading, run: result.run);
}
