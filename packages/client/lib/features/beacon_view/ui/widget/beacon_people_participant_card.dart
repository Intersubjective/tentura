import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_people_lens.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_people_labels.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

/// One person row in the Beacon **People** tab (Phase 4).
class BeaconPeopleParticipantCard extends StatelessWidget {
  const BeaconPeopleParticipantCard({
    required this.beacon,
    required this.participant,
    required this.helpOffers,
    super.key,
  });

  final Beacon beacon;
  final BeaconParticipant participant;
  final List<TimelineHelpOffer> helpOffers;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onV = scheme.onSurfaceVariant;

    final titles = <String, String>{
      for (final c in helpOffers) c.user.id: c.user.shownName,
    };
    final name = participantDisplayTitle(
      participant: participant,
      beacon: beacon,
      userIdToKnownTitle: titles,
    );

    Profile profile;
    if (participant.userId == beacon.author.id) {
      profile = beacon.author;
    } else {
      Profile? fromHelpOffer;
      for (final c in helpOffers) {
        if (c.user.id == participant.userId) {
          fromHelpOffer = c.user;
          break;
        }
      }
      profile = fromHelpOffer ?? Profile(id: participant.userId);
    }
    if (profile.shownName.isEmpty) {
      profile = profile.copyWith(displayName: name);
    }

    CoordinationResponseType? authorResponseForHelpOffered;
    for (final c in helpOffers) {
      if (!c.isWithdrawn && c.user.id == participant.userId) {
        authorResponseForHelpOffered = c.coordinationResponse;
        break;
      }
    }

    final statusLabel = beaconPeopleStatusLabel(
      l10n,
      participant.status,
      authorResponseForHelpOffered,
    );
    final roleLabel = beaconPeopleRoleLabel(l10n, participant.role);
    final next = participant.nextMoveText?.trim();
    final locale = Localizations.localeOf(context).toString();
    final when = DateFormat.yMMMd(locale).add_Hm().format(
          participant.updatedAt.toLocal(),
        );

    // Forward-path button is shown for any active help offerer (status ==
    // committed and not withdrawn) who is NOT the beacon author. Visible
    // to everyone who can render the People tab — the server-side auth
    // gate (BeaconHelpOffererForwardPathCase) still requires the viewer to
    // be involved (author / has-edge / has-help-offer).
    final showForwardPathButton =
        participant.status == BeaconParticipantStatusBits.committed &&
            participant.userId != beacon.author.id;

    return TenturaTechCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              final myId = context.read<ProfileCubit>().state.profile.id;
              if (participant.userId == myId) return;
              context.read<ScreenCubit>().showProfile(participant.userId);
            },
            child: SelfAwareAvatar.medium(profile: profile),
          ),
          const SizedBox(width: kSpacingSmall),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name,
                  style: TenturaText.body(scheme.onSurface),
                ),
                const SizedBox(height: kSpacingSmall / 2),
                Text(
                  '$roleLabel · $statusLabel',
                  style: TenturaText.status(onV),
                ),
                if (next != null && next.isNotEmpty) ...[
                  const SizedBox(height: kSpacingSmall / 2),
                  Text(
                    next,
                    style: TenturaText.bodySmall(scheme.onSurface),
                  ),
                ],
                const SizedBox(height: kSpacingSmall / 2),
                Text(
                  l10n.beaconPeopleParticipantUpdated(when),
                  style: TenturaText.status(onV),
                ),
              ],
            ),
          ),
          if (showForwardPathButton)
            IconButton(
              icon: const Icon(TenturaIcons.graph),
              tooltip: l10n.helpOffererForwardPathTooltip,
              onPressed: () =>
                  context.read<ScreenCubit>().showHelpOffererForwardPathFor(
                        beaconId: beacon.id,
                        helpOffererId: participant.userId,
                        helpOffererName: name,
                      ),
            ),
        ],
      ),
    );
  }
}
