import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';

/// Overlapping mini-avatars with circular `+N` overflow (inbox forwarders style).
///
/// Uses [TenturaAvatar] (initials when no photo). Optional [starredProfileId]
/// marks the author with a star badge. No self-highlight rings.
class OverlappingPeopleAvatars extends StatelessWidget {
  const OverlappingPeopleAvatars({
    required this.profiles,
    this.overflowCount = 0,
    this.size = 24,
    this.overlap = 6,
    this.starredProfileId,
    this.overflowBadgeFillColor,
    this.overflowBadgeTextColor,
    this.overflowRingColor,
    super.key,
  });

  final List<Profile> profiles;
  final int overflowCount;
  final double size;
  final double overlap;

  /// When set, the matching profile slot shows an author star badge.
  final String? starredProfileId;

  /// Optional overflow badge colors (provenance panel uses inverted contrast).
  final Color? overflowBadgeFillColor;
  final Color? overflowBadgeTextColor;
  final Color? overflowRingColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ringColor = overflowRingColor ?? scheme.outlineVariant;
    final badgeFill = overflowBadgeFillColor ?? scheme.surfaceContainerHigh;
    final badgeFg = overflowBadgeTextColor ?? scheme.onSurfaceVariant;

    final extraSlots = overflowCount > 0 ? 1 : 0;
    final n = profiles.length + extraSlots;
    if (n == 0) {
      return const SizedBox.shrink();
    }

    final step = size - overlap;
    final width = size + (n - 1) * step;
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < profiles.length; i++)
            Positioned(
              left: i * step,
              child: _PeopleAvatarSlot(
                profile: profiles[i],
                size: size,
                showStar: starredProfileId != null &&
                    profiles[i].id == starredProfileId,
              ),
            ),
          if (overflowCount > 0)
            Positioned(
              left: profiles.length * step,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeFill,
                  border: Border.all(color: ringColor),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflowCount',
                  style: theme.textTheme.labelMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: badgeFg,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PeopleAvatarSlot extends StatelessWidget {
  const _PeopleAvatarSlot({
    required this.profile,
    required this.size,
    required this.showStar,
  });

  final Profile profile;
  final double size;
  final bool showStar;

  @override
  Widget build(BuildContext context) {
    final avatar = TenturaAvatar(profile: profile, size: size);
    if (!showStar) {
      return avatar;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        ProfileAuthorStarBadge(avatarSize: size),
      ],
    );
  }
}

/// Bottom-right star badge for beacon author avatars (HUD, stacks, tiles).
class ProfileAuthorStarBadge extends StatelessWidget {
  const ProfileAuthorStarBadge({
    required this.avatarSize,
    super.key,
  });

  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final iconSize = avatarSize * 0.5;
    return Positioned(
      right: -2,
      bottom: -2,
      child: Icon(
        Icons.star_rounded,
        size: iconSize,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
