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
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
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
      for (final c in helpOffers) c.user.id: c.user.displayName,
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
    if (profile.displayName.isEmpty) {
      profile = profile.copyWith(displayName: name);
    }

    CoordinationResponseType? authorResponseForHelpOffered;
    for (final c in helpOffers) {
      if (!c.isWithdrawn && c.user.id == participant.userId) {
        authorResponseForHelpOffered = c.coordinationResponse;
        break;
      }
    }

    final statusLabel = _statusL10n(
      l10n,
      participant.status,
      authorResponseForHelpOffered,
    );
    final roleLabel = _roleL10n(l10n, participant.role);
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
            child: TenturaAvatar(profile: profile),
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

  static String _roleL10n(L10n l10n, int role) {
    return switch (role) {
      BeaconParticipantRoleBits.author => l10n.beaconPeopleRoleAuthor,
      BeaconParticipantRoleBits.steward => l10n.beaconPeopleRoleSteward,
      BeaconParticipantRoleBits.helper => l10n.beaconPeopleRoleHelper,
      BeaconParticipantRoleBits.candidate => l10n.beaconPeopleRoleCandidate,
      BeaconParticipantRoleBits.watcher => l10n.beaconPeopleRoleWatcher,
      BeaconParticipantRoleBits.forwarder => l10n.beaconPeopleRoleForwarder,
      _ => l10n.beaconPeopleStatusUnknown(role),
    };
  }

  static String _statusL10n(
    L10n l10n,
    int status,
    CoordinationResponseType? authorResponseForOffered,
  ) {
    if (status == BeaconParticipantStatusBits.committed && authorResponseForOffered != null) {
      return switch (authorResponseForOffered) {
        CoordinationResponseType.useful => l10n.beaconPeopleStatusHelpOfferedUseful,
        CoordinationResponseType.needCoordination =>
          l10n.beaconPeopleStatusHelpOfferedNeedCoordination,
        _ => l10n.beaconPeopleStatusHelpOffered,
      };
    }
    if (status == BeaconParticipantStatusBits.watching) {
      return l10n.beaconPeopleStatusWatching;
    }
    if (status == BeaconParticipantStatusBits.offeredHelp) {
      return l10n.beaconPeopleStatusOfferedHelp;
    }
    if (status == BeaconParticipantStatusBits.candidate) {
      return l10n.beaconPeopleStatusCandidate;
    }
    if (status == BeaconParticipantStatusBits.admitted) {
      return l10n.beaconPeopleStatusAdmitted;
    }
    if (status == BeaconParticipantStatusBits.checking) {
      return l10n.beaconPeopleStatusChecking;
    }
    if (status == BeaconParticipantStatusBits.committed) {
      return l10n.beaconPeopleStatusHelpOffered;
    }
    if (status == BeaconParticipantStatusBits.needsInfo) {
      return l10n.beaconPeopleStatusNeedsInfo;
    }
    if (status == BeaconParticipantStatusBits.blocked) {
      return l10n.beaconPeopleStatusBlocked;
    }
    if (status == BeaconParticipantStatusBits.done) return l10n.beaconPeopleStatusDone;
    if (status == BeaconParticipantStatusBits.withdrawn) {
      return l10n.beaconPeopleStatusWithdrawn;
    }
    return l10n.beaconPeopleStatusUnknown(status);
  }
}
