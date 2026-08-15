import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_involved_profiles.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

/// Overlapping mini-avatars for author + active help-offerers (HUD strip / General card).
class BeaconInvolvedPeopleFacePile extends StatelessWidget {
  const BeaconInvolvedPeopleFacePile({
    required this.beacon,
    required this.involvedProfiles,
    required this.currentUserId,
    this.onTap,
    super.key,
  });

  final Beacon beacon;
  final List<Profile> involvedProfiles;
  final String currentUserId;
  final VoidCallback? onTap;

  static bool hasVisibleProfiles({
    required Beacon beacon,
    required List<Profile> involvedProfiles,
  }) {
    final display = beaconInvolvedPeopleDisplay(
      author: beacon.author,
      helpOfferUsers: involvedProfiles,
      helpOfferCount: involvedProfiles.length,
    );
    return display.visible.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final metaAvatar = context.tt.metadataAvatarSize;
    final display = beaconInvolvedPeopleDisplay(
      author: beacon.author,
      helpOfferUsers: involvedProfiles,
      helpOfferCount: involvedProfiles.length,
    );
    if (display.visible.isEmpty) {
      return const SizedBox.shrink();
    }
    final child = OverlappingPeopleAvatars(
      profiles: display.visible,
      overflowCount: display.overflow,
      size: metaAvatar,
      starredProfileId: beacon.author.id,
      selfUserId: currentUserId,
      semanticsLabel: l10n.facepileSemantics(
        display.visible.length,
        display.overflow,
      ),
    );

    if (onTap == null) return child;
    final radius = BorderRadius.circular(TenturaRadii.cardDense);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: child,
    );
  }
}
