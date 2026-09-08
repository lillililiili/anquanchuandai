import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/hooks/use_pagination.dart';
import 'package:rolling_intelligence_headband/theme/theme.dart';

/// 分页状态枚举
enum PaginationStatus {
  /// 初始状态
  idle,

  /// 首次加载中
  loading,

  /// 加载失败
  error,

  /// 空数据
  empty,

  /// 加载成功，还有更多数据
  success,

  /// 加载更多中
  loadingMore,

  /// 没有更多数据了
  noMore,
}

/// 分页列表视图组件
///
/// 结构：[header, slot(data, status), footer]
/// - 使用外部传入的 ScrollController 监听滚动
/// - footer 自动显示 loadingMore/noMore
/// - slot 由用户提供，渲染数据列表
///
/// ## 使用示例
///
/// ```dart
/// SingleChildScrollView(
///   controller: scrollController,
///   child: Column(
///     children: [
///       _StatCard(),
///       PaginationView.fromHook<Alarm>(
///         bind: pagination,
///         scrollController: scrollController,
///         slot: (data, status) => Column(
///           children: data.map((alarm) => AlarmItem(alarm)).toList(),
///         ),
///       ),
///     ],
///   ),
/// )
/// ```
class PaginationView<T> extends HookWidget {
  /// 分页数据结果（来自 usePaginationTable）
  final PaginationTableResult<T> bind;

  /// 外部传入的 ScrollController（用于监听滚动到底部）
  final ScrollController scrollController;

  /// 内容插槽，用户自己渲染数据列表
  ///
  /// 参数说明：
  /// - data: 当前数据列表
  /// - status: 分页状态（用于判断是否显示 loadingMore）
  final Widget Function(List<T> data, PaginationStatus status) slot;

  /// 头部组件（可选）
  final Widget? header;

  /// 空数据视图构建器（可选）
  final Widget Function(BuildContext context)? emptyBuilder;

  /// 错误视图构建器（可选）
  final Widget Function(BuildContext context, VoidCallback onRetry)?
  errorBuilder;

  /// 加载中视图构建器（可选）
  final Widget Function(BuildContext context)? loadingBuilder;

  /// 加载更多视图构建器（可选）
  final Widget Function(BuildContext context)? loadingMoreBuilder;

  /// 无更多数据视图构建器（可选）
  final Widget Function(BuildContext context)? noMoreBuilder;

  /// 空数据提示文案
  final String emptyMsg;

  /// 无更多数据提示文案
  final String noMoreMsg;

  /// 加载更多触发阈值（距离底部多少像素触发，默认 200）
  final double loadMoreThreshold;

  const PaginationView({
    super.key,
    required this.bind,
    required this.scrollController,
    required this.slot,
    this.header,
    this.emptyBuilder,
    this.errorBuilder,
    this.loadingBuilder,
    this.loadingMoreBuilder,
    this.noMoreBuilder,
    this.emptyMsg = '暂无数据',
    this.noMoreMsg = '没有更多了',
    this.loadMoreThreshold = 200.0,
  });

  /// 从 usePaginationTable hook 创建分页视图
  static Widget fromHook<T>({
    required PaginationTableResult<T> bind,
    required ScrollController scrollController,
    required Widget Function(List<T> data, PaginationStatus status) slot,
    Widget? header,
    Widget Function(BuildContext)? emptyBuilder,
    Widget Function(BuildContext, VoidCallback)? errorBuilder,
    Widget Function(BuildContext)? loadingBuilder,
    Widget Function(BuildContext)? loadingMoreBuilder,
    Widget Function(BuildContext)? noMoreBuilder,
    String emptyMsg = '暂无数据',
    String noMoreMsg = '没有更多了',
    double loadMoreThreshold = 200.0,
  }) {
    return PaginationView<T>(
      bind: bind,
      scrollController: scrollController,
      slot: slot,
      header: header,
      emptyBuilder: emptyBuilder,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
      loadingMoreBuilder: loadingMoreBuilder,
      noMoreBuilder: noMoreBuilder,
      emptyMsg: emptyMsg,
      noMoreMsg: noMoreMsg,
      loadMoreThreshold: loadMoreThreshold,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 使用 hooks 监听状态，替代多层 ValueListenableBuilder 嵌套
    final loading = useValueListenable(bind.loading);
    final data = useValueListenable(bind.dataSource);
    final total = useValueListenable(bind.total);
    final errorMsg = useValueListenable(bind.errorMsg);

    // 监听滚动到底部
    useEffect(() {
      void onScroll() {
        if (!scrollController.hasClients) return;

        final position = scrollController.position;
        final shouldLoadMore =
            position.pixels >= position.maxScrollExtent - loadMoreThreshold;

        if (shouldLoadMore &&
            bind.dataSource.value.length < bind.total.value &&
            !bind.loading.value) {
          bind.onChange(page: bind.currentPage.value + 1);
        }
      }

      scrollController.addListener(onScroll);
      return () => scrollController.removeListener(onScroll);
    }, [scrollController, bind, loadMoreThreshold]);

    final status = _convertStatus(loading, data, total, errorMsg);

    // 根据状态返回不同视图
    switch (status) {
      case PaginationStatus.loading:
        return _withHeader(_buildLoadingView(context));
      case PaginationStatus.error:
        return _withHeader(_buildErrorView(context));
      case PaginationStatus.empty:
        return _withHeader(_buildEmptyView(context));
      case PaginationStatus.success:
      case PaginationStatus.loadingMore:
      case PaginationStatus.noMore:
      case PaginationStatus.idle:
        return _buildContentView(context, data, status);
    }
  }

  Widget _withHeader(Widget child) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [if (header != null) header!, child],
  );

  /// 将 hook 状态转换为 PaginationStatus
  PaginationStatus _convertStatus(
    bool loading,
    List<T> data,
    int total,
    String errorMsg,
  ) {
    if (loading && data.isEmpty) {
      return PaginationStatus.loading;
    }
    if (loading && data.isNotEmpty) {
      // 有数据但还在 loading = 加载更多
      return PaginationStatus.loadingMore;
    }
    if (errorMsg.isNotEmpty && data.isEmpty) {
      return PaginationStatus.error;
    }
    if (data.isEmpty) {
      return PaginationStatus.empty;
    }
    if (data.length >= total && total > 0) {
      return PaginationStatus.noMore;
    }
    return PaginationStatus.success;
  }

  /// 构建内容视图 [header, slot, footer]
  Widget _buildContentView(
    BuildContext context,
    List<T> data,
    PaginationStatus status,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // header (Dart 3 syntax)
        if (header != null) header!,
        // slot（用户渲染的数据列表）
        slot(data, status),
        // footer（loadingMore / noMore）
        _buildFooter(context, status),
      ],
    );
  }

  /// 构建底部状态（loadingMore / noMore）
  Widget _buildFooter(BuildContext context, PaginationStatus status) {
    if (status == PaginationStatus.loadingMore) {
      if (loadingMoreBuilder != null) {
        return loadingMoreBuilder!(context);
      }
      return Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '加载中...',
              style: AppTypography.subtitle.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      );
    }

    if (status == PaginationStatus.noMore) {
      if (noMoreBuilder != null) {
        return noMoreBuilder!(context);
      }
      return Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        alignment: Alignment.center,
        child: Text(
          noMoreMsg,
          style: AppTypography.subtitle.copyWith(
            color: Theme.of(context).hintColor,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// 构建加载中视图
  Widget _buildLoadingView(BuildContext context) {
    if (loadingBuilder != null) {
      return loadingBuilder!(context);
    }

    return Container(
      height: 200,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Theme.of(context).primaryColor),
          const SizedBox(height: AppSpacing.md),
          Text(
            '加载中...',
            style: AppTypography.body.copyWith(
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(BuildContext context) {
    if (errorBuilder != null) {
      return errorBuilder!(context, bind.reload);
    }

    return Container(
      height: 200,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Text(
              bind.errorMsg.value.isNotEmpty ? bind.errorMsg.value : '加载失败',
              style: AppTypography.body.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(onPressed: bind.reload, child: const Text('重试')),
        ],
      ),
    );
  }

  /// 构建空数据视图
  Widget _buildEmptyView(BuildContext context) {
    if (emptyBuilder != null) {
      return emptyBuilder!(context);
    }

    return Container(
      height: 200,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: AppSpacing.md),
          Text(
            emptyMsg,
            style: AppTypography.body.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
