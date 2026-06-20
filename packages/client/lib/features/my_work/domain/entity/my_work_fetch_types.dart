import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';

/// A help-offered row returned from the My Work fetch queries.
typedef MyWorkHelpOfferedRow = ({
  Beacon beacon,
  String offerHelpMessage,
  String? helpType,
  CoordinationResponseType? authorResponseType,
  List<Profile> forwarderSenders,

  /// `beacon_help_offers.updated_at` (offer help message / row changes).
  DateTime helpOfferRowUpdatedAt,

  /// `beacon_help_offer_coordinations.updated_at` when author response exists.
  DateTime? authorCoordinationUpdatedAt,
});

/// Result of My Work fetch init (non-archived full rows + archived count hint).
typedef MyWorkInitResult = ({
  List<Beacon> authoredNonArchived,
  List<MyWorkHelpOfferedRow> helpOfferedNonArchived,
  int archivedCountHint,

  /// Latest message on active coordination items per beacon (V2).
  Map<String, DateTime> lastItemDiscussionMessageAtByBeaconId,
});

/// Result of My Work fetch archived (full archived rows).
typedef MyWorkArchivedResult = ({
  List<Beacon> authoredArchived,
  List<MyWorkHelpOfferedRow> helpOfferedArchived,
});
