import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';

/// A committed row returned from the My Work fetch queries.
typedef MyWorkCommittedRow = ({
  Beacon beacon,
  String commitMessage,
  String? helpType,
  CoordinationResponseType? authorResponseType,
  List<Profile> forwarderSenders,

  /// `beacon_commitment.updated_at` (commit message / row changes).
  DateTime commitmentRowUpdatedAt,

  /// `beacon_commitment_coordination.updated_at` when author response exists.
  DateTime? authorCoordinationUpdatedAt,
});

/// Result of My Work fetch init (non-closed full rows + closed id hints).
typedef MyWorkInitResult = ({
  List<Beacon> authoredNonClosed,
  List<MyWorkCommittedRow> committedNonClosed,
  List<String> authoredClosedIds,
  List<String> committedClosedIds,
});

/// Result of My Work fetch closed (full closed rows).
typedef MyWorkClosedResult = ({
  List<Beacon> authoredClosed,
  List<MyWorkCommittedRow> committedClosed,
});
