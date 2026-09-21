import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core.dart';
import '../events/event_models.dart';
import '../events/event_repository.dart';

/// One SOS opens its detail; multiple SOS events open the scoped list.
class HomeSosBanner extends StatefulWidget {
  const HomeSosBanner({super.key, required this.refreshVersion});
  final int refreshVersion;

  @override
  State<HomeSosBanner> createState() => _HomeSosBannerState();
}

class _HomeSosBannerState extends State<HomeSosBanner> {
  WearSession? _session;
  String? _scope;
  WearEvent? _event;
  int _request = 0;
  int _total = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session) || _scope != session.scopeKey) {
      _session = session;
      _scope = session.scopeKey;
      _event = null;
      _total = 0;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant HomeSosBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) _load();
  }

  Future<void> _load() async {
    final session = _session;
    if (session == null) return;
    final scope = session.scopeKey;
    final request = ++_request;
    try {
      // 'active' is mapped by the existing gateway to all non-closed statuses.
      final page = await ApiEventGateway(
        session.api,
      ).fetchPage(const EventFilters(type: 'sos', status: 'active'), 1, 1);
      if (!mounted || request != _request || scope != session.scopeKey) return;
      final rows = page.records.where(
        (e) => e.type == 'sos' && !e.isClosed && e.siteId == session.siteId,
      );
      setState(() {
        _event = rows.firstOrNull;
        _total = _event == null ? 0 : page.total;
      });
    } catch (_) {
      if (!mounted || request != _request || scope != session.scopeKey) return;
      // No invented emergency when the current scope cannot be verified.
      setState(() {
        _event = null;
        _total = 0;
      });
    }
  }

  Future<void> _open(WearEvent event) async {
    await context.push(
      _total > 1
          ? '/sos-events'
          : Uri(
              path: '/events',
              queryParameters: {'eventId': event.id},
            ).toString(),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    if (event == null || _scope != _session?.scopeKey) {
      return const SizedBox.shrink();
    }
    const red = Color(0xFFFF3C55);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        liveRegion: true,
        child: Material(
          color: const Color(0xFFFFF0F2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFFFB9C2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('home-sos-banner'),
            onTap: () => _open(event),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.priority_high_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.demo ? 'SOS 紧急求助 · 演示' : 'SOS 紧急求助',
                          style: const TextStyle(
                            color: red,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${event.personName.isEmpty ? '求助人员' : event.personName} · ${event.statusLabel}${_total > 1 ? ' · 共 $_total 条' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WearColors.muted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '查看',
                    style: TextStyle(
                      color: red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: red, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
