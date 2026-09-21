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

/// 内置 ListView 的分页组件
///
/// 适用于作为页面根布局的场景，数据量大时性能更好（使用懒加载）。
/// 页面内容直接作为 ListView 的一部分滚动。
///
/// ## 使用示例
///
/// ```dart
/// class AlarmListPage extends HookWidget {
///   @override
///   Widget build(BuildContext context) {
///     final pagination = usePaginationTable<Alarm>(
///       apiFun: (params) => AlarmApi.getAlarmPage(...),
///       queryInMount: true,
///       pageSize: 20,
///     );
///
///     return Scaffold(
///       appBar: AppBar(title: const Text('告警列表')),
///       body: PaginationListView.fromHook<Alarm>(
///         bind: pagination,
///         header: _AlarmStatsCard(),  // 顶部统计卡片，随列表滚动
///         itemBuilder: (context, alarm, index) => _AlarmListItem(alarm: alarm),
///         separatorBuilder: (context, index) => const Divider(height: 1),
///         onRefresh: () => pagination.reload(),
///       ),
///     );
///   }
/// }
/// ```
class PaginationListView<T> extends HookWidget {
  /// 分页数据结果（来自 usePaginationTable）
  final PaginationTableResult<T> bind;

  /// 列表项构建器
  ///
  /// 参数说明：
  /// - context: BuildContext
  /// - item: 当前列表项数据
  /// - index: 当前列表项索引
  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  /// 顶部固定内容（可选），随列表一起滚动
  /// 如：统计卡片、筛选栏等
  final Widget? header;

  /// 列表项分割线构建器（可选）
  final Widget Function(BuildContext context, int index)? separatorBuilder;

  /// 列表内边距
  final EdgeInsetsGeometry? padding;

  /// 滚动物理效果
  final ScrollPhysics? physics;

  /// 下拉刷新回调（可选）
  /// 提供此回调时，列表支持下拉刷新
  final Future<void> Function()? onRefresh;

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

  const PaginationListView({
    super.key,
    required this.bind,
    required this.itemBuilder,
    this.header,
    this.separatorBuilder,
    this.padding,
    this.physics,
    this.onRefresh,
    this.emptyBuilder,
    this.errorBuilder,
    this.loadingBuilder,
    this.loadingMoreBuilder,
    this.noMoreBuilder,
    this.emptyMsg = '暂无数据',
    this.noMoreMsg = '没有更多了',
    this.loadMoreThreshold = 200.0,
  });

  /// 从 usePaginationTable hook 创建分页列表视图（简化版）
  static Widget fromHook<T>({
    required PaginationTableResult<T> bind,
    required Widget Function(BuildContext, T, int) itemBuilder,
    Widget? header,
    Widget Function(BuildContext, int)? separatorBuilder,
    EdgeInsetsGeometry? padding,
    ScrollPhysics? physics,
    Future<void> Function()? onRefresh,
    Widget Function(BuildContext)? emptyBuilder,
    Widget Function(BuildContext, VoidCallback)? errorBuilder,
    Widget Function(BuildContext)? loadingBuilder,
    Widget Function(BuildContext)? loadingMoreBuilder,
    Widget Function(BuildContext)? noMoreBuilder,
    String emptyMsg = '暂无数据',
    String noMoreMsg = '没有更多了',
    double loadMoreThreshold = 200.0,
  }) {
    return PaginationListView<T>(
      bind: bind,
      itemBuilder: itemBuilder,
      header: header,
      separatorBuilder: separatorBuilder,
      padding: padding,
      physics: physics,
      onRefresh: onRefresh,
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
    // 使用 hooks 监听状态
    final loading = useValueListenable(bind.loading);
    final data = useValueListenable(bind.dataSource);
    final total = useValueListenable(bind.total);
    final errorMsg = useValueListenable(bind.errorMsg);

    final scrollController = useScrollController();

    // 监听滚动到底部触发加载更多
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
        return _buildStateView(
          context,
          _buildLoadingView(context),
          scrollController,
        );
      case PaginationStatus.error:
        return _buildStateView(
          context,
          _buildErrorView(context),
          scrollController,
        );
      case PaginationStatus.empty:
        return _buildStateView(
          context,
          _buildEmptyView(context),
          scrollController,
        );
      case PaginationStatus.success:
      case PaginationStatus.loadingMore:
      case PaginationStatus.noMore:
      case PaginationStatus.idle:
        return _buildListView(context, data, status, scrollController);
    }
  }

  Widget _buildStateView(
    BuildContext context,
    Widget state,
    ScrollController controller,
  ) {
    final view = CustomScrollView(
      controller: controller,
      physics: physics ?? const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (header != null) SliverToBoxAdapter(child: header!),
        SliverToBoxAdapter(child: state),
      ],
    );
    return onRefresh == null
        ? view
        : RefreshIndicator(onRefresh: onRefresh!, child: view);
  }

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

  /// 构建列表视图（使用 CustomScrollView + Sliver）
  Widget _buildListView(
    BuildContext context,
    List<T> data,
    PaginationStatus status,
    ScrollController scrollController,
  ) {
    // 构建 slivers 列表
    final slivers = <Widget>[];

    // Header（可选）
    if (header != null) {
      slivers.add(SliverToBoxAdapter(child: header!));
    }

    // 数据列表
    if (separatorBuilder != null) {
      // 使用 SliverList 并手动处理分隔符
      // item 在偶数索引，separator 在奇数索引
      slivers.add(
        SliverPadding(
          padding: padding ?? EdgeInsets.zero,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // 计算实际的 item 索引：index // 2
                final itemIndex = index ~/ 2;
                // 奇数索引显示 separator，偶数索引显示 item
                if (index.isOdd && itemIndex < data.length) {
                  return separatorBuilder!(context, itemIndex);
                }
                return itemBuilder(context, data[itemIndex], itemIndex);
              },
              childCount: data.length * 2 - 1, // n 个 item + (n-1) 个 separator
            ),
          ),
        ),
      );
    } else {
      // 使用普通 SliverList
      slivers.add(
        SliverPadding(
          padding: padding ?? EdgeInsets.zero,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => itemBuilder(context, data[index], index),
              childCount: data.length,
            ),
          ),
        ),
      );
    }

    // Footer（loadingMore / noMore）
    slivers.add(SliverToBoxAdapter(child: _buildFooter(context, status)));

    final scrollView = CustomScrollView(
      controller: scrollController,
      physics: physics ?? const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );

    // 包装 RefreshIndicator（如果提供了 onRefresh）
    if (onRefresh != null) {
      return RefreshIndicator(onRefresh: onRefresh!, child: scrollView);
    }

    return scrollView;
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
