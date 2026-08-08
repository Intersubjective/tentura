import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';

import '../database/tentura_db.dart';

/// Batch-friendly reciprocal positive `vote_user` edges (strict mutual subscribe).
@LazySingleton(as: VoteUserFriendshipLookupPort)
class VoteUserFriendshipLookup implements VoteUserFriendshipLookupPort {
  VoteUserFriendshipLookup(this._database);

  final TenturaDb _database;

  @override
  Future<({Set<String> viewerTrusts, Set<String> trustsViewer})>
  directionalPositiveTrustPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async {
    if (viewerId.isEmpty) {
      return (viewerTrusts: <String>{}, trustsViewer: <String>{});
    }
    final candidates = peerIds
        .where((id) => id.isNotEmpty && id != viewerId)
        .toSet();
    if (candidates.isEmpty) {
      return (viewerTrusts: <String>{}, trustsViewer: <String>{});
    }

    final forward =
        await (_database.select(_database.voteUsers)..where(
              (v) =>
                  v.subject.equals(viewerId) &
                  v.amount.isBiggerThanValue(0) &
                  v.object.isIn(candidates),
            ))
            .get();
    final reverse =
        await (_database.select(_database.voteUsers)..where(
              (v) =>
                  v.subject.isIn(candidates) &
                  v.object.equals(viewerId) &
                  v.amount.isBiggerThanValue(0),
            ))
            .get();

    return (
      viewerTrusts: forward.map((r) => r.object).toSet(),
      trustsViewer: reverse.map((r) => r.subject).toSet(),
    );
  }

  /// Peers in [peerIds] that have `viewerId -> peer` and `peer -> viewer`
  /// with `amount > 0`.
  @override
  Future<Set<String>> reciprocalPositivePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async {
    final directional = await directionalPositiveTrustPeerIds(
      viewerId: viewerId,
      peerIds: peerIds,
    );
    return directional.viewerTrusts.intersection(directional.trustsViewer);
  }

  @override
  Future<bool> isReciprocalSubscribe({
    required String viewerId,
    required String peerId,
  }) async {
    if (viewerId == peerId || peerId.isEmpty || viewerId.isEmpty) {
      return false;
    }
    final directional = await directionalPositiveTrustPeerIds(
      viewerId: viewerId,
      peerIds: [peerId],
    );
    return directional.viewerTrusts.contains(peerId) &&
        directional.trustsViewer.contains(peerId);
  }

  /// Returns true when [viewerId] has a positive trust edge toward [peerId]
  /// (one-way subscription; mutual subscribe is a strict subset).
  @override
  Future<bool> isSubscribedTo({
    required String viewerId,
    required String peerId,
  }) async {
    if (viewerId == peerId || peerId.isEmpty || viewerId.isEmpty) {
      return false;
    }
    final directional = await directionalPositiveTrustPeerIds(
      viewerId: viewerId,
      peerIds: [peerId],
    );
    return directional.viewerTrusts.contains(peerId);
  }
}
