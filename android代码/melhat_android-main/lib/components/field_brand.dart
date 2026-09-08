import 'tech_surface.dart';
import 'package:flutter/material.dart';

class FieldBrandMark extends StatelessWidget {
  const FieldBrandMark({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '智能分体式安全帽',
    image: true,
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .09),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * .26),
      ),
      child: Image.asset(
        'assets/field-brand/cargo-v2/logo.png',
        fit: BoxFit.contain,
        cacheWidth: 256,
        excludeFromSemantics: true,
      ),
    ),
  );
}

/// Decorative artwork never changes card sizing or captures business controls.
class FieldArtworkSurface extends StatelessWidget {
  const FieldArtworkSurface({
    super.key,
    required this.scene,
    required this.child,
    this.opacity = .75,
  });

  final String scene;
  final Widget child;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TechSurface(
      animated: true,
      radius: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: (dark ? opacity * .32 : opacity).clamp(0, 1),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/field-brand/cargo-v2/$scene.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.centerRight,
                          cacheWidth: 1024,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [surface, surface.withValues(alpha: 0)],
                              stops: const [.2, .85],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Dedicated transparent illustrations keep their complete silhouettes at small sizes.
class FieldSceneAccent extends StatelessWidget {
  const FieldSceneAccent({super.key, required this.scene, this.size = 64});

  final String scene;
  final double size;

  static const _toolImages = {
    'track-card': 'track-tool',
    'device-card': 'device-tool',
    'helmet-card': 'helmet-tool',
    'communication-card': 'communication-tool',
    'fence-card': 'fence-tool',
  };

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: _toolImages.containsKey(scene)
            ? Image.asset(
                'assets/field-brand/cargo-tools/${_toolImages[scene]}.png',
                fit: BoxFit.contain,
                cacheWidth: 384,
                errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(size * .22),
                child: OverflowBox(
                  alignment: Alignment.centerRight,
                  minWidth: size * 1.8,
                  maxWidth: size * 1.8,
                  minHeight: size,
                  maxHeight: size,
                  child: Image.asset(
                    'assets/field-brand/cargo-v2/$scene.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    cacheWidth: 384,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
      ),
    ),
  );
}

/// 业务页使用紧凑标题，给查询和真实数据让出首屏；品牌大图仅用于登录。
class FieldHero extends StatelessWidget {
  const FieldHero({
    super.key,
    required this.scene,
    required this.title,
    this.subtitle,
    this.dark = false,
    this.margin = const EdgeInsets.all(16),
  });
  final String scene;
  final String title;
  final String? subtitle;
  final bool dark;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: dark
          ? const EdgeInsets.all(14)
          : const EdgeInsets.symmetric(vertical: 4),
      decoration: dark
          ? BoxDecoration(
              color: const Color(0xFF202B46),
              borderRadius: BorderRadius.circular(16),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : scheme.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: dark ? const Color(0xFFD5E1EF) : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
