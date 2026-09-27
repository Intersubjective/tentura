import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';

import 'tentura_avatar.dart';

/// Capped overlapping mini-avatar row (face pile) with no overflow badge.
///
/// Renders at most [max] avatars from [profiles]; extra profiles are dropped
/// silently. Facepile layout: overlap grows right (LTR). Stack paint order
/// (back → front): rightmost face, …, leftmost face (primary slot foremost).
class TenturaAvatarStack extends StatelessWidget {
  const TenturaAvatarStack({
    required this.profiles,
    this.sizeBucket = TenturaAvatarSize.small,
    this.size,
    this.max = 3,
    this.overlap = 6,
    super.key,
  });

  final List<Profile> profiles;
  final TenturaAvatarSize sizeBucket;
  final double? size;
  final int max;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    final visible = profiles.take(max).toList(growable: false);
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }

    final avatarSize = size ?? TenturaAvatar.resolveSize(context, sizeBucket);
    final step = avatarSize - overlap;
    final width = avatarSize + (visible.length - 1) * step;

    return SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = visible.length - 1; i >= 0; i--)
            Positioned(
              left: i * step,
              child: TenturaAvatarStackRing(
                child: TenturaAvatar(
                  profile: visible[i],
                  sizeBucket: sizeBucket,
                  size: size,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
