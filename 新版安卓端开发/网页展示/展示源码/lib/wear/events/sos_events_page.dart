import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import 'event_models.dart';
import 'event_repository.dart';

/// Home's emergency collection is independent of the message workspace filters.
class SosEventsPage extends StatefulWidget {
  const SosEventsPage({super.key});

  @override
  State<SosEventsPage> createState() => _SosEventsPageState();
}

class _SosEventsPageState extends State<SosEventsPage> {
  WearSession? _session;
  String? _scope;
  List<WearEvent> _events = [];
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (identical(session, _session) && _scope == session.scopeKey) return;
    _session?.refreshTick.removeListener(_onSignal);
    _session = session;
    _scope = session.scopeKey;
    _events = [];
    session.refreshTick.addListener(_onSignal);
    unawaited(_reload());
  }

  void _onSignal() => unawaited(_reload());

  Future<void> _reload() async {
    final session = _session!;
    final scope = session.scopeKey;
    final request = ++_request;
    bool current() =>
        mounted && request == _request && scope == session.scopeKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gateway = ApiEventGateway(session.api);
      final events = <String, WearEvent>{};
      // Load all server pages into one scrollable collection, with no page buttons.
      for (var number = 1; ; number++) {
        final page = await gateway.fetchPage(
          const EventFilters(type: 'sos', status: 'active'),
          number,
          50,
        );
        if (!current()) return;
        for (final event in page.records) {
          if (event.type == 'sos' &&
              !event.isClosed &&
              event.siteId == session.siteId) {
            events[event.id] = event;
          }
        }
        if (page.records.isEmpty || page.current * page.size >= page.total) {
          break;
        }
        if (page.current < number || page.size <= 0) {
          throw const FormatException('事件列表加载不完整，请刷新重试');
        }
      }
      if (current()) setState(() => _events = events.values.toList());
    } catch (_) {
      if (current()) setState(() => _error = '紧急求助列表暂未更新，请重试');
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _open(WearEvent event) async {
    await context.push(
      Uri(path: '/events', queryParameters: {'eventId': event.id}).toString(),
    );
    if (mounted) await _reload();
  }

  @override
  void dispose() {
    _session?.refreshTick.removeListener(_onSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFEEF8FF),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          key: const ValueKey('sos-events-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_rounded,
                    color: WearColors.danger,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loading ? '正在更新紧急求助…' : '未关闭求助 · 共 ${_events.length} 条',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: WearColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              WearEmpty(title: _error!, onRetry: _reload)
            else if (!_loading && _events.isEmpty)
              WearEmpty(
                title: '暂无未关闭的紧急求助',
                detail: '求助处理完成后将从这里移除。',
                onRetry: _reload,
              ),
            for (final event in _events) _card(event),
            if (!_loading && _error == null && _events.isNotEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '已显示全部紧急求助',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: WearColors.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _header() => SizedBox(
    height: WearHeaderLayout.height(context),
    child: Stack(
      children: [
        const Positioned.fill(
          child: WearAssetImage(
            'assets/field-brand/preview/sos_reference_hero.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        Positioned(
          top: 3,
          left: 0,
          right: 12,
          child: Row(
            children: [
              IconButton(
                tooltip: '返回首页',
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/workbench'),
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 22,
                  color: WearColors.ink,
                ),
              ),
              const WearRollingWordmark(height: 23),
            ],
          ),
        ),
        const Positioned(
          left: 18,
          top: 60,
          right: 135,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '紧急求助列表',
                style: TextStyle(
                  fontSize: WearHeaderLayout.titleSize,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: WearColors.ink,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '当前厂站 · 未关闭的紧急求助',
                style: TextStyle(
                  fontSize: WearHeaderLayout.subtitleSize,
                  height: 1.35,
                  color: WearColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _card(WearEvent event) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: WearCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('sos-event-${event.id}'),
        borderRadius: BorderRadius.circular(22),
        onTap: () => _open(event),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: WearColors.danger.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.error_rounded,
                  color: WearColors.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.personName.isEmpty ? '求助人员' : event.personName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: WearColors.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'SOS 求助 · ${event.sn.isEmpty ? '设备未知' : event.sn}',
                      style: const TextStyle(color: WearColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        WearBadge(
                          text: event.statusLabel,
                          color: WearColors.danger,
                        ),
                        if (event.escalated)
                          const WearBadge(
                            text: '已升级',
                            color: WearColors.danger,
                          ),
                        if (event.demo)
                          const WearBadge(
                            text: '演示',
                            color: WearColors.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      formatTime(event.occurredAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: WearColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: WearColors.muted),
            ],
          ),
        ),
      ),
    ),
  );
}
