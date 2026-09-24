import 'package:flutter/material.dart';
import '../core.dart';
import 'query_utils.dart';
import 'inspection.dart';

String workOwnerLabel(JsonMap task, WearSession session) {
  final explicit = textOf(task['ownerName'], '');
  if (explicit.isNotEmpty) return explicit;
  final id = idOf(task['ownerUserId']);
  if (id == session.userId) {
    return textOf(
      session.me?['nickName'],
      textOf(session.me?['userName'], '当前用户'),
    );
  }
  return id.isEmpty ? '未关联' : '账号 $id';
}

String workGuardianLabel(JsonMap task) {
  final explicit = textOf(task['guardianName'], '');
  if (explicit.isNotEmpty) return explicit;
  final id = idOf(task['guardianPersonId']);
  for (final person in jsonList(task['members'])) {
    if (idOf(person['personId']) == id) return textOf(person['name']);
  }
  return id.isEmpty ? '未关联' : '人员 $id';
}

/// Local read-only fixture, used only after explicitly opening the UI example.
/// IDs are never sent to business APIs.
Future<JsonMap> workReferencePreview() async => {
  'id': 'ui-preview',
  'title': '锅炉平台检修',
  'demo': true,
  'ownerName': '李志远',
  'guardianName': '周明',
  'status': 'in_progress',
  'workType': 'height',
  'spaceName': '锅炉平台',
  'ticketRequired': true,
  'ticketStatus': 'provided',
  'ticketNo': 'GL-20260915-018',
  'members': [
    {'personId': 'preview-1', 'name': '陈建国', 'personCode': '示例'},
    {'personId': 'preview-2', 'name': '赵启航', 'personCode': '示例'},
    {'personId': 'preview-3', 'name': '孙立', 'personCode': '示例'},
  ],
  'equipmentCheck': [
    for (var i = 1; i <= 3; i++)
      for (final type in ['helmet', 'belt', 'watch'])
        {
          'personId': 'preview-$i',
          'personName': ['陈建国', '赵启航', '孙立'][i - 1],
          'typeCode': type,
          'result': i == 1 && type == 'belt' ? 'unknown' : 'ok',
          'sn': '示例-$type-$i',
        },
  ],
  'events': [
    {
      'id': 'preview-event',
      'personName': '陈建国',
      'type': 'realtime',
      'status': 'open',
      'description': '安全带连接中断',
      'occurredAt': '2026-09-17T10:39:00+08:00',
    },
  ],
};

class TaskReferenceView extends StatelessWidget {
  const TaskReferenceView({
    super.key,
    required this.task,
    required this.equipment,
    required this.events,
    required this.owner,
    required this.guardian,
    required this.onBack,
    required this.onRefresh,
    required this.onPerson,
    required this.onEvent,
    required this.onGuardian,
    required this.details,
    required this.equipmentDetails,
    this.memberEquipment = const {},
    this.preview = false,
    this.onManageMembers,
    this.inspectionActions,
  });
  final JsonMap task;
  final List<JsonMap> equipment, events;
  final Map<String, List<JsonMap>?> memberEquipment;
  final String owner, guardian;
  final VoidCallback onBack, onGuardian;
  final Future<void> Function() onRefresh;
  final void Function(JsonMap) onPerson, onEvent;
  final Widget details, equipmentDetails;
  final bool preview;
  final VoidCallback? onManageMembers;
  final Widget? inspectionActions;
  static const ink = Color(0xFF101F43),
      muted = Color(0xFF6B88AF),
      blue = Color(0xFF008BFF);

  Widget _card(Widget child) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: child,
    ),
  );
  Widget _line() => const Divider(height: 1, color: Color(0xFFEDF2F8));
  Widget _field(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 20, color: muted),
        const SizedBox(width: 12),
        SizedBox(
          width: 87,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: muted),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 14, color: ink)),
        ),
      ],
    ),
  );
  Widget _avatar() => const WearAssetImage(
    WearArt.characterAvatar,
    width: 46,
    height: 46,
    fit: BoxFit.cover,
    borderRadius: BorderRadius.all(Radius.circular(23)),
  );

  @override
  Widget build(BuildContext context) {
    final members = jsonList(task['members']);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            SizedBox(
              key: const ValueKey('wear-page-hero-task'),
              height: WearHeaderLayout.height(context),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/field-brand/preview/task_reference_hero.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 3,
                    left: 0,
                    right: 12,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '返回来源页面',
                          onPressed: onBack,
                          icon: const Icon(
                            Icons.arrow_back_ios_new,
                            size: 22,
                            color: ink,
                          ),
                        ),
                        const WearRollingWordmark(height: 23),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            preview
                                ? '界面示例 · 非真实业务'
                                : task['demo'] == true
                                ? '演示作业'
                                : '作业信息',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 18,
                    top: 60,
                    right: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '作业详情',
                          style: TextStyle(
                            fontSize: WearHeaderLayout.titleSize,
                            fontWeight: FontWeight.w900,
                            color: ink,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '安全作业，平安每一天！',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card(
                    Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEAF7FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.description_outlined,
                                color: blue,
                                size: 25,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                textOf(task['title']),
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2F3FF),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                inspectionStatus(
                                  task['inspectionStatus'] ??
                                      (task['status'] == 'ended'
                                          ? 'completed'
                                          : 'in_progress'),
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: inspectionColor(
                                    task['inspectionStatus'],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _line(),
                        _field(
                          Icons.description_outlined,
                          '来源工作票',
                          task['ticketRequired'] == false
                              ? '无需工作票'
                              : textOf(
                                  task['ticketNo'],
                                  task['ticketStatus'] == 'unverified'
                                      ? '待核实'
                                      : '未关联',
                                ),
                        ),
                        _line(),
                        _field(Icons.person_outline, '工作负责人', owner),
                        _line(),
                        _field(Icons.person_outline, '监护人', guardian),
                        _line(),
                        Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: PageStorageKey('task-info-${task['id']}'),
                            tilePadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            minTileHeight: 36,
                            leading: const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: muted,
                            ),
                            title: const Text(
                              '许可与审批以原工作票系统为准',
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                            subtitle: const Text(
                              '更多作业信息',
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                            children: [details],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '安全提醒',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            '正确佩戴安全帽与防护用品，保持通讯畅通。',
                            style: TextStyle(color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _card(
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        key: PageStorageKey('task-members-${task['id']}'),
                        tilePadding: EdgeInsets.zero,
                        initiallyExpanded: false,
                        title: Row(
                          children: [
                            const Icon(Icons.groups, color: blue, size: 26),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '参与人员 · ${members.length} 人',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 6),
                          child: Text(
                            members.isEmpty
                                ? '暂无参与人员'
                                : '${members.map((p) => textOf(p['name'])).join('、')}\n展开查看人员与装备状态',
                            style: const TextStyle(fontSize: 12, color: muted),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        children: [
                          if (onManageMembers != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: onManageMembers,
                                child: const Text('调整人员'),
                              ),
                            ),
                          if (members.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text(
                                '暂无参与人员',
                                style: TextStyle(color: muted),
                              ),
                            ),
                          for (final person in members) ...[
                            InkWell(
                              key: ValueKey(
                                'task-person-${idOf(person['personId'])}',
                              ),
                              onTap: () => onPerson(person),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    _avatar(),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            textOf(person['name']),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: ink,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Wrap(
                                            spacing: 9,
                                            runSpacing: 4,
                                            children: [
                                              for (final type in [
                                                'helmet',
                                                'belt',
                                                'watch',
                                              ])
                                                _memberStatus(person, type),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _line(),
                          ],
                          Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: PageStorageKey(
                                'task-equipment-${task['id']}',
                              ),
                              tilePadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              minTileHeight: 32,
                              title: Text(
                                '装备检查（${equipment.length}）',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                              children: [equipmentDetails],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ?inspectionActions,
                  if (inspectionActions == null)
                    OutlinedButton.icon(
                      onPressed: onGuardian,
                      icon: const Icon(Icons.call, size: 25),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: blue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      label: const Text(
                        '联系监护人',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberStatus(JsonMap person, String type) {
    final previewItems = equipment.where(
      (e) =>
          idOf(e['personId']) == idOf(person['personId']) &&
          e['typeCode'] == type,
    );
    final result = previewItems.isEmpty ? null : previewItems.first['result'];
    final state = preview
        ? (result == 'ok'
              ? '正常'
              : result == 'missing'
              ? '缺少'
              : result == null
              ? '未关联'
              : '待核验')
        : taskMemberDeviceStatus(
            memberEquipment[idOf(person['personId'])],
            type,
          );
    final normal = state == '在线' || (preview && state == '正常');
    final color = normal
        ? const Color(0xFF00BE95)
        : ['未关联', '状态未知', '离线', '未获取'].contains(state)
        ? muted
        : const Color(0xFFFFA000);
    final label = switch (type) {
      'helmet' => '帽',
      'belt' => '带',
      _ => '表',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(20, 20),
          painter: _EquipmentGlyph(type, color),
        ),
        const SizedBox(width: 3),
        Text(
          '$label$state',
          style: TextStyle(fontSize: 11, color: normal ? muted : color),
        ),
      ],
    );
  }
}

/// Missing requests, unassigned equipment and stale telemetry are distinct.
/// When several devices of one type exist, surface a problem before "online".
String taskMemberDeviceStatus(List<JsonMap>? assignments, String type) {
  if (assignments == null) return '未获取';
  final devices = assignments.where((device) => device['typeCode'] == type);
  if (devices.isEmpty) return '未关联';
  final states = devices.map((device) {
    final connection = connectionLabel(device);
    if (connection != '在线') return connection;
    final status = device['simulationStatus']?.toString();
    if (status != null && status.isNotEmpty && status != 'normal') {
      final label = device['simulationStatusLabel']?.toString().trim();
      return label != null && label.isNotEmpty ? label : '异常';
    }
    return connection;
  }).toList();
  return states.firstWhere((state) => state != '在线', orElse: () => '在线');
}

class _EquipmentGlyph extends CustomPainter {
  const _EquipmentGlyph(this.type, this.color);
  final String type;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    if (type == 'helmet') {
      canvas.drawPath(
        Path()
          ..moveTo(3, 18)
          ..lineTo(3, 13)
          ..quadraticBezierTo(3, 5, 12, 4)
          ..quadraticBezierTo(21, 5, 21, 13)
          ..lineTo(21, 18)
          ..close(),
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(10, 2, 4, 15),
          const Radius.circular(2),
        ),
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(1, 17, 22, 5),
          const Radius.circular(2),
        ),
        fill,
      );
    } else if (type == 'belt') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(5, 5, 14, 14),
          const Radius.circular(2),
        ),
        stroke,
      );
      canvas.drawRect(const Rect.fromLTWH(0, 8, 6, 8), fill);
      canvas.drawRect(const Rect.fromLTWH(18, 8, 6, 8), fill);
      canvas.drawLine(const Offset(13, 5), const Offset(13, 19), stroke);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 0, 8, 24),
          const Radius.circular(2),
        ),
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 5, 16, 14),
          const Radius.circular(3),
        ),
        fill,
      );
      canvas.drawLine(
        const Offset(12, 8),
        const Offset(12, 13),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2,
      );
      canvas.drawLine(
        const Offset(12, 13),
        const Offset(15, 13),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EquipmentGlyph oldDelegate) =>
      type != oldDelegate.type || color != oldDelegate.color;
}
