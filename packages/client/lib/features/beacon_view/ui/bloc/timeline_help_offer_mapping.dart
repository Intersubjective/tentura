import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'beacon_view_state.dart';

typedef HelpOfferWithCoordinationRow = ({
  String beaconId,
  String userId,
  Profile user,
  String message,
  String? helpType,
  String? roleLabel,
  int status,
  String? withdrawReason,
  DateTime createdAt,
  DateTime updatedAt,
  int? responseType,
  DateTime? responseUpdatedAt,
  String? responseAuthorUserId,
  int? roomAccess,
  int? admissionAction,
  String? lastDeclineReason,
  String? lastRemoveReason,
  int stakeState,
  int offerKind,
  bool isDirectAuthorForward,
});

List<TimelineHelpOffer> timelineHelpOffersFromRemote(
  List<HelpOfferWithCoordinationRow> helpOffers,
) => [
  for (final c in helpOffers)
    TimelineHelpOffer(
      user: c.user,
      message: c.message,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
      isWithdrawn: c.status == 1,
      helpType: c.helpType,
      roleLabel: c.roleLabel,
      coordinationResponse: CoordinationResponseType.tryFromInt(c.responseType),
      withdrawReason: c.withdrawReason,
      roomAccess: c.roomAccess,
      admissionAction: HelpOfferAdmissionAction.tryFromInt(c.admissionAction),
      lastDeclineReason: c.lastDeclineReason,
      lastRemoveReason: c.lastRemoveReason,
      stakeState: CommitmentStakeState.fromInt(c.stakeState),
      offerKind: c.offerKind,
      isDirectAuthorForward: c.isDirectAuthorForward,
    ),
];
