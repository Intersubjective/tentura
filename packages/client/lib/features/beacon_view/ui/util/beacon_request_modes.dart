import 'package:flutter/foundation.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';

/// Which face of the Request screen the viewer gets (#159, #104).
enum BeaconViewMode {
  /// Author and people let in: operational HUD with Now / Chat / People.
  hud,

  /// Everyone else: what it is, who asks, who is in on it, one big action.
  showcase,
}

/// [BeaconViewMode.showcase] when the viewer is not inside the Request, or
/// when an insider previews it ("How others see it").
BeaconViewMode beaconViewModeFor(
  BeaconViewState state, {
  bool previewAsOutsider = false,
}) => previewAsOutsider || !state.isInsideRequest
    ? BeaconViewMode.showcase
    : BeaconViewMode.hud;

/// Team as the showcase strip shows it: acquaintances first.
@immutable
class BeaconShowcaseTeam {
  const BeaconShowcaseTeam({
    required this.visible,
    required this.acquaintances,
    required this.hiddenCount,
  });

  /// Members the viewer may see, acquaintances first, then roster order.
  final List<Profile> visible;

  /// The subset of [visible] the viewer knows, in [visible] order.
  final List<Profile> acquaintances;

  /// Members counted on the Request but not readable by the viewer (blocked,
  /// or past the preview); shown only as "+N".
  final int hiddenCount;

  int get total => visible.length + hiddenCount;

  bool get isEmpty => total == 0;
}

/// Orders the admitted-helper team for the showcase strip.
///
/// An acquaintance is someone the viewer trusts ([Profile.myVote] > 0) or
/// shares a past Request with ([acquaintanceIds], from the server). Only
/// profiles the viewer can already read are named; the rest of
/// [totalCount] becomes [BeaconShowcaseTeam.hiddenCount].
BeaconShowcaseTeam deriveBeaconShowcaseTeam({
  required List<Profile> roster,
  required int totalCount,
  required Set<String> acquaintanceIds,
  required String viewerId,
}) {
  final seen = <String>{};
  final known = <Profile>[];
  final others = <Profile>[];
  for (final p in roster) {
    if (p.id.isEmpty || p.id == viewerId || !seen.add(p.id)) continue;
    if (p.myVote > 0 || acquaintanceIds.contains(p.id)) {
      known.add(p);
    } else {
      others.add(p);
    }
  }
  final visible = [...known, ...others];
  final hidden = totalCount - visible.length;
  return BeaconShowcaseTeam(
    visible: visible,
    acquaintances: known,
    hiddenCount: hidden > 0 ? hidden : 0,
  );
}

/// [deriveBeaconShowcaseTeam] over the view state: the full roster when it
/// was fetched, else the beacon's preview.
BeaconShowcaseTeam beaconShowcaseTeamFromState(BeaconViewState state) {
  final beacon = state.beacon;
  final roster = state.admittedHelpersLoaded
      ? state.admittedHelperRoster
      : beacon.admittedHelperUsers;
  return deriveBeaconShowcaseTeam(
    roster: roster,
    totalCount: beacon.admittedHelperCount,
    acquaintanceIds: state.teamAcquaintanceIds,
    viewerId: state.myProfile.id,
  );
}

/// One HUD party-frame row: a team member and their current move.
@immutable
class BeaconHudTeamMember {
  const BeaconHudTeamMember({
    required this.profile,
    this.nextMove,
    this.isAuthor = false,
  });

  final Profile profile;
  final String? nextMove;
  final bool isAuthor;
}

/// HUD team: author first, then admitted helpers, each with their next move
/// from the room roster when the viewer can read it.
List<BeaconHudTeamMember> beaconHudTeam(BeaconViewState state) {
  final moves = <String, String>{
    for (final BeaconParticipant p in state.roomParticipants)
      if (p.roomAccess == RoomAccessBits.admitted &&
          (p.nextMoveText?.trim().isNotEmpty ?? false))
        p.userId: p.nextMoveText!.trim(),
  };
  final author = state.beacon.author;
  final roster = state.admittedHelpersLoaded
      ? state.admittedHelperRoster
      : state.beacon.admittedHelperUsers;
  final seen = <String>{author.id};
  return [
    if (author.id.isNotEmpty)
      BeaconHudTeamMember(
        profile: author,
        nextMove: moves[author.id],
        isAuthor: true,
      ),
    for (final p in roster)
      if (p.id.isNotEmpty && seen.add(p.id))
        BeaconHudTeamMember(profile: p, nextMove: moves[p.id]),
  ];
}

/// Who last set the next step, as a display name; null when unknown.
String? beaconStepEditorName(BeaconViewState state) {
  final id = state.beaconRoomCue?.updatedBy?.trim();
  if (id == null || id.isEmpty) return null;
  if (id == state.beacon.author.id) return state.beacon.author.shownName;
  if (id == state.myProfile.id) return state.myProfile.shownName;
  for (final p in state.admittedHelperRoster) {
    if (p.id == id) return p.shownName;
  }
  for (final p in state.roomParticipants) {
    if (p.userId == id && p.userTitle.trim().isNotEmpty) {
      return p.userTitle.trim();
    }
  }
  return null;
}
