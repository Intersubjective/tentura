import 'package:flutter/material.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

/// Tiny overlapping forwarder avatars + optional `+N` (inbox / My Work surfaces).
class CompactForwarderAvatars extends StatelessWidget {
  const CompactForwarderAvatars({
    required this.profiles,
    this.overflowCount = 0,
    this.sizeBucket = TenturaAvatarSize.small,
    this.size,
    this.overlap = 6,
    this.starredProfileId,
    this.selfUserId,
    this.semanticsLabel,
    this.overflowBadgeFillColor,
    this.overflowBadgeTextColor,
    this.overflowRingColor,
    super.key,
  });

  final List<Profile> profiles;
  final int overflowCount;
  final TenturaAvatarSize sizeBucket;
  final double? size;
  final double overlap;
  final String? starredProfileId;
  final String? selfUserId;
  final String? semanticsLabel;
  final Color? overflowBadgeFillColor;
  final Color? overflowBadgeTextColor;
  final Color? overflowRingColor;

  @override
  Widget build(BuildContext context) {
    return OverlappingPeopleAvatars(
      profiles: profiles,
      overflowCount: overflowCount,
      sizeBucket: sizeBucket,
      size: size,
      overlap: overlap,
      starredProfileId: starredProfileId,
      selfUserId: selfUserId,
      semanticsLabel: semanticsLabel,
      overflowBadgeFillColor: overflowBadgeFillColor,
      overflowBadgeTextColor: overflowBadgeTextColor,
      overflowRingColor: overflowRingColor,
    );
  }
}
