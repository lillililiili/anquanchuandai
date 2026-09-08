import 'field_motion.dart';
import 'package:flutter/material.dart';

/// 骨架屏视图状态
enum SkeletonStatus { idle, loading, error, success, empty }

/// Hook 绑定数据类型
typedef SkeletonBind<T> = ({
  ValueNotifier<SkeletonStatus> status,
  ValueNotifier<T?> data,
  Future<T> Function() execute,
  ValueNotifier<String> emptyMsg,
  ValueNotifier<String> errorMsg,
  bool Function(T)? isEmpty,
  Future<T> Function()? onRetry,
  double minHeight,
});

/// 骨架屏视图组件
///
/// 核心思路：接收原始 widget 树，loading 时自动遍历并将 Text/Image 转换为骨架屏样式
/// 类似于 Vue 中的 CSS 穿透效果，但使用 Flutter 的 widget 遍历方式实现
///
/// ## 使用示例
///
/// ```dart
/// SkeletonView(
///   status: skeletonStatus,
///   builder: (data) => ListView.builder(
///     itemCount: dataList.length,
///     itemBuilder: (context, index) {
///       return ListTile(title: Text(dataList[index].title));
///     },
///   ),
/// )
/// ```
class SkeletonView<T> extends StatefulWidget {
  /// 当前视图状态
  final SkeletonStatus status;

  /// 数据构建器（仅在 success 状态下调用）
  final Widget Function(T) builder;

  /// 空数据时的文案
  final String emptyMsg;

  /// 错误时的文案
  final String errorMsg;

  /// 判空回调（用于自定义类型数据）
  final bool Function(T)? isEmpty;

  /// 重试回调
  final VoidCallback? onRetry;

  /// 数据（传递给 builder）
  final T? data;

  /// 最小高度（用于在 scrollable 容器中显示 loading/empty/error 状态）
  final double minHeight;

  const SkeletonView({
    super.key,
    required this.status,
    required this.builder,
    this.data,
    this.emptyMsg = '暂无数据',
    this.errorMsg = '加载失败，点击重试',
    this.isEmpty,
    this.onRetry,
    this.minHeight = 200,
  });

  /// 从 Hook 绑定数据创建骨架屏视图
  ///
  /// ## 使用示例
  ///
  /// ```dart
  /// final skeleton = useSkeleton<List<String>>(
  ///   initialData: [],
  ///   emptyMsg: '暂无数据',
  ///   errorMsg: '加载失败，点击重试',
  ///   isEmpty: (data) => data.isEmpty,
  ///   onRetry: () => skeleton.run(fetchData()),
  /// );
  ///
  /// return SkeletonView.fromHook(
  ///   skeleton,
  ///   (data) => ListView.builder(...),
  /// );
  /// ```
  factory SkeletonView.fromHook(
    SkeletonBind<T> bind,
    Widget Function(T) builder,
  ) {
    return SkeletonView<T>(
      status: bind.status.value,
      data: bind.data.value,
      builder: builder,
      emptyMsg: bind.emptyMsg.value,
      errorMsg: bind.errorMsg.value,
      isEmpty: bind.isEmpty,
      onRetry: () {
        bind.onRetry?.call().ignore();
      },
      minHeight: bind.minHeight,
    );
  }

  @override
  State<SkeletonView> createState() => _SkeletonViewState<T>();
}

class _SkeletonViewState<T> extends State<SkeletonView<T>> {
  /// 判断当前实际状态
  SkeletonStatus get _viewStatus {
    if (widget.status == SkeletonStatus.success && widget.isEmpty != null) {
      if (widget.data == null) {
        return SkeletonStatus.empty;
      }
      return widget.isEmpty!(widget.data as T)
          ? SkeletonStatus.empty
          : SkeletonStatus.success;
    }
    return widget.status;
  }

  @override
  Widget build(BuildContext context) {
    final viewStatus = _viewStatus;

    // idle 状态：显示默认占位（无内容、无 loading）
    if (viewStatus == SkeletonStatus.idle) {
      return SizedBox(height: widget.minHeight);
    }

    // 空状态
    if (viewStatus == SkeletonStatus.empty) {
      return _buildEmptyView();
    }

    // 错误状态
    if (viewStatus == SkeletonStatus.error) {
      if (widget.data != null &&
          !(widget.isEmpty?.call(widget.data as T) ?? false))
        return _content(context, failed: true);
      return _buildErrorView();
    }

    // loading 状态：显示骨架屏占位
    if (viewStatus == SkeletonStatus.loading) {
      if (widget.data != null &&
          !(widget.isEmpty?.call(widget.data as T) ?? false)) {
        return _content(context, refreshing: true);
      }
      final scheme = Theme.of(context).colorScheme;
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.minHeight),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (MotionPolicy.reduced(context))
                    const Icon(Icons.hourglass_empty, size: 18)
                  else
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: MotionActivity(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('正在加载…')),
                ],
              ),
              const SizedBox(height: 20),
              for (final width in [.75, 1.0, .55])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: width,
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    // 成功状态：调用 builder 渲染数据
    return _content(context);
  }

  Widget _content(
    BuildContext context, {
    bool refreshing = false,
    bool failed = false,
  }) => Stack(
    children: [
      widget.builder(widget.data as T),
      if (failed)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.errorMsg,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onRetry,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (refreshing)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: MotionPolicy.reduced(context)
              ? const Text('正在刷新…')
              : const MotionActivity(child: LinearProgressIndicator()),
        ),
    ],
  );

  /// 构建空视图
  Widget _buildEmptyView() {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              widget.emptyMsg,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView() {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              widget.errorMsg,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: widget.onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
