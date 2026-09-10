import 'package:flutter/material.dart';

class WearColors {
  static const ink = Color(0xFF16333F);
  static const muted = Color(0xFF657A84);
  static const primary = Color(0xFF008594);
  static const background = Color(0xFFF2F6F6);
  static const line = Color(0xFFDFE8EA);
  static const danger = Color(0xFFBA433C);
  static const warning = Color(0xFF946318);
}

class WearCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const WearCard({super.key, required this.child, this.padding});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: WearColors.line),
    ),
    child: child,
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
