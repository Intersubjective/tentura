import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/help_offer_end.dart';
import 'package:tentura/ui/l10n/l10n.dart';

String beaconPeopleRoleLabel(L10n l10n, int role) {
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

String beaconPeopleStatusLabel(
  L10n l10n,
  int status,
  CoordinationResponseType? authorResponseForOffered, {
  HelpOfferAdmissionAction? admissionAction,
}) {
  if (admissionAction == HelpOfferAdmissionAction.remove) {
    return l10n.beaconPeopleStatusRemovedFromChat;
  }
  if (status == BeaconParticipantStatusBits.committed &&
      authorResponseForOffered != null) {
    return switch (authorResponseForOffered) {
      // Accept stores `useful` as part of admission (#361): that is not the
      // author marking the offer useful; the card already says "Admitted".
      // Relies on accept writing `useful`; revisit if accept stops doing so.
      CoordinationResponseType.useful
          when admissionAction == HelpOfferAdmissionAction.accept =>
        l10n.beaconPeopleStatusHelpOffered,
      CoordinationResponseType.useful =>
        l10n.beaconPeopleStatusHelpOfferedUseful,
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
  if (status == BeaconParticipantStatusBits.done) {
    return l10n.beaconPeopleStatusDone;
  }
  if (status == BeaconParticipantStatusBits.withdrawn) {
    return l10n.beaconPeopleStatusWithdrawn;
  }
  return l10n.beaconPeopleStatusUnknown(status);
}

/// Participant status `withdrawn` is also what a stripped row looks like.
/// When the offer's end reason says otherwise, the role line follows that.
String beaconPeopleOfferStatusLine(
  L10n l10n, {
  required int status,
  required HelpOfferEndKind endKind,
  CoordinationResponseType? coordinationResponse,
  HelpOfferAdmissionAction? admissionAction,
}) {
  if (status == BeaconParticipantStatusBits.withdrawn &&
      (endKind == HelpOfferEndKind.participationEnded ||
          endKind == HelpOfferEndKind.declined)) {
    return helpOfferEndLabel(
      l10n,
      endKind,
      HelpOfferEndLabelSurface.peopleBadge,
    );
  }
  return beaconPeopleStatusLabel(
    l10n,
    status,
    coordinationResponse,
    admissionAction: admissionAction,
  );
}

/// People-card badge and the Forwards reaction use different words for a
/// real withdrawal («Withdrawn» / «Withdrew commitment»). Ended and declined
/// share one phrase on both surfaces.
enum HelpOfferEndLabelSurface { peopleBadge, forwardRow }

String helpOfferEndLabel(
  L10n l10n,
  HelpOfferEndKind kind,
  HelpOfferEndLabelSurface surface,
) {
  return switch (kind) {
    HelpOfferEndKind.withdrew => switch (surface) {
      HelpOfferEndLabelSurface.peopleBadge => l10n.labelWithdrawn,
      HelpOfferEndLabelSurface.forwardRow => l10n.forwardWithdrawn,
    },
    HelpOfferEndKind.participationEnded =>
      l10n.helpOfferParticipationEndedLabel,
    HelpOfferEndKind.declined => l10n.helpOfferStatusDeclined,
    HelpOfferEndKind.none => '',
  };
}

/// Participation stake label for help-offer tiles (P4 — keyed on [stakeState]).
String? helpOfferStakeParticipationLabel(
  L10n l10n,
  CommitmentStakeState stakeState,
) {
  return switch (stakeState) {
    CommitmentStakeState.released => l10n.helpOfferParticipationEndedLabel,
    CommitmentStakeState.exited => l10n.labelWithdrawn,
    CommitmentStakeState.softened => l10n.helpOfferAcknowledgementSoftenedLabel,
    CommitmentStakeState.acknowledged => l10n.beaconPeopleStatusHelpOffered,
    _ => null,
  };
}
