import 'package:injectable/injectable.dart';

import '../database/tentura_db.dart';

/// Batch-friendly reciprocal positive `vote_user` edges (strict mutual subscribe).
@lazySingleton
class VoteUserFriendshipLookup {
  VoteUserFriendshipLookup(this._database);

  final TenturaDb _database;

  /// Peers in [peerIds] that have `viewerId -> peer` and `peer -> viewer`
  /// with `amount > 0`.
  Future<Set<String>> reciprocalPositivePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async {
    final candidates = peerIds
        .where((id) => id.isNotEmpty && id != viewerId)
        .toList();
    if (candidates.isEmpty) {
      return {};
    }
    final forward = await (_database.select(_database.voteUsers)
          ..where(
            (v) =>
                v.subject.equals(viewerId) &
                v.amount.isBiggerThanValue(0) &
                v.object.isIn(candidates),
          ))
        .get();
    if (forward.isEmpty) {
      return {};
    }
    final forwardPeers = forward.map((r) => r.object).toSet();
    final reverse = await (_database.select(_database.voteUsers)
          ..where(
            (v) =>
                v.subject.isIn(forwardPeers) &
                v.object.equals(viewerId) &
                v.amount.isBiggerThanValue(0),
          ))
        .get();
    return reverse.map((r) => r.subject).toSet();
  }

  Future<bool> isReciprocalSubscribe({
    required String viewerId,
    required String peerId,
  }) async {
    if (viewerId == peerId || peerId.isEmpty) {
      return false;
    }
    final s = await reciprocalPositivePeerIds(
      viewerId: viewerId,
      peerIds: [peerId],
    );
    return s.contains(peerId);
  }
}
