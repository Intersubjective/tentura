import 'package:meta/meta.dart';

import 'package:tentura/domain/entity/profile.dart';

/// Why `forwardCandidates` suggests a person (server `forward_reach.kind`).
enum ForwardReachKind {
  direct,
  viaConnection,
  sharedRequest,
  wider,
}

/// A Request the viewer and candidate both participate in.
typedef ForwardSharedRequest = ({String id, String title});

/// Reach explanation on a forward picker row; null on profiles from other queries.
@immutable
class ForwardReach {
  const ForwardReach({
    required this.kind,
    this.via = const [],
    this.viaCount = 0,
    this.sharedRequest,
  });

  final ForwardReachKind kind;

  /// Up to two vouchers (viewer connections who trust the candidate).
  final List<Profile> via;

  /// Total voucher count, including those not listed in [via].
  final int viaCount;

  final ForwardSharedRequest? sharedRequest;
}
