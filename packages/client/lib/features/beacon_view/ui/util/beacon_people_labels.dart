import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
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
  CoordinationResponseType? authorResponseForOffered,
) {
  if (status == BeaconParticipantStatusBits.committed &&
      authorResponseForOffered != null) {
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
  if (status == BeaconParticipantStatusBits.done) {
    return l10n.beaconPeopleStatusDone;
  }
  if (status == BeaconParticipantStatusBits.withdrawn) {
    return l10n.beaconPeopleStatusWithdrawn;
  }
  return l10n.beaconPeopleStatusUnknown(status);
}
