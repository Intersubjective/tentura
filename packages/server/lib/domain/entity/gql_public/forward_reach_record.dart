import 'package:meta/meta.dart';

import 'user_public_record.dart';

/// Why `forwardCandidates` suggests a person, strongest reason first.
enum ForwardReachKind {
  /// The viewer trusts the candidate directly.
  direct,

  /// At least one of the viewer's direct connections trusts the candidate.
  viaConnection,

  /// No voucher, but the viewer and the candidate share an active Request.
  sharedRequest,

  /// Any other path.
  wider,
}

/// A Request the viewer and a candidate share and the viewer can read.
typedef ForwardSharedRequest = ({String id, String title});

/// Reach explanation on one `forwardCandidates` row; null everywhere else.
@immutable
class ForwardReachRecord {
  const ForwardReachRecord({
    required this.kind,
    this.via = const [],
    this.viaCount = 0,
    this.sharedRequest,
  });

  final ForwardReachKind kind;

  /// Up to two vouchers, strongest viewer trust first.
  final List<UserPublicRecord> via;

  /// Every voucher, including those not previewed in [via].
  final int viaCount;

  /// Most recently active shared Request, if any.
  final ForwardSharedRequest? sharedRequest;
}
