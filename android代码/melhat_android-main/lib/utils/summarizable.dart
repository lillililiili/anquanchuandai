/// 可摘要化的模型 Mixin
///
/// 用于将模型数据转换为 AI 易读的摘要格式
mixin Summarizable {
  /// 单条摘要（一行，用于列表展示）
  String toSummary();

  /// 详细摘要（多条，用于详情展示）
  String toDetail() => toSummary();
}

/// 摘要工具类
///
/// 提供列表、分组等场景的摘要生成
class SummaryHelper {
  /// 生成列表摘要
  ///
  /// [items] 数据列表
  /// [title] 标题（可选）
  /// [emptyMsg] 空数据提示
  /// [maxItems] 最多显示条数，默认 10
  /// [showTotal] 是否显示总数，默认 true
  static String list<T extends Summarizable>(
    List<T> items, {
    String title = '',
    String emptyMsg = '暂无数据',
    int maxItems = 10,
    bool showTotal = true,
  }) {
    if (items.isEmpty) {
      return title.isNotEmpty ? '$title：$emptyMsg' : emptyMsg;
    }

    final buffer = StringBuffer();

    // 标题行
    if (title.isNotEmpty) {
      if (showTotal) {
        buffer.writeln('$title（共 ${items.length} 条）');
      } else {
        buffer.writeln(title);
      }
    }

    // 数据行
    for (final item in items.take(maxItems)) {
      buffer.writeln(item.toSummary());
    }

    // 截断提示
    if (items.length > maxItems) {
      buffer.writeln('...还有 ${items.length - maxItems} 条');
    }

    return buffer.toString().trimRight();
  }

  /// 生成分组摘要
  ///
  /// [groups] 分组数据
  /// [titleFormatter] 分组标题格式化函数
  /// [maxItemsPerGroup] 每组最多显示条数
  static String grouped<K, V extends Summarizable>(
    Map<K, List<V>> groups, {
    String Function(K)? titleFormatter,
    int maxItemsPerGroup = 5,
  }) {
    if (groups.isEmpty) return '暂无数据';

    return groups.entries.map((entry) {
      final title = titleFormatter?.call(entry.key) ?? '${entry.key}';
      return list(
        entry.value,
        title: title,
        maxItems: maxItemsPerGroup,
      );
    }).join('\n\n');
  }

  /// 生成统计摘要
  ///
  /// [stats] 统计数据 Map
  /// [title] 标题
  static String stats(
    Map<String, dynamic> stats, {
    String title = '',
  }) {
    if (stats.isEmpty) return '暂无统计数据';

    final buffer = StringBuffer();
    if (title.isNotEmpty) buffer.writeln(title);

    for (final entry in stats.entries) {
      buffer.writeln('• ${entry.key}：${entry.value}');
    }

    return buffer.toString().trimRight();
  }
}
