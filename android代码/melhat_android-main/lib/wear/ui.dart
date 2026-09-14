import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class WearColors {
  static const ink = SpringColors.textPrimaryLight;
  static const muted = SpringColors.textSecondaryLight;
  // Existing primary usages are foreground text/icons on light surfaces.
  // Bright cyan belongs to action backgrounds, with navy foreground text.
  static const primary = ink;
  static const accent = SpringColors.mintGreen;
  static const background = SpringColors.backgroundLight;
  static const line = Color(0xFFE2E7F0);
  static const danger = Color(0xFFBA433C);
  static const warning = Color(0xFF946318);
}

class WearCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const WearCard({super.key, required this.child, this.padding});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: WearColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding ?? const EdgeInsets.all(18), child: child),
  );
}

class WearEmpty extends StatelessWidget {
  final String title;
  final String? detail;
  final VoidCallback? onRetry;
  const WearEmpty({super.key, required this.title, this.detail, this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inbox_outlined, size: 40, color: WearColors.muted),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: WearColors.ink,
          ),
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              detail!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WearColors.muted),
            ),
          ),
        if (onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
      ],
    ),
  );
}

class WearBadge extends StatelessWidget {
  final String text;
  final Color? color;
  const WearBadge({super.key, required this.text, this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: (color ?? WearColors.primary).withValues(alpha: .08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color ?? WearColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class WearPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const WearPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 25,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                  color: WearColors.ink,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      color: WearColors.muted,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
