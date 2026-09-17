import 'dart:async';
import 'package:flutter/material.dart';
import '../core.dart';
import 'event_controller.dart';
import 'event_models.dart';

const _ink = Color(0xFF101F43),
    _muted = Color(0xFF6B88AF),
    _blue = Color(0xFF008BFF),
    _red = Color(0xFFFF3C55),
    _amber = Color(0xFFFFA000);

/// Presentation only: original controller retains permissions, versions and writes.
class EventReferenceView extends StatefulWidget {
  const EventReferenceView({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onSubmit,
    required this.onCommunication,
    required this.legacyDetail,
  });
  final EventController controller;
  final VoidCallback onBack, onSubmit, onCommunication;
  final Widget legacyDetail;
  @override
  State<EventReferenceView> createState() => _EventReferenceViewState();
}

class _EventReferenceViewState extends State<EventReferenceView> {
  late final TextEditingController _note = TextEditingController(
    text: widget.controller
        .draftFor(widget.controller.selected!.id)
        .handleComment,
  );
  final _photos = <String>[];
  bool _demoJoined = false;
  EventController get c => widget.controller;
  WearEvent get e => c.selected!;
  bool get sos => e.type == 'sos';
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String known(String value, [String fallback = '未关联']) =>
      value.isEmpty ? fallback : value;
  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Widget card(Widget child, {EdgeInsets padding = const EdgeInsets.all(12)}) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
  Widget gap() => const SizedBox(height: 10);
  Widget heading(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: _ink,
    ),
  );
  Widget line() => const Divider(height: 17, color: Color(0xFFEDF2F8));
  Widget iconCircle(IconData icon, {Color color = _blue, double size = 36}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: size * .62),
      );
  Widget infoRow(
    IconData icon,
    String title,
    String sub, {
    Color color = _blue,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          iconCircle(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(sub, style: const TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right, color: _muted),
        ],
      ),
    ),
  );
  ButtonStyle button({bool red = false}) => FilledButton.styleFrom(
    backgroundColor: red ? _red : _blue,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(44),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.none,
    ),
  );
  ButtonStyle outline({bool red = false}) => OutlinedButton.styleFrom(
    foregroundColor: red ? _red : _blue,
    minimumSize: const Size.fromHeight(44),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    side: BorderSide(color: red ? _red : _blue),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
  );
  @override
  Widget build(BuildContext context) {
    final draft = c.draftFor(e.id).handleComment;
    if (_note.text != draft) {
      _note.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
    return PopScope(
      canPop: !c.writing,
      child: Scaffold(
        backgroundColor: const Color(0xFFEEF8FF),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: c.refreshFromSignal,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _hero(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (c.detailLoading || c.writing)
                          const LinearProgressIndicator(minHeight: 2),
                        if (c.errorMessage != null) _notice(c.errorMessage!),
                        if (c.conflictMessage != null)
                          _notice('${c.conflictMessage!}；草稿已保留，请核对最新状态'),
                        if (c.successMessage != null)
                          _notice(c.successMessage!),
                        if (sos) ..._sosContent() else ..._abnormalContent(),
                        gap(),
                        card(
                          Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: const ValueKey('event-original-actions'),
                              tilePadding: EdgeInsets.zero,
                              title: const Text(
                                '事件资料与原处置功能',
                                style: TextStyle(fontSize: 13, color: _muted),
                              ),
                              subtitle: const Text(
                                '认领、转交、复核、关联与时间线',
                                style: TextStyle(fontSize: 10, color: _muted),
                              ),
                              children: [widget.legacyDetail],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: card(
      Text(text, style: const TextStyle(color: _muted, fontSize: 12)),
    ),
  );
  Widget _hero(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: (sos ? 194.0 : 176.0) + (scale - 1).clamp(0, 2) * 66,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              sos
                  ? 'assets/field-brand/preview/sos_reference_hero.png'
                  : 'assets/field-brand/preview/verify_reference_hero.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 4,
            left: sos ? 15 : 0,
            right: 14,
            child: Row(
              children: [
                if (!sos)
                  IconButton(
                    tooltip: '返回事件列表',
                    onPressed: c.writing ? null : widget.onBack,
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: _ink,
                      size: 22,
                    ),
                  ),
                const WearRollingWordmark(height: 23),
                const Spacer(),
                Flexible(
                  child: Text(
                    e.demo ? '演示事件' : '事件信息',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: sos ? 0 : 18,
            top: sos ? 55 : 60,
            right: sos ? 135 : 158,
            child: sos
                ? Row(
                    children: [
                      IconButton(
                        tooltip: '返回事件列表',
                        onPressed: c.writing ? null : widget.onBack,
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: _ink,
                          size: 22,
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'SOS协助',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: _ink,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '异常核验',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '安全无小事\n核查每一个风险！',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF315D8F),
                          height: 1.4,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        height: 2,
                        width: 110,
                        color: _blue.withValues(alpha: .5),
                      ),
                    ],
                  ),
          ),
          if (sos)
            Positioned(
              left: 12,
              top: 116,
              right: 145,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_rounded,
                          color: Colors.white,
                          size: 31,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.demo ? 'SOS演练' : 'SOS求救',
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      e.demo ? '演示场景' : '紧急求助 · ${e.statusLabel}',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _abnormalContent() => [
    card(
      Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 35,
                  color: _amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.type == 'geofence' ? '围栏异常' : e.typeLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(
                      '事件 #${e.id}',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '告警需现场核验，不直接判定违规',
                      style: TextStyle(fontSize: 10, color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3C2),
                  border: Border.all(color: const Color(0xFFFFD566)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  e.statusLabel,
                  style: const TextStyle(
                    color: Color(0xFF996000),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          line(),
          Row(
            children: [
              iconCircle(Icons.person_outline),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${known(e.personName)} · ${known(e.sn)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    Text(
                      e.taskId.isEmpty ? '未关联作业' : '关联作业 ${e.taskId}',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 34, color: const Color(0xFFE8EFF8)),
              const SizedBox(width: 10),
              const Icon(Icons.schedule, color: _blue, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '设备数据时间',
                      style: TextStyle(fontSize: 10, color: _muted),
                    ),
                    Text(
                      formatTime(e.occurredAt),
                      style: const TextStyle(fontSize: 12, color: _ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    gap(),
    card(
      Column(
        children: [
          infoRow(
            Icons.description_outlined,
            '原安监事件',
            known(e.sourceEventId, '暂未关联原安监事件'),
          ),
          line(),
          infoRow(Icons.lock_outline, e.statusLabel, '源记录只读；现场操作仍按原权限执行'),
        ],
      ),
    ),
    gap(),
    card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('现场核验说明'),
          const SizedBox(height: 9),
          TextField(
            key: ValueKey('event-handle-input-${e.id}'),
            controller: _note,
            enabled: !c.writing,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            style: const TextStyle(fontSize: 14, color: _ink),
            decoration: InputDecoration(
              hintText: '记录现场核实情况和已采取的措施',
              filled: true,
              fillColor: const Color(0xFFF9FCFF),
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD8E4F3)),
              ),
              counterStyle: const TextStyle(fontSize: 10, color: _muted),
            ),
            onChanged: (value) => unawaited(
              c.updateDraft(
                e.id,
                c.draftFor(e.id).copyWith(handleComment: value),
              ),
            ),
          ),
        ],
      ),
    ),
    gap(),
    _attachmentCard(),
    gap(),
    Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: outline(),
            onPressed: c.writing
                ? null
                : () async {
                    await c.updateDraft(e.id, c.draftFor(e.id));
                    if (mounted) message('草稿已保存在本机；示例附件未上传');
                  },
            child: const Text('保存草稿'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            key: ValueKey('event-handle-submit-${e.id}'),
            style: button(),
            onPressed: c.writing || !c.can(EventCommand.handle)
                ? null
                : widget.onSubmit,
            child: const Text('提交核验'),
          ),
        ),
      ],
    ),
    if (!c.can(EventCommand.handle))
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          e.status == 'open' && c.can(EventCommand.claim)
              ? '请先在下方原处置功能中认领；草稿可先保存。'
              : '当前角色或事件状态不可提交核验，原处置操作见下方。',
          style: const TextStyle(fontSize: 10, color: _muted),
        ),
      ),
    const Padding(
      padding: EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, color: _muted, size: 18),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              '正式结案按原系统权限与流程办理',
              style: TextStyle(fontSize: 10, color: _muted),
            ),
          ),
        ],
      ),
    ),
  ];
  Widget _attachmentCard() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            heading('现场附件'),
            const Spacer(),
            const Flexible(
              child: Text(
                '最多4张 · 本地UI示例',
                style: TextStyle(fontSize: 10, color: _muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (_photos.length < 4)
              SizedBox(
                width: 96,
                height: 92,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: Color(0xFFB9D0E9)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  onPressed: c.writing ? null : _addPhoto,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 37, color: _blue),
                      Text(
                        '添加照片',
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ),
              ),
            for (var i = 0; i < _photos.length; i++)
              SizedBox(
                width: 96,

                child: Column(
                  children: [
                    SizedBox(
                      height: 90,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: InkWell(
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  content: Image.asset(_photos[i]),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('关闭'),
                                    ),
                                  ],
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: Image.asset(
                                  _photos[i],
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton(
                              tooltip: '删除示例照片',
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                              ),
                              onPressed: c.writing
                                  ? null
                                  : () => setState(() => _photos.removeAt(i)),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      '现场照片（示例）',
                      style: TextStyle(fontSize: 10, color: _muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '示例图片仅用于本页预览，尚未接入相册与上传',
          style: TextStyle(fontSize: 9, color: _muted),
        ),
      ],
    ),
  );
  Future<void> _addPhoto() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加照片示例'),
        content: const Text('当前先体验附件布局，可添加、预览、删除示例照片；不会上传到事件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加示例照片'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && _photos.length < 4) {
      setState(
        () =>
            _photos.add('assets/field-brand/preview/work_reference_scene.png'),
      );
    }
  }

  List<Widget> _sosContent() => [
    card(
      Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: _blue,
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: CustomPaint(painter: _SosHelmetPainter()),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      known(e.personName, '人员未知'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(
                      '求助设备 ${known(e.sn, '未知')}',
                      style: const TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 1.36,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Transform.scale(
                      scale: 1.2,
                      child: const Image(
                        image: AssetImage(WearArt.plantMap),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.blue.withValues(alpha: .04),
                    ),
                  ),
                  const Positioned(
                    left: 5,
                    bottom: 5,
                    child: ColoredBox(
                      color: Color(0xCC143448),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Text(
                          '厂区示意 · 非实时地图',
                          style: TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
    ),
    gap(),
    card(
      infoRow(
        Icons.location_on,
        '位置来源：设备 ${known(e.sn, '未知')}',
        e.locationLat.isEmpty || e.locationLng.isEmpty
            ? '位置未知 · 不阻断协助\n事件时间 ${formatTime(e.occurredAt)}'
            : '事件快照 ${e.locationLat}, ${e.locationLng}\n${formatTime(e.occurredAt)} · 非实时定位',
      ),
    ),
    gap(),
    card(
      infoRow(
        Icons.people_outline,
        '协助组：待接入',
        _demoJoined ? '本地演示已加入 · 未建立实际会话' : '暂无已接入的协助组信息',
        color: const Color(0xFF8A56F8),
        onTap: _assist,
      ),
    ),
    gap(),
    Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: button(),
            onPressed: c.writing ? null : _assist,
            icon: const Icon(Icons.person_add_alt_1, size: 22),
            label: Text(_demoJoined ? '已加入（示例）' : '加入协助'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: outline(red: true),
            onPressed: c.writing
                ? null
                : () {
                    if (_demoJoined) {
                      setState(() => _demoJoined = false);
                      message('本地协助演示已结束，未关闭事件');
                    } else {
                      message('当前没有本页建立的协助会话；事件状态未改变');
                    }
                  },
            icon: const Icon(Icons.call_end, size: 22),
            label: const Text('结束协助'),
          ),
        ),
      ],
    ),
    gap(),
    card(
      infoRow(Icons.info_outline, '原设备行为待联调', '帽端长按SOS 3秒退出\n当前为说明，未验证硬件行为'),
    ),
  ];
  Future<void> _assist() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('协助组服务尚未接入'),
        content: Text(
          '求助人员：${known(e.personName)}\n设备：${known(e.sn)}\n可打开已有通信能力，或体验本地协助状态。两者都不会自动呼叫或关闭事件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _demoJoined = true);
            },
            child: const Text('体验本地加入'),
          ),
          if (e.deviceId.isNotEmpty)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onCommunication();
              },
              child: const Text('打开已有通信'),
            ),
        ],
      ),
    );
  }
}

class _SosHelmetPainter extends CustomPainter {
  const _SosHelmetPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 28);
    final white = Paint()..color = Colors.white;
    canvas.drawPath(
      Path()
        ..moveTo(4, 21)
        ..lineTo(4, 15)
        ..quadraticBezierTo(4, 6, 14, 5)
        ..quadraticBezierTo(24, 6, 24, 15)
        ..lineTo(24, 21)
        ..close(),
      white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 2, 4, 18),
        const Radius.circular(2),
      ),
      white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 20, 24, 5),
        const Radius.circular(2),
      ),
      white,
    );
    canvas.drawCircle(const Offset(14, 14), 3, Paint()..color = _blue);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SosHelmetPainter oldDelegate) => false;
}
