import 'tech_surface.dart';
import 'field_motion.dart';
import 'package:flutter/material.dart';
import '../field/field_data.dart';

/// Read-only visual summary. Device filters are supplied by FieldHomePage.
class FieldDeviceOverview extends StatelessWidget {
  const FieldDeviceOverview({
    super.key,
    required this.online,
    required this.total,
    required this.offline,
    required this.low,
    required this.waiting,
    required this.onOnline,
    required this.onOffline,
    required this.onLow,
  });
  final int online, total, offline, low;
  final bool waiting;
  final VoidCallback onOnline, onOffline, onLow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TechSurface(
      animated: true,
      radius: 22,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/field-brand/devices-scene.webp',
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.surface,
                            scheme.surface.withValues(alpha: .92),
                            scheme.surface.withValues(alpha: .08),
                          ],
                          stops: const [0, .35, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '智能安全帽 · 设备概览',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: waiting ? null : onOnline,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MotionSwap(
                              value: '$waiting/$online/$total',
                              child: Text(
                                waiting ? '—' : '$online / $total',
                                style: TextStyle(
                                  fontSize: 28,
                                  height: 1.15,
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.wifi_rounded,
                                  size: 14,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '在线设备',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_outward, size: 15),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Row(
              children: [
                Expanded(
                  child: _status(
                    context,
                    '离线设备',
                    offline,
                    Icons.wifi_off_rounded,
                    onOffline,
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: VerticalDivider(
                    width: 1,
                    color: scheme.outlineVariant,
                  ),
                ),
                Expanded(
                  child: _status(
                    context,
                    '低电量',
                    low,
                    Icons.battery_alert_outlined,
                    onLow,
                    warning: low > 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _status(
    BuildContext context,
    String title,
    int count,
    IconData icon,
    VoidCallback onTap, {
    bool warning = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: waiting ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Icon(
              icon,
              size: 16,
              color: warning ? Colors.deepOrange : scheme.onSurfaceVariant,
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            Text(
              waiting ? '—' : '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: warning ? Colors.deepOrange : scheme.onSurface,
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Compact priority strip keeps urgent work close to the equipment summary.
class FieldPriorityCard extends StatelessWidget {
  const FieldPriorityCard({
    super.key,
    required this.count,
    required this.waiting,
    required this.partial,
    required this.onTap,
  });
  final int count;
  final bool waiting, partial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: waiting ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: (count > 0 ? Colors.deepOrange : scheme.primary)
                      .withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  size: 21,
                  color: count > 0 ? Colors.deepOrange : scheme.onSurface,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      waiting ? '正在加载…' : '$count 条待处理告警',
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      partial ? '已加载待办 · 下拉重试' : '及时核查现场，跟进人员安全',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class FieldEventCard extends StatelessWidget {
  const FieldEventCard({super.key, required this.event, required this.onTap});
  final FieldEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent = event.type == 'sos';
    final accent = urgent ? scheme.error : Colors.deepOrange;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TechSurface(
      radius: 16,
      child: Card(
        margin: const EdgeInsets.only(bottom: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: urgent
                ? accent.withValues(alpha: .4)
                : scheme.outlineVariant,
            width: .7,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: dark ? .2 : .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    event.isFence
                        ? Icons.shield_outlined
                        : Icons.notifications_active_outlined,
                    size: 20,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: TextStyle(
                          color: urgent ? scheme.error : scheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${event.userName.isEmpty ? '未关联人员' : event.userName} · ${event.hatNumber}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (event.time.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          event.time,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
