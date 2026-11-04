import 'package:meta/meta.dart';

import 'gql_public/forward_reach_record.dart';

/// One mutually-visible peer from the `forwardCandidates` SQL wrap.
@immutable
class ForwardCandidatePeerRow {
  const ForwardCandidatePeerRow({
    required this.peerId,
    required this.forwardMr,
    required this.reverseMr,
    required this.viewerTrusts,
    required this.trustsViewer,
    this.mutualSince,
    this.viewerTrustsDirectly = false,
    this.voucherIds = const [],
    this.voucherCount = 0,
    this.sharedRequest,
  });

  final String peerId;
  final double forwardMr;
  final double reverseMr;
  final bool viewerTrusts;
  final bool trustsViewer;

  /// Start of the current pair of trust edges, or null for one-way trust.
  final DateTime? mutualSince;

  /// The viewer has a positive trust edge to the peer.
  final bool viewerTrustsDirectly;

  /// Up to two listed direct connections of the viewer that trust the peer,
  /// strongest viewer trust first; [voucherCount] counts all of them.
  final List<String> voucherIds;
  final int voucherCount;

  /// Most recently active readable Request shared with the viewer.
  final ForwardSharedRequest? sharedRequest;
}
