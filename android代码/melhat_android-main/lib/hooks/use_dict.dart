import 'package:rolling_intelligence_headband/api/system.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// 字典数据 Hook 返回类
///
/// 由 useMemoized 保持同一实例，字段值在每次 rebuild 时同步更新。
/// 闭包捕获的是实例引用，因此始终读取最新数据：
/// ```dart
/// final dict = useDict('my_dict');
/// // UI 中：
/// if (dict.loading) ...
/// // 闭包中：
/// final items = dict.data;
/// ```
class DictState {
  /// 字典数据列表
  List<DictItem> data;

  /// 是否正在加载
  bool loading;

  /// 是否已完成过至少一次加载（成功或失败）
  bool loaded;

  /// 错误信息
  String? error;

  DictState({
    required this.data,
    required this.loading,
    required this.loaded,
    this.error,
  });
}

/// 字典项模型
class DictItem {
  final String? label;
  final String? value;
  final int? sort;

  DictItem({this.label, this.value, this.sort});

  factory DictItem.fromJson(Map<String, dynamic> json) {
    return DictItem(
      label: json['dictLabel'] as String?,
      value: json['dictValue'] as String?,
      sort: json['sort'] as int?,
    );
  }
}

/// 字典数据 Hook
///
/// 根据字典 key 请求字典数据，自动管理加载状态和错误处理
///
/// 使用示例:
/// ```dart
/// class MyWidget extends HookWidget {
///   @override
///   Widget build(BuildContext context) {
///     final dict = useDict('fence_type');
///
///     if (dict.loading) {
///       return CircularProgressIndicator();
///     }
///
///     if (dict.error != null) {
///       return Text('加载失败: ${dict.error}');
///     }
///
///     return DropdownButton(
///       items: dict.data.map((item) => DropdownMenuItem(
///         value: item.value,
///         child: Text(item.label ?? ''),
///       )).toList(),
///       onChanged: (v) {},
///     );
///   }
/// }
/// ```
DictState useDict(String dictKey) {
  // 同一实例，字段值在每次 rebuild 时同步
  final dictState = useMemoized(
    () => DictState(data: [], loading: false, loaded: false),
  );
  final data = useState<List<DictItem>>([]);
  final loading = useState(false);
  final loaded = useState(false);
  final error = useState<String?>(null);
  final context = useContext();

  // 每次 rebuild 同步最新值到 dictState 实例
  dictState.data = data.value;
  dictState.loading = loading.value;
  dictState.loaded = loaded.value;
  dictState.error = error.value;

  useEffect(() {
    Future<void> fetchDict() async {
      loading.value = true;
      error.value = null;

      try {
        final list = await SystemApi.getDictByType(dictKey);
        if (!context.mounted) return;
        data.value = list;
      } catch (e, t) {
        AppLogger.e('useDict[$dictKey]', e, t);
        if (context.mounted) {
          error.value = e.toString();
        }
      } finally {
        if (context.mounted) {
          loading.value = false;
          loaded.value = true;
        }
      }
    }

    if (dictKey.isNotEmpty) {
      fetchDict();
    }

    return null;
  }, [dictKey]);

  return dictState;
}
