import '../core.dart';

/// The work source and membership remain read-only; no inspection progress API.
Future<JsonMap?> loadCurrentWork(WearSession session) async {
  final seen = <String>{};
  JsonMap? pending;
  for (var current = 1; ; current++) {
    final page = await session.api.page(
      '/api/v1/work-tasks/mine',
      current: current,
      size: 20,
    );
    if (page.current != current || page.size <= 0) {
      throw const FormatException('作业分页信息异常');
    }
    final rows = page.records
        .where((task) => seen.add(idOf(task['id'])))
        .toList();
    for (final task in rows) {
      if (task['status'] == 'in_progress') return task;
      if (['ready', 'draft', 'paused'].contains(task['status'])) {
        pending ??= task;
      }
    }
    if (!page.hasMore) return pending;
    if (rows.isEmpty) throw const FormatException('作业分页未继续返回');
  }
}
