import '../core.dart';
import 'inspection.dart';
import 'query_utils.dart';

/// Follow the same pages and section order as the default "my tasks" list.
/// Duty summary is capped at ten work orders and is not a completion queue.
Future<JsonMap?> loadCurrentWork(WearSession session) async {
  final seen = <String>{};
  for (var current = 1; ; current++) {
    final page = await session.api.page(
      '/api/v1/work-tasks/mine',
      current: current,
      size: 20,
    );
    if (page.current != current || page.size <= 0) {
      throw const FormatException('任务分页信息异常');
    }
    final newRows = page.records
        .where((task) => seen.add(idOf(task['id'])))
        .toList();
    for (final group in ['进行中', '有异常', '待开始', '状态未知']) {
      for (final task in newRows) {
        final taskGroupLabel = session.isDutyAdmin
            ? taskGroup(task['status'])
            : inspectionStatus(
                task['inspectionStatus'] ??
                    (task['status'] == 'ended' ? 'completed' : 'in_progress'),
              );
        if (taskGroupLabel != group ||
            task['status'] == 'ended' ||
            task['inspectionStatus'] == 'completed') {
          continue;
        }
        // An abnormal task may already have every inspection recorded. The
        // report status is independent of completion, so verify its progress.
        if (task['inspectionStatus'] != 'in_progress') {
          final progress = jsonMap(
            await session.api.get(
              '/api/v1/work-tasks/${Uri.encodeComponent(idOf(task['id']))}/inspection',
            ),
          );
          if (progress['total'] == null || progress['completed'] == null) {
            throw const FormatException('巡检进度暂不可用');
          }
          final total = intOf(progress['total']);
          if (total > 0 && intOf(progress['completed']) >= total) continue;
        }
        return task;
      }
    }
    if (!page.hasMore) return null;
    if (newRows.isEmpty) throw const FormatException('任务分页未继续返回');
  }
}
