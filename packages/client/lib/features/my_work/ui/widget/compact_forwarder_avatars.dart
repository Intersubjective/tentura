import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

/// Tiny overlapping forwarder avatars + optional `+N` (inbox / My Work surfaces).
class CompactForwarderAvatars extends StatelessWidget {
  const CompactForwarderAvatars({
    required this.profiles,
    this.overflowCount = 0,
    this.size = 24,
    this.overlap = 6,
    super.key,
  });

  final List<Profile> profiles;
  final int overflowCount;
  final double size;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    return OverlappingPeopleAvatars(
      profiles: profiles,
      overflowCount: overflowCount,
      size: size,
      overlap: overlap,
    );
  }
}
