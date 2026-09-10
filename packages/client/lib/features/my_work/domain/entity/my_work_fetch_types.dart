import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';

/// A help-offered row returned from the My Work fetch queries.
typedef MyWorkHelpOfferedRow = ({
  Beacon beacon,
  String offerHelpMessage,
  String? helpType,
  CoordinationResponseType? authorResponseType,
  CommitmentStakeState stakeState,
  List<Profile> forwarderSenders,

  /// `beacon_help_offers.updated_at` (offer help message / row changes).
  DateTime helpOfferRowUpdatedAt,

  /// `beacon_help_offer_coordinations.updated_at` when author response exists.
  DateTime? authorCoordinationUpdatedAt,
});

/// Obligation-backed beacon from init fetch (archive state is per viewer, not split query).
typedef MyWorkObligationRow = ({
  Beacon beacon,

  /// Whether the viewer has archived this Request (independent of card kind).
  bool viewerArchived,
});

/// Result of My Work fetch init (non-archived full rows + archived count hint).
typedef MyWorkInitResult = ({
  List<Beacon> authoredNonArchived,
  List<MyWorkHelpOfferedRow> helpOfferedNonArchived,
  List<MyWorkObligationRow> obligationBeacons,
  int archivedCountHint,
});

/// Result of My Work fetch archived (full archived rows).
typedef MyWorkArchivedResult = ({
  List<Beacon> authoredArchived,
  List<MyWorkHelpOfferedRow> helpOfferedArchived,
});
