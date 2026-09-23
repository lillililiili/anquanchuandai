import 'dart:async';
import 'package:flutter/material.dart';
import '../core.dart';
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
  late final TextEditingController _note = TextEditingController(
    text: widget.controller
        .draftFor(widget.controller.selected!.id)
        .handleComment,
  );
  bool _demoJoined = false;
  final _legacyAnchor = GlobalKey();
  final _formAnchor = GlobalKey();
  final _legacyController = ExpansibleController();
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
    _legacyController.dispose();
    super.dispose();
  }

  String known(String value, [String fallback = '未关联']) =>
      value.isEmpty ? fallback : value;
  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
                        if (c.detailLoading || c.writing)
                          const LinearProgressIndicator(minHeight: 2),
                        if (c.errorMessage != null) _notice(c.errorMessage!),
                        if (c.conflictMessage != null)
                          _notice('${c.conflictMessage!}；草稿已保留，请核对最新状态'),
                        if (c.successMessage != null)
                          _notice(c.successMessage!),
                        _summary(),
                        if (e.source == 'manual_sos') ...[
                          gap(),
                          card(
                            Text(
                              e.isClosed
                                  ? '手动 SOS 已结束，可查看审批记录。'
                                  : '手动 SOS 已提交 → 管理员审批 → 结束\n无需一级审查，等待管理员审批。',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                              ),
                            ),
                          ),
                        ],
                        if (c.can(EventCommand.confirm) ||
                            c.can(EventCommand.close))
                          gap(),
                        if (c.can(EventCommand.confirm))
                          FilledButton.icon(
                            key: const ValueKey('event-confirm-reminder'),
                            onPressed: c.writing ? null : widget.onConfirm,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('收到'),
                          ),
                        if (c.can(EventCommand.close))
                          FilledButton.icon(
                            onPressed: c.writing ? null : widget.onReview,
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('审批通过并结束'),
                          ),
                        if (!e.isWarning && !c.can(EventCommand.handle)) ...[
                          gap(),
                          card(
                            EventSubmittedPhotos(
                              key: ValueKey('event-media-${e.id}'),
                              eventId: e.id,
                              version: e.version,
                            ),
                          ),
                        ],
                        if (!c.can(EventCommand.handle) &&
                            _handleFeedback != null) ...[
                          gap(),
                          card(
                            Text(
                              _handleFeedback!,
                              key: ValueKey('event-handle-feedback-${e.id}'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                              ),
                            ),
                          ),
                        ],
                        gap(),
                        if (!e.isWarning) EventLocationCard(event: e),
                        gap(),
                        if (!e.isWarning && c.can(EventCommand.handle))
                          ..._assessment(),
                        gap(),
                        if (!e.isWarning && c.actor.isAdmin) _communication(),
                        gap(),
                        card(
                          Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              controller: _legacyController,
                              expansionAnimationStyle:
                                  AnimationStyle.noAnimation,
                              key: const ValueKey('event-original-actions'),
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                '事件记录',
                                style: TextStyle(fontSize: 13, color: _muted),
                              ),
                              subtitle: Text(
                                e.isWarning ? '查看本人确认记录' : '处理说明、关联与时间线',
                                style: TextStyle(fontSize: 10, color: _muted),
                              ),
                              children: [
                                Container(
                                  key: _legacyAnchor,
                                  child: widget.legacyDetail,
                                ),
                              ],
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
                text:
                    '${e.severityLabel} · ${e.isWarning
                        ? '本人确认'
                        : e.source == 'manual_sos'
                        ? '管理员审批'
                        : e.isEmergency
                        ? '两级处置'
                        : '现场处理'}',
                color: e.isEmergency
                    ? _red
                    : e.isWarning
                    ? WearColors.online
                    : _amber,
              ),
              const SizedBox(height: 6),
              Text(
                e.isWarning ? '查看提醒 · 收到结束' : '定位现场 · 协同处置',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _summary() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            iconCircle(
              sos ? Icons.sos : Icons.warning_amber_rounded,
              color: levelColor,
              size: 42,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.alarmLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '事件 #${e.id}',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            WearBadge(
              text: e.statusFor(admin: c.actor.isAdmin),
              color: e.isClosed ? WearColors.online : levelColor,
            ),
          ],
        ),
        line(),
        infoRow(
          Icons.person_outline,
          known(e.personName, '人员未知'),
          '${e.deviceTypeLabel} ${known(e.sn, '未知')} · ${e.taskId.isEmpty ? '未关联作业' : '关联作业 ${e.taskId}'}',
        ),
        infoRow(Icons.schedule, '事件发生时间', formatTime(e.occurredAt)),
        line(),
        const Text(
          '告警描述',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          e.descriptionLabel,
          style: const TextStyle(fontSize: 12, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 5),
        if (!e.isWarning)
          const Text(
            '告警需现场核验，不直接判定违规',
            style: TextStyle(fontSize: 10, color: _muted),
          ),
      ],
    ),
  );

  List<Widget> _assessment() => [
    card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(key: _formAnchor, child: heading('上报异常原因')),
          const SizedBox(height: 4),
          const Text(
            '异常原因说明（选填）',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
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
              hintText: '请说明为什么发生本次异常，以及现场实际情况',
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
                    if (mounted) message('说明与附件草稿已保存在本机');
                  },
            child: const Text('保存草稿'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            key: ValueKey('event-handle-submit-${e.id}'),
            style: button(),
            onPressed:
                c.writing ||
                    !c.can(EventCommand.handle) ||
                    c.isHandleCommentSubmitted(e.id)
                ? null
                : widget.onSubmit,
            child: Text(
              c.writing
                  ? '提交中…'
                  : c.isHandleCommentSubmitted(e.id)
                  ? '已上报'
                  : e.isEmergency
                  ? '提交待审批'
                  : '提交并结束',
            ),
          ),
        ),
      ],
    ),
    if (_handleFeedback case final feedback?)
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: card(
          Text(
            feedback,
            key: ValueKey('event-handle-feedback-${e.id}'),
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ),
      ),
    if (!c.can(EventCommand.handle))
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          '本次处理已完成，可查看上报记录。',
          style: const TextStyle(fontSize: 10, color: _muted),
        ),
      ),
    Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, color: _muted, size: 18),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              e.isEmergency ? '现场上报 → 管理员审批 → 结束' : '说明和附件均可不填，提交成功后事件自动结束',
              style: TextStyle(fontSize: 10, color: _muted),
            ),
          ),
        ],
      ),
    ),
  ];
  String? get _handleFeedback {
    if (c.conflictMessage != null) {
      return '${c.conflictMessage}；填写内容已保留，请核对最新状态后重试。';
    }
    final submitted = c.isHandleCommentSubmitted(e.id);
    if (c.errorMessage != null) {
      return submitted
          ? '核验已提交，内容已保存；最新数据刷新失败：${c.errorMessage}。请稍后刷新，勿重复提交。'
          : '${c.errorMessage}；填写内容已保留。';
    }
    if (!submitted) return null;
    if (e.status == 'pending_review') {
      return '现场记录已保存，等待管理员审批，当前事件尚未结束。';
    }
    if (e.status == 'closed') return '核验内容已保存，事件已关闭。';
    if (c.can(EventCommand.close)) {
      return '核验已提交，内容已保存。确认处置完成后，可在“更多处置与记录”中关闭事件；修改说明后可补充提交。';
    }
    return '核验已提交，内容已保存。当前状态：${e.statusFor(admin: c.actor.isAdmin)}。';
  }

  Widget _attachmentCard() => card(
    EventPhotoCapture(
      key: ValueKey('event-evidence-${e.id}'),
      paths: c.draftFor(e.id).photoPaths,
      enabled: !c.writing,
      onChanged: (paths) => unawaited(
        c.updateDraft(e.id, c.draftFor(e.id).copyWith(photoPaths: paths)),
      ),
    ),
  );

  Widget _communication() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('通信与协助'),
        const SizedBox(height: 6),
        const Text(
          '联系现场人员，核实情况并协同处置',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('event-communication'),
          style: outline(),
          onPressed: c.writing ? null : widget.onCommunication,
          icon: const Icon(Icons.call_outlined, size: 20),
          label: const Text('联系现场'),
        ),
        if (sos) ...[
          line(),
          infoRow(
            Icons.people_outline,
            '协助组：待接入',
            _demoJoined ? '本地演示已加入 · 未建立实际会话' : '暂无已接入的协助组信息',
            onTap: _assist,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: c.writing ? null : _assist,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: Text(_demoJoined ? '已加入（示例）' : '加入协助'),
              ),
              OutlinedButton.icon(
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
                icon: const Icon(Icons.call_end, size: 18),
                label: const Text('结束协助'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '帽端长按 SOS 3 秒退出：硬件行为待联调。',
            style: TextStyle(fontSize: 10, color: _muted),
          ),
        ],
      ],
    ),
  );
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
