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
  String? authorSeenAt,
});

/// An author removal deactivates the offer (status 1) so it stops counting,
/// but the helper did not withdraw: the row stays a removed, re-admittable
/// offer, as it looked before the server change (#401). A helper who withdraws
/// after being removed sets a withdraw reason; the server no longer re-admits
/// that offer, so it is withdrawn here too.
bool _isWithdrawnRow(HelpOfferWithCoordinationRow c) =>
    c.status == 1 &&
    !(HelpOfferAdmissionAction.tryFromInt(c.admissionAction) ==
            HelpOfferAdmissionAction.remove &&
        c.withdrawReason == null);

List<TimelineHelpOffer> timelineHelpOffersFromRemote(
  List<HelpOfferWithCoordinationRow> helpOffers,
) => [
  for (final c in helpOffers)
    TimelineHelpOffer(
      user: c.user,
      message: c.message,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
      isWithdrawn: _isWithdrawnRow(c),
      helpType: c.helpType,
      roleLabel: c.roleLabel,
      coordinationResponse: CoordinationResponseType.tryFromInt(c.responseType),
      coordinationResponseAt: c.responseUpdatedAt,
      withdrawReason: c.withdrawReason,
      roomAccess: c.roomAccess,
      admissionAction: HelpOfferAdmissionAction.tryFromInt(c.admissionAction),
      lastDeclineReason: c.lastDeclineReason,
      lastRemoveReason: c.lastRemoveReason,
      stakeState: CommitmentStakeState.fromInt(c.stakeState),
      offerKind: c.offerKind,
      isDirectAuthorForward: c.isDirectAuthorForward,
      authorSeenAt: c.authorSeenAt == null
          ? null
          : DateTime.tryParse(c.authorSeenAt!)?.toUtc(),
    ),
];
