import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';

/// 分页表格 Hook 返回结果类
class PaginationTableResult<T> {
  /// 执行查询（可指定分页参数）
  final Future<DataPage<T>> Function({int? page, int? size}) execute;

  /// 刷新当前页
  final Future<DataPage<T>> Function({int? page, int? size}) refresh;

  /// 重置分页到初始值
  final void Function() resetPage;

  /// 重置并重新加载
  final Future<void> Function() reload;

  /// 加载状态
  final ValueNotifier<bool> loading;

  /// 删除记录（带确认对话框）
  final Future<void> Function(BuildContext context, T row) deleteRecord;

  /// 数据源
  final ValueNotifier<List<T>> dataSource;

  /// 当前页码
  final ValueNotifier<int> currentPage;

  /// 每页条数
  final ValueNotifier<int> pageSize;

  /// 总条数
  final ValueNotifier<int> total;

  /// 错误/空数据提示信息
  final ValueNotifier<String> errorMsg;

  /// 分页变化回调
  final Future<void> Function({int? page, int? size}) onChange;

  PaginationTableResult({
    required this.execute,
    required this.refresh,
    required this.resetPage,
    required this.reload,
    required this.loading,
    required this.deleteRecord,
    required this.dataSource,
    required this.currentPage,
    required this.pageSize,
    required this.total,
    required this.errorMsg,
    required this.onChange,
  });
}

/// 分页表格 Hook
///
/// 功能包括：
/// - 自动分页查询
/// - 数据转换
/// - 合并自定义查询参数
/// - 删除确认对话框
/// - 重置分页、刷新等
///
/// ## 使用示例
///
/// ```dart
/// final pagination = usePaginationTable<Alarm>(
///   apiFun: (params) => AlarmApi.getPage(
///     current: params['pageNum'],
///     size: params['pageSize'],
///   ),
///   immediate: true,
///   currentPage: 1,
///   pageSize: 10,
///   getQueryParams: () => {
///     'alarmType': selectedType.value,
///     'isHandled': selectedStatus.value,
///   },
///   onDelete: (row) => AlarmApi.delete(row.id!),
/// );
///
/// // 在 UI 中使用
/// ListView.builder(
///   itemCount: pagination.dataSource.value.length,
///   itemBuilder: (context, index) {
///     final item = pagination.dataSource.value[index];
///     return ListTile(
///       title: Text(item.title),
///       trailing: IconButton(
///         icon: const Icon(Icons.delete),
///         onPressed: () => pagination.deleteRecord(context, item),
///       ),
///     );
///   },
/// )
/// ```
///

PaginationTableResult<T> usePaginationTable<T>({
  required Future<DataPage<T>> Function(Map<String, dynamic> params) apiFun,
  bool immediate = true,
  int currentPage = 1,
  int pageSize = 10,
  List<T> Function(dynamic rows)? transformData,
  Map<String, dynamic> Function()? getQueryParams,
  Future<void> Function(T row)? onDelete,
  void Function({
    required List<T> data,
    required int total,
    required int currentPage,
    required int pageSize,
    required bool isInitialLoad,
  })?
  onComplete,
  void Function(
    Object error,
    StackTrace stackTrace, {
    required bool isInitialLoad,
  })?
  onError,
}) {
  // 状态定义
  final loading = useState<bool>(false);
  final errorMsg = useState<String>('');
  final dataSource = useState<List<T>>([]);
  final currentPageNotifier = useState<int>(currentPage);
  final pageSizeNotifier = useState<int>(pageSize);
  final totalNotifier = useState<int>(0);
  final isInitialLoad = useState<bool>(true); // 追踪是否是初始加载
  final context = useContext();

  /// 查询表格数据
  Future<DataPage<T>> queryTableData({int? page, int? size}) async {
    final targetPage = page ?? currentPageNotifier.value;
    final targetSize = size ?? pageSizeNotifier.value;

    var queryParams = <String, dynamic>{
      'pageNum': targetPage,
      'pageSize': targetSize,
    };

    // 合并自定义查询参数
    if (getQueryParams != null) {
      final otherParams = getQueryParams();
      queryParams.addAll(otherParams);
    }

    loading.value = true;
    errorMsg.value = "";

    try {
      final result = await apiFun(queryParams);
      if (!context.mounted) return result;

      final rows = result.records;

      // 数据转换
      List<T> newData = [];
      if (transformData != null && rows != null) {
        newData = transformData(rows);
      } else if (rows != null) {
        newData = rows;
      }

      // 加载更多时追加数据，否则替换数据
      if (targetPage > 1) {
        dataSource.value = [...dataSource.value, ...newData];
      } else {
        dataSource.value = newData;
      }

      // 成功的零结果属于空态；错误文案只用于请求失败。
      errorMsg.value = '';

      // 更新分页信息
      totalNotifier.value = result.total ?? 0;
      currentPageNotifier.value = targetPage;
      pageSizeNotifier.value = targetSize;

      // 在下一帧执行 onComplete 回调
      if (onComplete != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            onComplete(
              data: dataSource.value,
              total: totalNotifier.value,
              currentPage: currentPageNotifier.value,
              pageSize: pageSizeNotifier.value,
              isInitialLoad: isInitialLoad.value,
            );
            // 标记初始加载已完成
            isInitialLoad.value = false;
          }
        });
      }
      return result;
    } catch (e, stackTrace) {
      AppLogger.e('usePaginationTable error:', e, stackTrace);
      if (!context.mounted) rethrow;
      if (targetPage == 1) {
        dataSource.value = [];
      }
      errorMsg.value = e.toString();

      // 在下一帧执行 onError 回调
      if (onError != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            onError(e, stackTrace, isInitialLoad: isInitialLoad.value);
            // 标记初始加载已完成（即使失败）
            isInitialLoad.value = false;
          }
        });
      }
      rethrow;
    } finally {
      if (context.mounted) {
        loading.value = false;
      }
    }
  }

  /// 分页变化回调
  Future<void> onChange({int? page, int? size}) {
    return queryTableData(page: page, size: size);
  }

  /// 重置分页
  void resetPage() {
    currentPageNotifier.value = currentPage;
    pageSizeNotifier.value = pageSize;
  }

  /// 重新加载（重置分页并查询）
  Future<void> reload() async {
    resetPage();
    await queryTableData();
  }

  /// 删除记录（带确认对话框）
  Future<void> deleteRecord(BuildContext context, T row) async {
    if (onDelete == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提醒'),
        content: const Text('确认删除这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await onDelete(row);
        await reload();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  // 组件挂载时自动查询
  useEffect(() {
    if (immediate) {
      try {
        queryTableData().ignore();
      } catch (e, t) {
        AppLogger.e('useSkeleton immediate request error:', e, t);
      }
    }
    return null;
  }, []);

  return PaginationTableResult<T>(
    execute: queryTableData,
    refresh: queryTableData,
    resetPage: resetPage,
    reload: reload,
    loading: loading,
    deleteRecord: deleteRecord,
    dataSource: dataSource,
    currentPage: currentPageNotifier,
    pageSize: pageSizeNotifier,
    total: totalNotifier,
    errorMsg: errorMsg,
    onChange: onChange,
  );
}
