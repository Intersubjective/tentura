import 'package:flutter/material.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';

/// Overlapping mini-avatars with circular `+N` overflow (inbox forwarders style).
///
/// Facepile layout: overlap grows right (LTR). Stack paint order (back → front):
/// rightmost face, …, leftmost face (primary slot foremost), self slot above
/// other profiles, then `+N` on top.
class OverlappingPeopleAvatars extends StatelessWidget {
  const OverlappingPeopleAvatars({
    required this.profiles,
    this.overflowCount = 0,
    this.sizeBucket = TenturaAvatarSize.small,
    this.size,
    this.overlap = 6,
    this.starredProfileId,
    this.selfUserId,
    this.overflowBadgeFillColor,
    this.overflowBadgeTextColor,
    this.overflowRingColor,
    this.semanticsLabel,
    super.key,
  });

  final List<Profile> profiles;
  final int overflowCount;
  final TenturaAvatarSize sizeBucket;
  final double? size;
  final double overlap;

  /// When set, the matching profile slot shows an author star badge.
  final String? starredProfileId;

  /// When set, the matching profile slot shows the self halo.
  final String? selfUserId;

  final Color? overflowBadgeFillColor;
  final Color? overflowBadgeTextColor;
  final Color? overflowRingColor;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ringColor = overflowRingColor ?? scheme.outlineVariant;
    final badgeFill = overflowBadgeFillColor ?? scheme.surfaceContainerHigh;
    final badgeFg = overflowBadgeTextColor ?? scheme.onSurfaceVariant;
    final avatarSize = size ?? TenturaAvatar.resolveSize(context, sizeBucket);

    final extraSlots = overflowCount > 0 ? 1 : 0;
    final n = profiles.length + extraSlots;
    if (n == 0) {
      return const SizedBox.shrink();
    }

    final step = avatarSize - overlap;
    final width = avatarSize + (n - 1) * step;
    final theme = Theme.of(context);
    final label = semanticsLabel ?? _defaultSemanticsLabel(
      profiles.length,
      overflowCount,
    );

    final selfIndex = selfUserId == null
        ? -1
        : profiles.indexWhere((p) => p.id == selfUserId);

    final stackChildren = <Widget>[
      for (var i = profiles.length - 1; i >= 0; i--)
        if (i != selfIndex)
          Positioned(
            left: i * step,
            child: _PeopleAvatarSlot(
              profile: profiles[i],
              sizeBucket: sizeBucket,
              size: size,
              showStar:
                  starredProfileId != null &&
                  profiles[i].id == starredProfileId,
              isSelf: false,
            ),
          ),
      if (selfIndex >= 0)
        Positioned(
          left: selfIndex * step,
          child: _PeopleAvatarSlot(
            profile: profiles[selfIndex],
            sizeBucket: sizeBucket,
            size: size,
            showStar:
                starredProfileId != null &&
                profiles[selfIndex].id == starredProfileId,
            isSelf: true,
          ),
        ),
      if (overflowCount > 0)
        Positioned(
          left: profiles.length * step,
          child: Container(
            width: avatarSize,
            height: avatarSize,
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
    ];

    return Semantics(
      container: true,
      label: label,
      child: SizedBox(
        width: width,
        height: avatarSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: stackChildren,
        ),
      ),
    );
  }

  static String _defaultSemanticsLabel(int visibleCount, int overflowCount) {
    final people = visibleCount == 1 ? '1 person' : '$visibleCount people';
    if (overflowCount <= 0) {
      return people;
    }
    return '$people, $overflowCount more';
  }
}

class _PeopleAvatarSlot extends StatelessWidget {
  const _PeopleAvatarSlot({
    required this.profile,
    required this.sizeBucket,
    required this.size,
    required this.showStar,
    required this.isSelf,
  });

  final Profile profile;
  final TenturaAvatarSize sizeBucket;
  final double? size;
  final bool showStar;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    return TenturaAvatar(
      profile: profile,
      sizeBucket: sizeBucket,
      size: size,
      showAuthorStar: showStar,
      isSelf: isSelf,
    );
  }
}
