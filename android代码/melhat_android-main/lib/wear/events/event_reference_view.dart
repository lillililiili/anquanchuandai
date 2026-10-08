import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../core.dart';
import '../mock_media.dart';
import 'event_controller.dart';
import 'event_models.dart';
import 'event_location_card.dart';
import 'event_photos.dart';

const _ink = Color(0xFF101F43),
    _muted = Color(0xFF6B88AF),
    _blue = WearColors.brand,
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
    this.onClaim,
    this.onConfirm,
    this.onReview,
  });
  final EventController controller;
  final VoidCallback onBack, onSubmit, onCommunication;
  final Widget legacyDetail;
  final VoidCallback? onClaim, onConfirm, onReview;
  @override
  State<EventReferenceView> createState() => _EventReferenceViewState();
}

class _EventReferenceViewState extends State<EventReferenceView> {
  late final TextEditingController _note;
  late final TextEditingController _situation;
  late final TextEditingController _measures;
  late String _conclusion;
  late int _formBaseVersion;
  int _formRevision = 0;

  @override
  void initState() {
    super.initState();
    // Initialize while the event exists. A revoked session clears the controller
    // before disposal, including editors hidden from ordinary users.
    _note = TextEditingController(text: c.draftFor(e.id).handleComment);
    _situation = TextEditingController(text: _initial('situation'));
    _measures = TextEditingController(text: _initial('measures'));
    _conclusion = _initial('conclusion');
    _formBaseVersion = c.draftFor(e.id).baseVersion ?? e.version;
  }

  String _initial(String field) {
    final draft = c.draftFor(e.id).toJson();
    final local = textOf(draft[field], '');
    return local.isNotEmpty ? local : textOf(e.verificationDraft[field], '');
  }

  EventController get c => widget.controller;
  WearEvent get e => c.selected!;
  bool get sos => e.type == 'sos';
  Color get levelColor => e.isEmergency
      ? _red
      : e.isWarning
      ? WearColors.online
      : _amber;
  @override
  void dispose() {
    _note.dispose();
    _situation.dispose();
    _measures.dispose();
    super.dispose();
  }

  String known(String value, [String fallback = '未关联']) =>
      value.isEmpty ? fallback : value;
  void message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Widget card(Widget child, {EdgeInsets padding = const EdgeInsets.all(12)}) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
  Future<void> _run(EventCommand command) async {
    FocusScope.of(context).unfocus();
    final formWasCurrent = _formBaseVersion == e.version;
    if (command == EventCommand.verify ||
        command == EventCommand.saveVerification) {
      await c.updateDraft(
        e.id,
        c
            .draftFor(e.id)
            .copyWith(
              baseVersion: _formBaseVersion,
              conclusion: _conclusion,
              situation: _situation.text,
              measures: _measures.text,
            ),
      );
    }
    if (!mounted) return;
    if (command == EventCommand.verify ||
        command == EventCommand.endAssistance) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(command == EventCommand.verify ? '提交最终核验？' : '结束本次协助？'),
          content: Text(
            command == EventCommand.verify
                ? '提交后核验记录只读；平台核验不代表外部系统正式结案。'
                : '协助记录将保留，事件仍需单独完成核验。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    final saved = await c.execute(command);
    if (saved && formWasCurrent) {
      _formBaseVersion = c.draftFor(e.id).baseVersion ?? e.version;
    }
    if (mounted && saved) {
      message(c.successMessage ?? (e.demo ? '本地模拟记录已更新' : '记录已更新'));
      WearScope.of(context).requestRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = c.draftFor(e.id).handleComment;
    if (_note.text != note) _note.text = note;
    return PopScope(
      canPop: !c.writing,
      child: Scaffold(
        backgroundColor: WearColors.background,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: c.refreshFromSignal,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _hero(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (c.writing || c.detailLoading)
                          const LinearProgressIndicator(minHeight: 2),
                        if (c.errorMessage != null) _notice(c.errorMessage!),
                        if (c.conflictMessage != null)
                          _notice('${c.conflictMessage}；填写内容已保留，请载入最新草稿后重新核对'),
                        if (!e.isPlatformComplete &&
                            (c.draftFor(e.id).baseVersion ??
                                    _formBaseVersion) !=
                                e.version)
                          OutlinedButton(
                            onPressed: c.writing
                                ? null
                                : () async {
                                    await c.loadLatestDraft();
                                    if (!mounted) return;
                                    setState(() {
                                      final draft = c.draftFor(e.id);
                                      _formBaseVersion = e.version;
                                      _formRevision++;
                                      _conclusion = draft.conclusion;
                                      _situation.text = draft.situation;
                                      _measures.text = draft.measures;
                                      _note.text = draft.handleComment;
                                    });
                                  },
                            child: const Text('载入最新草稿（替换当前填写）'),
                          ),
                        if (c.successMessage != null)
                          _notice(c.successMessage!),
                        _summary(),
                        gap(),
                        if (c.can(EventCommand.claim)) ...[
                          FilledButton.icon(
                            key: const ValueKey('event-claim'),
                            style: button(),
                            onPressed: c.writing
                                ? null
                                : () => _run(EventCommand.claim),
                            icon: const Icon(Icons.assignment_ind_outlined),
                            label: const Text('认领并开始处理'),
                          ),
                          gap(),
                        ],
                        if (e.isSos) ...[_assistanceCard(), gap()],
                        EventLocationCard(event: e),
                        gap(),
                        if (c.can(EventCommand.handle)) ...[
                          _observationForm(),
                          gap(),
                        ],
                        _observations(),
                        gap(),
                        if (c.can(EventCommand.handle) ||
                            c.can(EventCommand.verify)) ...[
                          card(
                            EventPhotoCapture(
                              paths: c.draftFor(e.id).photoPaths,
                              onChanged: (paths) => c.updateDraft(
                                e.id,
                                c.draftFor(e.id).copyWith(photoPaths: paths),
                              ),
                              enabled: !c.writing,
                            ),
                          ),
                          gap(),
                        ],
                        if (c.can(EventCommand.verify)) ...[
                          _verificationForm(),
                          gap(),
                        ],
                        if (e.isPlatformComplete ||
                            !c.can(EventCommand.verify)) ...[
                          _verificationResult(),
                          gap(),
                        ],
                        card(
                          EventSubmittedPhotos(
                            key: ValueKey('event-media-${e.id}'),
                            eventId: e.id,
                            version: e.version,
                          ),
                        ),
                        gap(),
                        if (c.actor.isAdmin && e.deviceId.isNotEmpty) ...[
                          card(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                heading('联系现场'),
                                const SizedBox(height: 8),
                                const Text(
                                  '按设备可用能力发起语音；通话结束不会完成事件核验。',
                                  style: TextStyle(color: _muted, fontSize: 12),
                                ),
                                OutlinedButton.icon(
                                  style: outline(),
                                  onPressed: c.writing
                                      ? null
                                      : widget.onCommunication,
                                  icon: const Icon(Icons.call_outlined),
                                  label: const Text('查看可用通讯装备'),
                                ),
                              ],
                            ),
                          ),
                          gap(),
                        ],
                        _timeline(),
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

  Widget _notice(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: card(
      Text(value, style: const TextStyle(color: _muted, fontSize: 12)),
    ),
  );

  Widget _summary() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            iconCircle(
              e.isSos ? Icons.sos : Icons.warning_amber_outlined,
              color: levelColor,
            ),
            const SizedBox(width: 10),
            Expanded(child: heading(e.alarmLabel)),
            WearBadge(text: e.statusLabel),
          ],
        ),
        line(),
        Text(e.descriptionLabel),
        const SizedBox(height: 8),
        infoRow(Icons.person_outline, '相关人员', known(e.personName)),
        infoRow(
          Icons.source_outlined,
          '报警来源',
          e.source == 'manual_sos'
              ? '手机手动求助'
              : e.demo
              ? '模拟设备上报'
              : '设备上报',
        ),
        infoRow(Icons.devices_outlined, '关联设备', known(e.sn, '未关联设备，仍可文字跟进')),
        infoRow(
          Icons.assignment_outlined,
          '关联作业',
          known(e.taskId, '未关联作业'),
          onTap: e.taskId.isEmpty
              ? null
              : () => context.push('/tasks/${e.taskId}'),
        ),
        infoRow(Icons.schedule, '发生时间', formatTime(e.occurredAt)),
        if (e.locationDescription.isNotEmpty)
          infoRow(Icons.place_outlined, '位置说明', e.locationDescription),
        const Text(
          '平台核验不代表外部告警已解除或正式结案。',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _assistanceCard() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('SOS 协助'),
        const SizedBox(height: 8),
        Text(
          '本条求助 · ${const {'waiting': '等待接警', 'accepted': '已接警 · 等待加入协助', 'active': '正在协助', 'ended': '协助已结束'}[e.assistance['state']] ?? '等待接警'}',
        ),
        Text(
          '协助人数：${(e.assistance['members'] as List? ?? []).length}',
          style: const TextStyle(color: _muted),
        ),
        const Text(
          '加入协助会保存记录，不会自动接通语音。',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        if (c.can(EventCommand.joinAssistance))
          OutlinedButton.icon(
            key: const ValueKey('sos-join'),
            style: outline(red: true),
            onPressed: c.writing
                ? null
                : () => _run(EventCommand.joinAssistance),
            icon: const Icon(Icons.support_agent),
            label: const Text('接警并加入协助'),
          ),
        if (c.can(EventCommand.endAssistance))
          OutlinedButton(
            key: const ValueKey('sos-end'),
            style: outline(),
            onPressed: c.writing
                ? null
                : () => _run(EventCommand.endAssistance),
            child: const Text('结束协助'),
          ),
      ],
    ),
  );

  Widget _observationForm() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('补充现场情况'),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('event-observation'),
          controller: _note,
          enabled: !c.writing,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(hintText: '记录现场情况或需要的帮助，照片可选'),
          onChanged: (value) => c.updateDraft(
            e.id,
            c.draftFor(e.id).copyWith(handleComment: value),
          ),
        ),
        FilledButton(
          key: const ValueKey('event-observation-submit'),
          style: button(),
          onPressed: c.writing ? null : () => _run(EventCommand.handle),
          child: const Text('提交现场情况'),
        ),
        const Text(
          '补充记录不会自动完成核验。',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    ),
  );

  Widget _observations() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading('现场补充记录'),
        const SizedBox(height: 8),
        if (e.observations.isEmpty)
          const Text('暂无补充记录', style: TextStyle(color: _muted)),
        for (final row in e.observations) ...[
          Text(textOf(row['comment'])),
          if (!e.demo)
            EventStoredPhotos(
              blobIds: (row['photoIds'] as List? ?? []).map(idOf).toList(),
            ),
          if (jsonList(row['photos']).isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final photo in jsonList(row['photos']))
                  MockMediaTile(media: photo),
              ],
            ),
          Text(
            '${textOf(row['actor'])} · ${formatTime(row['createdAt'])}',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          line(),
        ],
      ],
    ),
  );

  void _rememberVerification() => unawaited(
    c.updateDraft(
      e.id,
      c
          .draftFor(e.id)
          .copyWith(
            baseVersion: _formBaseVersion,
            conclusion: _conclusion,
            situation: _situation.text,
            measures: _measures.text,
          ),
    ),
  );
  Widget _verificationForm() => card(
    Column(
      key: ValueKey(_formRevision),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('最终核验'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('verification-conclusion'),
          initialValue: _conclusion.isEmpty ? null : _conclusion,
          decoration: const InputDecoration(labelText: '核验结论 *'),
          items: const [
            '设备通信异常',
            '需现场处理',
            '暂无法确认',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: c.writing
              ? null
              : (value) {
                  setState(() => _conclusion = value ?? '');
                  _rememberVerification();
                },
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('verification-situation'),
          controller: _situation,
          enabled: !c.writing,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(labelText: '现场情况 *'),
          onChanged: (_) => _rememberVerification(),
        ),
        TextField(
          key: const ValueKey('verification-measures'),
          controller: _measures,
          enabled: !c.writing,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(labelText: '采取措施'),
          onChanged: (_) => _rememberVerification(),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('verification-save'),
                style: outline(),
                onPressed: c.writing
                    ? null
                    : () => _run(EventCommand.saveVerification),
                child: const Text('保存核验草稿'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const ValueKey('verification-submit'),
                style: button(),
                onPressed: c.writing ? null : () => _run(EventCommand.verify),
                child: const Text('提交最终核验'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _verificationResult() => e.status != 'verified'
      ? card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('待值守人员核验'),
              const SizedBox(height: 8),
              const Text(
                '补充现场情况不会自动完成核验，最终结果将在值守人员提交后显示。',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        )
      : card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('核验结果（只读）'),
              const SizedBox(height: 8),
              Text('核验结论：${textOf(e.verification['conclusion'])}'),
              Text('现场情况：${textOf(e.verification['situation'])}'),
              Text('采取措施：${textOf(e.verification['measures'])}'),
              if (!e.demo)
                EventStoredPhotos(
                  blobIds: (e.verification['photoIds'] as List? ?? [])
                      .map(idOf)
                      .toList(),
                ),
              if (jsonList(e.verification['photos']).isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final photo in jsonList(e.verification['photos']))
                      MockMediaTile(media: photo),
                  ],
                ),
              Text(
                '${textOf(e.verification['actor'])} · ${formatTime(e.verification['createdAt'])}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        );

  Widget _timeline() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading('处理时间线'),
        const SizedBox(height: 8),
        if (c.actions.isEmpty)
          const Text('暂无处理记录', style: TextStyle(color: _muted)),
        for (final action in c.actions.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${formatTime(action.createTime)} · ${action.actor}\n${action.reason}',
            ),
          ),
      ],
    ),
  );
  Widget _hero(BuildContext context) => SizedBox(
    key: const ValueKey('wear-page-hero-event-detail'),
    height: WearHeaderLayout.height(context),
    child: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/field-brand/preview/verify_reference_hero.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          left: 0,
          right: 16,
          child: Row(
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
              const WearRollingWordmark(height: 23),
              const Spacer(),
              if (e.demo)
                const WearBadge(text: '演示事件', color: WearColors.muted),
            ],
          ),
        ),
        Positioned(
          left: 18,
          top: 58,
          right: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '事件详情',
                style: TextStyle(
                  fontSize: WearHeaderLayout.titleSize,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 10),
              WearBadge(
                text: '${e.severityLabel} · ${e.statusLabel}',
                color: e.isEmergency
                    ? _red
                    : e.isWarning
                    ? WearColors.online
                    : _amber,
              ),
              const SizedBox(height: 6),
              Text(
                '现场跟进 · 统一核验',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
