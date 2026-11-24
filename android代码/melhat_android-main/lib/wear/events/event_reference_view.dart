import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../core.dart';
import '../mock_media.dart';
import 'event_controller.dart';
import 'event_models.dart';
import 'event_location_card.dart';
import 'event_photos.dart';

const _ink = WearColors.ink, _muted = WearColors.muted;

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
  EventCommand? _editor;
  bool _showLocation = false;

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
    if (_conclusion.isNotEmpty ||
        _situation.text.isNotEmpty ||
        _measures.text.isNotEmpty) {
      if (c.can(EventCommand.verify)) _editor = EventCommand.verify;
    }
    if (_editor == null &&
        _note.text.isNotEmpty &&
        !c.isHandleCommentSubmitted(e.id) &&
        c.can(EventCommand.handle)) {
      _editor = EventCommand.handle;
    }
  }

  String _initial(String field) {
    final draft = c.draftFor(e.id).toJson();
    final local = textOf(draft[field], '');
    return local.isNotEmpty ? local : textOf(e.verificationDraft[field], '');
  }

  EventController get c => widget.controller;
  WearEvent get e => c.selected!;
  bool get worksEnabled => WearScope.of(context).workBusinessEnabled;
  bool get externalLinked => worksEnabled && e.sourceEventId.isNotEmpty;
  Color get levelColor => e.isEmergency
      ? WearColors.danger
      : e.isWarning
      ? WearColors.online
      : WearColors.warning;

  @override
  void dispose() {
    _note.dispose();
    _situation.dispose();
    _measures.dispose();
    super.dispose();
  }

  Widget _heading(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: _ink,
    ),
  );

  Widget _fact(String label, String value, {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: _muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: onTap == null ? _ink : WearColors.brand),
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, size: 20, color: _muted),
        ],
      ),
    );
    return onTap == null
        ? row
        : InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Align(alignment: Alignment.centerLeft, child: row),
            ),
          );
  }

  Future<void> _run(EventCommand command) async {
    FocusScope.of(context).unfocus();
    final eventId = e.id;
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
                ? externalLinked
                      ? '提交后核验记录只读；平台核验不代表外部系统正式结案。'
                      : '提交后核验记录只读，请确认现场情况和结论。'
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
    if (!mounted || !saved || c.selected?.id != eventId) return;
    setState(() {
      if (formWasCurrent) {
        _formBaseVersion = c.draftFor(eventId).baseVersion ?? e.version;
      }
      if (command == EventCommand.handle || command == EventCommand.verify) {
        _editor = null;
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(c.successMessage ?? '记录已更新')));
    WearScope.of(context).requestRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final note = c.draftFor(e.id).handleComment;
    if (_note.text != note) _note.text = note;
    final claim = c.can(EventCommand.claim);
    final handle = c.can(EventCommand.handle);
    final verify = c.can(EventCommand.verify);
    final contact = c.actor.isAdmin && e.deviceId.isNotEmpty;
    return PopScope(
      canPop: !c.writing,
      child: Scaffold(
        backgroundColor: WearColors.background,
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回事件列表',
            icon: const Icon(Icons.arrow_back),
            onPressed: c.writing ? null : widget.onBack,
          ),
          title: const Row(
            children: [
              WearRollingWordmark(height: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '事件详情',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: c.refreshFromSignal,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  _summary(),
                  if (_showLocation &&
                      e.locationLat.isNotEmpty &&
                      e.locationLng.isNotEmpty)
                    EventLocationCard(event: e, api: WearScope.of(context).api),
                  if (c.writing || c.detailLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (c.errorMessage case final message?) _notice(message),
                  if (c.conflictMessage case final message?) _notice(message),
                  if (!e.isPlatformComplete &&
                      (c.draftFor(e.id).baseVersion ?? _formBaseVersion) !=
                          e.version)
                    OutlinedButton(
                      onPressed: c.writing ? null : _loadLatestDraft,
                      child: const Text('载入最新草稿（替换当前填写）'),
                    ),
                  if (e.isPlatformComplete && _hasVerification)
                    _verificationResult(),
                  if (e.isSos &&
                      (!e.isPlatformComplete ||
                          e.assistance['state'] == 'ended' ||
                          (e.assistance['members'] as List? ?? []).isNotEmpty))
                    _assistanceCard(),
                  if (claim || verify || handle || contact)
                    WearCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (claim)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              child: FilledButton.icon(
                                key: const ValueKey('event-claim'),
                                onPressed: c.writing
                                    ? null
                                    : () => _run(EventCommand.claim),
                                icon: const Icon(Icons.assignment_ind_outlined),
                                label: const Text('认领并开始处理'),
                              ),
                            ),
                          if (verify) _formEntry(EventCommand.verify),
                          if (handle) _formEntry(EventCommand.handle),
                          if (contact)
                            ListTile(
                              leading: const Icon(Icons.call_outlined),
                              title: const Text('联系现场'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: c.writing ? null : widget.onCommunication,
                            ),
                        ],
                      ),
                    ),
                  if (!verify &&
                      const {
                        'open',
                        'field_pending',
                        'claimed',
                        'handling',
                      }.contains(e.status))
                    const Text('待值守人员核验', style: TextStyle(color: _muted)),
                  if (e.observations.isNotEmpty || c.actions.isNotEmpty)
                    _history(),
                  EventSubmittedPhotos(
                    key: ValueKey('event-media-${e.id}'),
                    eventId: e.id,
                    version: e.version,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadLatestDraft() async {
    await c.loadLatestDraft();
    if (!mounted || c.selected == null) return;
    setState(() {
      final draft = c.draftFor(e.id);
      _formBaseVersion = e.version;
      _formRevision++;
      _conclusion = draft.conclusion;
      _situation.text = draft.situation;
      _measures.text = draft.measures;
      _note.text = draft.handleComment;
    });
  }

  Widget _notice(String text) => Semantics(
    liveRegion: true,
    child: Text(text, style: const TextStyle(color: WearColors.danger)),
  );

  Widget _summary() {
    final hasCoordinates = e.locationLat.isNotEmpty && e.locationLng.isNotEmpty;
    final hasPoint = eventLocationPoint(e) != null;
    final source = e.source == 'manual_sos' ? '手机手动求助' : e.deviceTypeLabel;
    final description = e.alarmDescription.trim();
    return WearCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                e.isSos ? Icons.sos_rounded : Icons.warning_amber_rounded,
                color: levelColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.alarmLabel,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              WearBadge(text: e.severityLabel, color: levelColor),
              WearBadge(text: e.statusLabel),
              if (e.escalated)
                const WearBadge(text: '已升级', color: WearColors.danger),
              if (e.demo)
                const WearBadge(text: '演示事件', color: WearColors.muted),
            ],
          ),
          if (description.isNotEmpty && description != e.alarmLabel.trim()) ...[
            const SizedBox(height: 8),
            Text(description),
          ],
          const Divider(height: 20),
          _fact('发生时间', formatTime(e.occurredAt)),
          _fact(
            '相关人员',
            textOf(
              e.personName,
              textOf(e.personCode, textOf(e.personId, '未关联人员')),
            ),
          ),
          if (e.source == 'manual_sos' ||
              e.deviceType.isNotEmpty ||
              e.sn.isNotEmpty)
            _fact('报警来源', [source, if (e.sn.isNotEmpty) e.sn].join(' · ')),
          if (e.claimantName.isNotEmpty || e.claimantUserId.isNotEmpty)
            _fact('认领人', textOf(e.claimantName, e.claimantUserId)),
          if (hasCoordinates)
            Semantics(
              key: const ValueKey('event-position'),
              expanded: _showLocation,
              child: _fact(
                '事发位置',
                textOf(
                  e.locationDescription,
                  _showLocation
                      ? '收起定位详情'
                      : hasPoint
                      ? '查看地图'
                      : '查看定位详情',
                ),
                onTap: () => setState(() => _showLocation = !_showLocation),
              ),
            )
          else
            _fact('事发位置', textOf(e.locationDescription, '暂无有效定位')),
          if (worksEnabled && e.taskId.isNotEmpty)
            _fact(
              '关联作业',
              e.taskId,
              onTap: () =>
                  context.push('/tasks/${Uri.encodeComponent(e.taskId)}'),
            ),
        ],
      ),
    );
  }

  Widget _assistanceCard() {
    final memberCount = (e.assistance['members'] as List? ?? []).length;
    final state = const {
      'waiting': '等待接警',
      'accepted': '已接警',
      'active': '正在协助',
      'ended': '协助已结束',
    }[e.assistance['state']];
    return WearCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _heading('SOS 协助'),
              if (state != null) Text(state),
              if (memberCount > 0)
                Text('$memberCount 人参与', style: const TextStyle(color: _muted)),
            ],
          ),
          if (c.can(EventCommand.joinAssistance) ||
              c.can(EventCommand.endAssistance))
            Wrap(
              spacing: 8,
              children: [
                if (c.can(EventCommand.joinAssistance))
                  OutlinedButton.icon(
                    key: const ValueKey('sos-join'),
                    onPressed: c.writing
                        ? null
                        : () => _run(EventCommand.joinAssistance),
                    icon: const Icon(Icons.support_agent),
                    label: const Text('接警并加入协助'),
                  ),
                if (c.can(EventCommand.endAssistance))
                  TextButton(
                    key: const ValueKey('sos-end'),
                    onPressed: c.writing
                        ? null
                        : () => _run(EventCommand.endAssistance),
                    child: const Text('结束协助'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _formEntry(EventCommand command) {
    final verify = command == EventCommand.verify;
    final expanded = _editor == command;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: expanded,
          child: ListTile(
            key: ValueKey(
              verify ? 'event-open-verification' : 'event-open-observation',
            ),
            leading: Icon(
              verify ? Icons.fact_check_outlined : Icons.edit_note_outlined,
            ),
            title: Text(verify ? '填写核验' : '补充现场情况'),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: c.writing
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    setState(() => _editor = expanded ? null : command);
                  },
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: verify ? _verificationForm() : _observationForm(),
          ),
      ],
    );
  }

  Widget _photoInput() => EventPhotoCapture(
    paths: c.draftFor(e.id).photoPaths,
    enabled: !c.writing,
    onChanged: (paths) =>
        c.updateDraft(e.id, c.draftFor(e.id).copyWith(photoPaths: paths)),
  );

  Widget _observationForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      TextField(
        key: const ValueKey('event-observation'),
        controller: _note,
        enabled: !c.writing,
        minLines: 2,
        maxLines: 5,
        maxLength: 500,
        decoration: const InputDecoration(
          labelText: '现场情况',
          hintText: '记录看到的情况或需要的帮助',
        ),
        onChanged: (value) => c.updateDraft(
          e.id,
          c.draftFor(e.id).copyWith(handleComment: value),
        ),
      ),
      _photoInput(),
      FilledButton(
        key: const ValueKey('event-observation-submit'),
        onPressed: c.writing ? null : () => _run(EventCommand.handle),
        child: const Text('提交现场情况'),
      ),
    ],
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
  Widget _verificationForm() => Column(
    key: ValueKey(_formRevision),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      DropdownButtonFormField<String>(
        key: const ValueKey('verification-conclusion'),
        initialValue: _conclusion.isEmpty ? null : _conclusion,
        isExpanded: true,
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
      TextField(
        key: const ValueKey('verification-situation'),
        controller: _situation,
        enabled: !c.writing,
        minLines: 2,
        maxLines: 5,
        maxLength: 500,
        decoration: const InputDecoration(labelText: '现场情况 *'),
        onChanged: (_) => _rememberVerification(),
      ),
      TextField(
        key: const ValueKey('verification-measures'),
        controller: _measures,
        enabled: !c.writing,
        minLines: 1,
        maxLines: 4,
        maxLength: 500,
        decoration: const InputDecoration(labelText: '采取措施'),
        onChanged: (_) => _rememberVerification(),
      ),
      _photoInput(),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 4,
        children: [
          OutlinedButton(
            key: const ValueKey('verification-save'),
            onPressed: c.writing
                ? null
                : () => _run(EventCommand.saveVerification),
            child: const Text('保存核验草稿'),
          ),
          FilledButton(
            key: const ValueKey('verification-submit'),
            onPressed: c.writing ? null : () => _run(EventCommand.verify),
            child: const Text('提交最终核验'),
          ),
        ],
      ),
    ],
  );

  bool get _hasVerification =>
      const [
        'conclusion',
        'situation',
        'measures',
        'actor',
        'createdAt',
      ].any((key) => textOf(e.verification[key], '').isNotEmpty) ||
      (e.verification['photoIds'] as List? ?? []).isNotEmpty ||
      jsonList(e.verification['photos']).isNotEmpty;

  Widget _recordPhotos(JsonMap row) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!e.demo && (row['photoIds'] as List? ?? []).isNotEmpty)
        EventStoredPhotos(
          blobIds: (row['photoIds'] as List).map(idOf).toList(),
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
    ],
  );

  Widget _verificationResult() {
    final result = e.verification;
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('核验结果（只读）'),
          const SizedBox(height: 6),
          for (final field in const {
            'conclusion': '核验结论',
            'situation': '现场情况',
            'measures': '采取措施',
            'actor': '核验人',
          }.entries)
            if (textOf(result[field.key], '').isNotEmpty)
              _fact(field.value, textOf(result[field.key])),
          if (textOf(result['createdAt'], '').isNotEmpty)
            _fact('核验时间', formatTime(result['createdAt'])),
          _recordPhotos(result),
          if (externalLinked)
            const Text(
              '此处显示平台核验结果，外部结案状态请在作业系统查看。',
              style: TextStyle(color: _muted),
            ),
        ],
      ),
    );
  }

  Widget _history() => WearCard(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      key: const ValueKey('event-history'),
      leading: const Icon(Icons.history),
      title: const Text('处理记录'),
      shape: const Border(),
      collapsedShape: const Border(),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (e.observations.isNotEmpty) _heading('现场补充'),
        for (final record in e.observations)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (textOf(record['comment'], '').isNotEmpty)
                  Text(textOf(record['comment'])),
                _recordPhotos(record),
                Text(
                  [
                    if (textOf(record['actor'], '').isNotEmpty)
                      textOf(record['actor']),
                    if (textOf(record['createdAt'], '').isNotEmpty)
                      formatTime(record['createdAt']),
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
        if (e.observations.isNotEmpty && c.actions.isNotEmpty) const Divider(),
        if (c.actions.isNotEmpty) _heading('操作记录'),
        for (final action in c.actions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    action.label,
                    if (action.actor.isNotEmpty) action.actor,
                  ].join(' · '),
                ),
                if (action.reason.isNotEmpty &&
                    action.reason.trim() != action.label.trim())
                  Text(action.reason),
                if (action.createTime.isNotEmpty)
                  Text(
                    formatTime(action.createTime),
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
