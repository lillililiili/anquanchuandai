import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/components/skeleton_view.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// 骨架屏 Hook
///
/// 返回一个包含状态、数据和配置的 record，可直接传递给 [SkeletonView.fromHook]
///
/// ## 使用示例
///
/// ```dart
/// final skeleton = useSkeleton<List<String>>(
///   initialData: [],
///   emptyMsg: '暂无数据',
///   isEmpty: (data) => data.isEmpty,
///   request: fetchData,
///   onComplete: (data) {
///     // 数据加载完成后的回调
///   },
/// );
///
/// return SkeletonView.fromHook(
///   skeleton,
///   (data) => ListView.builder(...),
/// );
/// ```
SkeletonBind<T> useSkeleton<T>({
  required Future<T> Function() request,
  bool immediate = true,
  String emptyMsg = '暂无数据',
  bool Function(T)? isEmpty,
  Object? Function()? commitToken,
  double minHeight = 200,
  void Function(T data, {required bool isInitialLoad})? onComplete,
  void Function(
    Object error,
    StackTrace stackTrace, {
    required bool isInitialLoad,
  })?
  onError,
}) {
  final status = useState<SkeletonStatus>(SkeletonStatus.idle);
  final data = useState<T?>(null);
  final emptyMsgNotifier = useState<String>(emptyMsg);
  final errorMsgNotifier = useState<String>('');
  final isInitialLoad = useState<bool>(true);
  final context = useContext();

  Future<T> execute() async {
    final executionToken = commitToken?.call();
    try {
      status.value = SkeletonStatus.loading;
      final result = await request();

      if (!context.mounted) return result;
      if (commitToken != null && commitToken() != executionToken) return result;
      data.value = result;
      status.value = SkeletonStatus.success;

      if (onComplete != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            onComplete(result, isInitialLoad: isInitialLoad.value);
            isInitialLoad.value = false;
          }
        });
      }

      return result;
    } catch (e, t) {
      AppLogger.e('useSkeleton request error:', e, t);
      if (!context.mounted) rethrow;
      if (commitToken != null && commitToken() != executionToken) rethrow;
      status.value = SkeletonStatus.error;
      errorMsgNotifier.value = e.toString();

      if (onError != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            onError(e, t, isInitialLoad: isInitialLoad.value);
            isInitialLoad.value = false;
          }
        });
      }

      rethrow;
    }
  }

  final isEmptyFunc = useMemoized(() {
    if (isEmpty != null) {
      return (T data) => isEmpty(data);
    } else {
      return (T data) => false;
    }
  }, [isEmpty]);

  // 组件挂载时立即执行请求（如果 immediate 为 true）
  useEffect(() {
    if (immediate) {
      try {
        execute().ignore();
      } catch (e, t) {
        AppLogger.e('useSkeleton immediate request error:', e, t);
      }
    }
    return null;
  }, []);

  return (
    status: status,
    data: data,
    execute: execute,
    emptyMsg: emptyMsgNotifier,
    errorMsg: errorMsgNotifier,
    isEmpty: isEmptyFunc,
    onRetry: execute,
    minHeight: minHeight,
  );
}
