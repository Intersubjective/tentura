import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Admitted (+ candidate/offered for author/steward) participants for ask/blocker targets.
List<BeaconParticipant> participantsForCoordinationTargetPicker({
  required List<BeaconParticipant> participants,
  required String myUserId,
  required bool isAuthorOrSteward,
}) {
  return isAuthorOrSteward
      ? participants
          .where((p) =>
              p.roomAccess == RoomAccessBits.admitted ||
              p.status == BeaconParticipantStatusBits.candidate ||
              p.status == BeaconParticipantStatusBits.offeredHelp)
          .toList()
      : participants
          .where((p) => p.roomAccess == RoomAccessBits.admitted)
          .toList();
}

/// Sorted user ids for ask targets (author + participants).
List<String> askTargetUserIds({
  required String beaconAuthorId,
  required List<BeaconParticipant> participants,
}) {
  final ids = <String>{beaconAuthorId};
  for (final p in participants) {
    ids.add(p.userId);
  }
  return ids.toList()..sort();
}

/// Promise targets: admitted picker list excluding self.
List<BeaconParticipant> promiseTargetParticipants({
  required List<BeaconParticipant> participants,
  required String myUserId,
  required bool isAuthorOrSteward,
}) {
  return participantsForCoordinationTargetPicker(
    participants: participants,
    myUserId: myUserId,
    isAuthorOrSteward: isAuthorOrSteward,
  ).where((p) => p.userId != myUserId).toList();
}

String coordinationTargetLabel({
  required String userId,
  required List<BeaconParticipant> participants,
  required String viewerId,
  required L10n l10n,
}) {
  if (userId == viewerId) {
    return l10n.labelMe;
  }
  BeaconParticipant? match;
  for (final p in participants) {
    if (p.userId == userId) {
      match = p;
      break;
    }
  }
  final title = match?.userTitle.trim() ?? '';
  if (title.isNotEmpty) {
    return title;
  }
  final handle = match?.handle.trim() ?? '';
  if (handle.isNotEmpty) {
    return '@$handle';
  }
  return userId.length <= 16 ? userId : '${userId.substring(0, 14)}…';
}

String coordinationTargetPickerLabel(L10n l10n, CoordinationItemKind kind) {
  return switch (kind) {
    CoordinationItemKind.ask => l10n.beaconRoomNeedInfoPickTarget,
    CoordinationItemKind.promise => l10n.coordinationPromiseTargetPickerLabel,
    CoordinationItemKind.blocker => l10n.beaconRoomNeedInfoPickTarget,
    _ => l10n.beaconRoomNeedInfoPickTarget,
  };
}

String coordinationComposerSheetTitle(L10n l10n, CoordinationItemKind kind, bool isEdit) {
  if (isEdit) {
    return l10n.myWorkEditDraft;
  }
  return switch (kind) {
    CoordinationItemKind.ask => l10n.coordinationMarkAskTitle,
    CoordinationItemKind.promise => l10n.coordinationCreatePromiseAction,
    CoordinationItemKind.blocker => l10n.coordinationMarkBlockerTitle,
    _ => l10n.myWorkEditDraft,
  };
}
