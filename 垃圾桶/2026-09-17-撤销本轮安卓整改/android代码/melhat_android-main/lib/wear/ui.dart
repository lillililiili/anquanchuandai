import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'session.dart';
import 'theme.dart';
export 'theme.dart';

/// Fixed semantic accents; foreground and surface colors come from Theme.
class WearColors {
  static const ink = Color(0xFF25231F);
  static const muted = Color(0xFF686154);
  static const primary = Color(0xFF245BC4);
  static const brand = Color(0xFF2F6FED);
  static const accent = brand;
  static const background = Color(0xFFF4F2ED);
  static const line = Color(0xFFD0CBC1);
  static const danger = Color(0xFFC05648);
  static const warning = Color(0xFFC4922A);
  static const online = Color(0xFF6B8A5C);
}

class WearRollingWordmark extends StatelessWidget {
  const WearRollingWordmark({super.key, this.height = 28});
  final double height;
  @override
  Widget build(BuildContext context) => Text(
    'ROLLING',
    style: TextStyle(
      fontSize: height * .85,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
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
  const WearCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
  );
}

class WearEmpty extends StatelessWidget {
  const WearEmpty({super.key, required this.title, this.detail, this.onRetry});
  final String title;
  final String? detail;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => WearCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.inbox_outlined,
          size: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              detail!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
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
  const WearBadge({super.key, required this.text, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class WearPageHeader extends StatelessWidget {
  const WearPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
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
                  fontSize: 24,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  final double? width, height;
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
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: SizedBox(width: width, height: height),
      ),
    );
    return borderRadius == null
        ? image
        : ClipRRect(borderRadius: borderRadius!, child: image);
  }
}

class WearSiteSwitcher extends StatelessWidget {
  const WearSiteSwitcher({super.key});
  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    return TextButton(
      onPressed: session.busy || session.callActive.value
          ? null
          : () {
              final path = GoRouterState.of(context).uri.path;
              final from = path.startsWith('/me')
                  ? '/me'
                  : path.startsWith('/events')
                  ? '/events'
                  : '/communications';
              context.push('/sites?returnTo=${Uri.encodeComponent(from)}');
            },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              session.siteName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }
}

/// The generated pair has identical architecture/composition across themes.
class WearPageBackground extends StatelessWidget {
  const WearPageBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 160,
        child: WearAssetImage(
          WearThemes.background(context),
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
        ),
      ),
      child,
    ],
  );
}

class WearBrandHero extends StatelessWidget {
  const WearBrandHero({
    super.key,
    required this.title,
    this.subtitle,
    required this.background,
    this.alignment = Alignment.centerRight,
    this.trailing,
    this.showSiteSwitcher = true,
    this.height = 116,
  });
  final String title;
  final String? subtitle;
  final String background;
  final Alignment alignment;
  final Widget? trailing;
  final bool showSiteSwitcher;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 108),
    decoration: BoxDecoration(
      image: DecorationImage(
        image: AssetImage(WearThemes.background(context)),
        fit: BoxFit.cover,
        alignment: Alignment.centerRight,
        opacity: .8,
        onError: (_, _) {},
      ),
    ),
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
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
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class WearSkyHeader extends StatelessWidget {
  const WearSkyHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.art,
    this.artWidth = 132,
    this.artHeight = 132,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });
  final String title;
  final String? subtitle, art;
  final double artWidth, artHeight;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => WearBrandHero(
    title: title,
    subtitle: subtitle,
    background: '',
    trailing: trailing,
  );
}

class WearSectionTitle extends StatelessWidget {
  const WearSectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class WearStatusDot extends StatelessWidget {
  const WearStatusDot({super.key, required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
          ),
        ),
      ),
    ],
  );
}
