import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import 'session.dart';

class WearColors {
  static const ink = SpringColors.textPrimaryLight;
  static const muted = SpringColors.textSecondaryLight;
  // Existing primary usages are foreground text/icons on light surfaces.
  static const primary = ink;
  static const brand = Color(0xFF2F7BFF);
  static const accent = brand;
  static const background = Color(0xFFEEF5FC);
  static const line = Color(0xFFE2E7F0);
  static const danger = Color(0xFFBA433C);
  static const warning = Color(0xFFD97706);
  static const online = Color(0xFF16A34A);
}

class WearRollingWordmark extends StatelessWidget {
  const WearRollingWordmark({super.key, this.height = 28});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size(height, height),
            painter: const _RollingMarkPainter(),
          ),
          SizedBox(width: height * 0.2),
          Text(
            'ROLLING',
            style: TextStyle(
              color: const Color(0xFF163A7A),
              fontSize: height * 0.7,
              fontWeight: FontWeight.w800,
              letterSpacing: height * 0.02,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _RollingMarkPainter extends CustomPainter {
  const _RollingMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final ring = Paint()
      ..color = WearColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fill = Paint()..color = WearColors.brand;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - stroke / 2;
    canvas.drawCircle(c, r, ring);
    canvas.drawCircle(c, r * 0.36, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class WearArt {
  static const _base = 'assets/field-brand/preview/';
  static const characterThumbsup = '${_base}character_thumbsup.jpg';
  static const characterPhone = '${_base}character_phone.jpg';
  static const commsHero = '${_base}comms_hero.jpg';
  static const eventsHero = '${_base}events_hero.jpg';
  static const mineHero = '${_base}mine_hero.jpg';
  static const characterWalkie = '${_base}character_walkie.jpg';
  static const characterClipboard = '${_base}character_clipboard.jpg';
  static const characterAvatar = '${_base}character_avatar.jpg';
  static const helmet = '${_base}helmet.jpg';
  static const belt = '${_base}belt.jpg';
  static const watch = '${_base}watch.jpg';
  static const loginStillLife = '${_base}login_stilllife.jpg';
  static const workScene = '${_base}work_scene.jpg';
  static const plantMap = '${_base}plant_map.jpg';
  static const videoPlaceholder = '${_base}video_placeholder.jpg';
  static const sitePhoto = '${_base}site_photo.jpg';
  static const skyHeader = '${_base}sky_header.jpg';
  static const slogan = '${_base}slogan.png';
  static const logoWordmark = '${_base}logo_wordmark.png';
  static const warningTriangle = '${_base}warning_triangle.jpg';
  static const sosBubble = '${_base}sos_bubble.jpg';

  static String equipment(Object? typeCode) => switch (typeCode?.toString()) {
    'helmet' => helmet,
    'belt' => belt,
    'watch' => watch,
    _ => helmet,
  };
}

class WearCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const WearCard({super.key, required this.child, this.padding});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
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

class WearAssetImage extends StatelessWidget {
  const WearAssetImage(
    this.asset, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.borderRadius,
  });

  final String asset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => ColoredBox(
        color: const Color(0xFFE8F1FF),
        child: SizedBox(width: width, height: height),
      ),
    );
    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}

class WearSiteSwitcher extends StatelessWidget {
  const WearSiteSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    return InkWell(
      onTap: session.busy || session.callActive.value
          ? null
          : () => context.go('/sites'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: Text(
              session.siteName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: WearColors.muted),
            ),
          ),
          const Icon(Icons.expand_more, size: 16, color: WearColors.muted),
        ],
      ),
    );
  }
}

class WearBrandHero extends StatelessWidget {
  const WearBrandHero({
    super.key,
    required this.title,
    this.subtitle,
    required this.background,
    this.alignment = const Alignment(0.18, 0),
    this.trailing,
    this.showSiteSwitcher = true,
    this.height = 188,
  });

  final String title;
  final String? subtitle;
  final String background;
  final Alignment alignment;
  final Widget? trailing;
  final bool showSiteSwitcher;
  final double height;

  @override
  Widget build(BuildContext context) {
    final right =
        trailing ?? (showSiteSwitcher ? const WearSiteSwitcher() : null);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WearAssetImage(
            background,
            fit: BoxFit.cover,
            alignment: alignment,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: WearRollingWordmark(height: 22),
                    ),
                    const Spacer(),
                    ?right,
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 118),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 28,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                color: WearColors.ink,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                subtitle!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: WearColors.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WearSkyHeader extends StatelessWidget {
  const WearSkyHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.art,
    this.artWidth = 132,
    this.artHeight = 132,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 8, 12),
  });

  final String title;
  final String? subtitle;
  final String? art;
  final double artWidth;
  final double artHeight;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          const Positioned.fill(
            child: WearAssetImage(
              WearArt.skyHeader,
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
          ),
          Padding(
            padding: padding,
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
                          fontSize: 26,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: WearColors.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
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
                if (art != null)
                  WearAssetImage(
                    art!,
                    width: artWidth,
                    height: artHeight,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomRight,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WearSectionTitle extends StatelessWidget {
  const WearSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: WearColors.brand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: WearColors.ink,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class WearStatusDot extends StatelessWidget {
  const WearStatusDot({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
