import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_people_row.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';

/// Room participant rows filtered for the Beacon view **People** lens (Phase 4).
///
/// Server only returns [participants] when the viewer may use the room API;
/// when the list is empty / unavailable this returns an empty list.
List<BeaconParticipant> beaconParticipantsVisibleForViewer({
  required List<BeaconParticipant> participants,
  required String viewerUserId,
  required String authorUserId,
}) {
  BeaconParticipant? mine;
  for (final p in participants) {
    if (p.userId == viewerUserId) {
      mine = p;
      break;
    }
  }

  final viewerAuthor = viewerUserId == authorUserId;
  final viewerSteward = mine?.role == BeaconParticipantRoleBits.steward;
  final viewerAdmitted = mine?.roomAccess == RoomAccessBits.admitted;
  final fullLens = viewerAdmitted || viewerAuthor || viewerSteward;

  final filtered = participants.where(
    (p) => p.roomAccess != RoomAccessBits.left,
  );

  if (fullLens) {
    final list = filtered.toList(growable: false)
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return list;
  }

  bool pubLens(BeaconParticipant p) {
    if (p.userId == viewerUserId) return true;
    final role = p.role;
    return role == BeaconParticipantRoleBits.author ||
        role == BeaconParticipantRoleBits.steward ||
        role == BeaconParticipantRoleBits.forwarder;
  }

  final list = filtered.where(pubLens).toList(growable: false)
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  return list;
}

/// Best-effort display name: author, then [userIdToKnownTitle] (e.g. helpOffers), else id.
String participantDisplayTitle({
  required BeaconParticipant participant,
  required Beacon beacon,
  required Map<String, String> userIdToKnownTitle,
}) {
  if (participant.userId == beacon.author.id) {
    return beacon.author.displayName;
  }
  final t = userIdToKnownTitle[participant.userId];
  if (t != null && t.trim().isNotEmpty) return t.trim();
  return participant.userId.length <= 10
      ? participant.userId
      : '${participant.userId.substring(0, 8)}…';
}

/// Active-helpers fold from the admitted-helper Hasura projection.
///
/// Author first (starred), then roster profiles (non-author). Optional
/// [helpOffers] / [roomParticipants] enrich member/author rows only.
List<BeaconPeopleRow> activeHelpersFromAdmittedRoster({
  required Beacon beacon,
  required List<Profile> admittedHelpers,
  List<BeaconPeopleHelpOfferInput> helpOffers = const [],
  List<BeaconParticipant> roomParticipants = const [],
}) {
  final authorId = beacon.author.id;
  final participantByUserId = {
    for (final p in roomParticipants) p.userId: p,
  };
  final helpOfferByUserId = {
    for (final ho in helpOffers)
      if (!ho.isWithdrawn) ho.userId: ho,
  };

  Profile profileFor(String userId, Profile? rosterProfile) {
    if (userId == authorId) return beacon.author;
    if (rosterProfile != null && rosterProfile.displayName.isNotEmpty) {
      return rosterProfile;
    }
    final ho = helpOfferByUserId[userId];
    if (ho != null && ho.profile.displayName.isNotEmpty) {
      return ho.profile;
    }
    final p = participantByUserId[userId];
    if (p != null && p.userTitle.trim().isNotEmpty) {
      return Profile(id: userId, displayName: p.userTitle.trim());
    }
    return rosterProfile ?? Profile(id: userId);
  }

  final helpers = [...admittedHelpers]
    ..sort((a, b) => a.displayName.compareTo(b.displayName));

  return [
    BeaconPeopleRow(
      userId: authorId,
      profile: beacon.author,
      participant: participantByUserId[authorId],
      isAuthor: true,
    ),
    for (final helper in helpers)
      if (helper.id != authorId)
        BeaconPeopleRow(
          userId: helper.id,
          profile: profileFor(helper.id, helper),
          participant: participantByUserId[helper.id],
          isAuthor: false,
        ),
  ];
}

BeaconPeopleSections classifyBeaconPeopleSections({
  required Beacon beacon,
  required List<BeaconPeopleHelpOfferInput> helpOffers,
  required List<BeaconParticipant> roomParticipants,
  required String viewerUserId,
  List<Profile> admittedHelpers = const [],
}) {
  final authorId = beacon.author.id;
  final visibleParticipants = beaconParticipantsVisibleForViewer(
    participants: roomParticipants,
    viewerUserId: viewerUserId,
    authorUserId: authorId,
  );

  final activeHelpers = admittedHelpers.isNotEmpty
      ? activeHelpersFromAdmittedRoster(
          beacon: beacon,
          admittedHelpers: admittedHelpers,
          helpOffers: helpOffers,
          roomParticipants: visibleParticipants,
        )
      : null;

  final admittedUserIds = <String>{
    if (activeHelpers != null)
      for (final row in activeHelpers)
        if (!row.isAuthor) row.userId,
  };
  if (activeHelpers == null) {
    for (final p in visibleParticipants) {
      if (p.roomAccess == RoomAccessBits.admitted) {
        admittedUserIds.add(p.userId);
      }
    }
    for (final ho in helpOffers) {
      if (!ho.isWithdrawn && ho.roomAccess == RoomAccessBits.admitted) {
        admittedUserIds.add(ho.userId);
      }
    }
  }

  final participantByUserId = {
    for (final p in visibleParticipants) p.userId: p,
  };
  final helpOfferByUserId = {
    for (final ho in helpOffers)
      if (!ho.isWithdrawn) ho.userId: ho,
  };

  Profile profileFor(String userId) {
    if (userId == authorId) return beacon.author;
    final ho = helpOfferByUserId[userId];
    if (ho != null && ho.profile.displayName.isNotEmpty) {
      return ho.profile;
    }
    final p = participantByUserId[userId];
    if (p != null && p.userTitle.trim().isNotEmpty) {
      return Profile(id: userId, displayName: p.userTitle.trim());
    }
    return Profile(id: userId);
  }

  BeaconPeopleRow rowFor(String userId, {required bool isAuthor}) =>
      BeaconPeopleRow(
        userId: userId,
        profile: profileFor(userId),
        participant: participantByUserId[userId],
        isAuthor: isAuthor,
      );

  final resolvedActiveHelpers =
      activeHelpers ??
      [
        rowFor(authorId, isAuthor: true),
        for (final uid
            in admittedUserIds.where((id) => id != authorId).toList()..sort(
              (a, b) =>
                  profileFor(a).displayName.compareTo(profileFor(b).displayName),
            ))
          rowFor(uid, isAuthor: false),
      ];

  final willingToHelp = <BeaconPeopleRow>[];
  final notFitting = <BeaconPeopleRow>[];
  final notFittingUserIds = {
    for (final ho in helpOffers)
      if (!ho.isWithdrawn && ho.coordinationResponse != null) ho.userId,
  };
  final assignedUserIds = {
    authorId,
    ...admittedUserIds,
  };
  for (final ho in helpOffers) {
    if (ho.isWithdrawn || !assignedUserIds.add(ho.userId)) continue;
    final row = rowFor(ho.userId, isAuthor: false);
    if (!notFittingUserIds.contains(ho.userId)) {
      willingToHelp.add(row);
    } else {
      notFitting.add(row);
    }
  }

  return BeaconPeopleSections(
    activeHelpers: resolvedActiveHelpers,
    willingToHelp: willingToHelp,
    notFitting: notFitting,
  );
}
