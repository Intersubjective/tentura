import 'package:blurhash_shader/blurhash_shader.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

/// Circular avatar without MeritRank arcs or eye overlay.
///
/// Optional [overlay] is drawn in the bottom-right (same region as [AvatarRated]'s
/// eye), inside a small circular badge for contrast.
class PlainMiniAvatar extends StatelessWidget {
  const PlainMiniAvatar({
    required this.profile,
    this.size = AvatarRated.sizeSmall,
    this.overlay,
    this.boxFit = BoxFit.cover,
    super.key,
  });

  final Profile profile;
  final double size;
  final Widget? overlay;
  final BoxFit boxFit;

  int get _cacheSize => size.ceil();

  @override
  Widget build(BuildContext context) {
    final avatar = ClipOval(
      child: profile.hasNoAvatar
          ? AvatarRated.getAvatarPlaceholder(
              cacheHeight: _cacheSize,
              cacheWidth: _cacheSize,
              fit: boxFit,
            )
          : profile.image?.blurHash.isEmpty ?? true
          ? _imageNetwork
          : BlurHash(
              profile.image!.blurHash,
              child: _imageNetwork,
            ),
    );

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          if (overlay != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: _OverlayBadge(
                size: size,
                child: overlay!,
              ),
            ),
        ],
      ),
    );
  }

  Widget get _imageNetwork => Image.network(
    profile.avatarUrl,
    errorBuilder: (_, _, _) => AvatarRated.getAvatarPlaceholder(
      cacheHeight: _cacheSize,
      cacheWidth: _cacheSize,
      fit: boxFit,
    ),
    cacheHeight: _cacheSize,
    cacheWidth: _cacheSize,
    fit: boxFit,
  );
}

class _OverlayBadge extends StatelessWidget {
  const _OverlayBadge({
    required this.size,
    required this.child,
  });

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeSize = size * 0.44;
    final iconSize = size * 0.26;
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: scheme.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.outlineVariant,
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: IconTheme.merge(
          data: IconThemeData(size: iconSize),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: child,
          ),
        ),
      ),
    );
  }
}
