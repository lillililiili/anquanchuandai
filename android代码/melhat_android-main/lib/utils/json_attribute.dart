/// JSON 属性工具类
class JsonAttribute {
  /// 挑选 JSON 列表中的指定属性
  ///
  /// [data] 原始 JSON 列表（List<Map<String, dynamic>>）
  /// [keys] 需要保留的属性名列表
  ///
  /// 返回只包含指定属性的新列表
  ///
  /// ## 使用示例
  ///
  /// ```dart
  /// final original = [
  ///   {'id': 1, 'name': 'Alice', 'age': 25, 'email': 'alice@example.com'},
  ///   {'id': 2, 'name': 'Bob', 'age': 30, 'email': 'bob@example.com'},
  /// ];
  ///
  /// final result = JsonAttribute.pick(original, ['id', 'name']);
  /// // 结果: [{'id': 1, 'name': 'Alice'}, {'id': 2, 'name': 'Bob'}]
  /// ```
  static List<Map<String, dynamic>> pick(
    List<Map<String, dynamic>> data,
    List<String> keys,
  ) {
    return data.map((item) {
      final picked = <String, dynamic>{};
      for (final key in keys) {
        if (item.containsKey(key)) {
          picked[key] = item[key];
        }
      }
      return picked;
    }).toList();
  }

  /// 挑选对象列表中的指定属性（自动调用 toJson）
  ///
  /// [data] 原始对象列表（List<T>，T 需有 toJson 方法）
  /// [keys] 需要保留的属性名列表
  /// [toJson] 可选的序列化函数，默认调用对象的 toJson()
  ///
  /// ## 使用示例
  ///
  /// ```dart
  /// final alarms = [Alarm(id: 1, title: '告警'), Alarm(id: 2, title: '告警2')];
  ///
  /// final result = JsonAttribute.pickFrom(alarms, ['id', 'title']);
  /// // 结果: [{'id': 1, 'title': '告警'}, {'id': 2, 'title': '告警2'}]
  /// ```
  static List<Map<String, dynamic>> pickFrom<T>(
    List<T> data,
    List<String> keys, {
    Map<String, dynamic> Function(T)? toJson,
  }) {
    return data.map((item) {
      // 获取 json 数据
      final Map<String, dynamic> json;
      if (toJson != null) {
        json = toJson(item);
      } else if (item is Map<String, dynamic>) {
        json = item;
      } else {
        // 尝试调用对象的 toJson 方法
        final dynamic dynamicItem = item;
        json = dynamicItem.toJson() as Map<String, dynamic>;
      }

      // 挑选指定属性
      final picked = <String, dynamic>{};
      for (final key in keys) {
        if (json.containsKey(key)) {
          picked[key] = json[key];
        }
      }
      return picked;
    }).toList();
  }

  /// 排除对象列表中的指定属性（自动调用 toJson）
  ///
  /// [data] 原始对象列表
  /// [excludeKeys] 需要排除的属性名列表
  /// [toJson] 可选的序列化函数
  static List<Map<String, dynamic>> excludeFrom<T>(
    List<T> data,
    List<String> excludeKeys, {
    Map<String, dynamic> Function(T)? toJson,
  }) {
    final excludeSet = Set<String>.from(excludeKeys);

    return data.map((item) {
      // 获取 json 数据
      final Map<String, dynamic> json;
      if (toJson != null) {
        json = toJson(item);
      } else if (item is Map<String, dynamic>) {
        json = item;
      } else {
        final dynamic dynamicItem = item;
        json = dynamicItem.toJson() as Map<String, dynamic>;
      }

      // 排除指定属性
      final filtered = <String, dynamic>{};
      for (final entry in json.entries) {
        if (!excludeSet.contains(entry.key)) {
          filtered[entry.key] = entry.value;
        }
      }
      return filtered;
    }).toList();
  }
}
