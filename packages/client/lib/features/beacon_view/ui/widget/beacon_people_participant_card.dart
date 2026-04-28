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
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// One person row in the Beacon **People** tab (Phase 4).
class BeaconPeopleParticipantCard extends StatelessWidget {
  const BeaconPeopleParticipantCard({
    required this.beacon,
    required this.participant,
    required this.commitments,
    super.key,
  });

  final Beacon beacon;
  final BeaconParticipant participant;
  final List<TimelineCommitment> commitments;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onV = scheme.onSurfaceVariant;

    final titles = <String, String>{
      for (final c in commitments) c.user.id: c.user.title,
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
      Profile? fromCommit;
      for (final c in commitments) {
        if (c.user.id == participant.userId) {
          fromCommit = c.user;
          break;
        }
      }
      profile = fromCommit ?? Profile(id: participant.userId);
    }
    if (profile.title.isEmpty) {
      profile = profile.copyWith(title: name);
    }

    CoordinationResponseType? authorResponseForCommitted;
    for (final c in commitments) {
      if (!c.isWithdrawn && c.user.id == participant.userId) {
        authorResponseForCommitted = c.coordinationResponse;
        break;
      }
    }

    final statusLabel = _statusL10n(
      l10n,
      participant.status,
      authorResponseForCommitted,
    );
    final roleLabel = _roleL10n(l10n, participant.role);
    final next = participant.nextMoveText?.trim();
    final locale = Localizations.localeOf(context).toString();
    final when = DateFormat.yMMMd(locale).add_Hm().format(
          participant.updatedAt.toLocal(),
        );

    return TenturaTechCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TenturaAvatar(profile: profile),
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
    CoordinationResponseType? authorResponse,
  ) {
    if (status == BeaconParticipantStatusBits.committed && authorResponse != null) {
      return switch (authorResponse) {
        CoordinationResponseType.useful => l10n.beaconPeopleStatusCommittedUseful,
        CoordinationResponseType.needCoordination =>
          l10n.beaconPeopleStatusCommittedNeedCoordination,
        _ => l10n.beaconPeopleStatusCommitted,
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
      return l10n.beaconPeopleStatusCommitted;
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
