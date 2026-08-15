import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/port/forward_candidates_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ForwardCandidatesCase extends UseCaseBase {
  ForwardCandidatesCase(
    this._peers,
    this._profiles, {
    required super.env,
    required super.logger,
  });

  final ForwardCandidatesRepositoryPort _peers;
  final UserProfileBatchLookup _profiles;

  Future<List<UserPublicRecord>> fetch({
    required String viewerId,
    required String context,
  }) async {
    if (viewerId.trim().isEmpty) {
      return const [];
    }

    final peers = await _peers.fetchVisiblePeers(
      viewerId: viewerId,
      context: context,
    );
    if (peers.isEmpty) {
      return const [];
    }

    final viewerTrustsPeerIds = {
      for (final peer in peers)
        if (peer.viewerTrusts) peer.peerId,
    };
    final trustsViewerPeerIds = {
      for (final peer in peers)
        if (peer.trustsViewer) peer.peerId,
    };
    final reciprocalPeerIds = viewerTrustsPeerIds.intersection(
      trustsViewerPeerIds,
    );
    final scoresByPeerId = {
      for (final peer in peers)
        peer.peerId: MutualScoreRecord(
          srcScore: peer.reverseMr,
          dstScore: peer.forwardMr,
        ),
    };

    final profiles = await _profiles.userPublicRecordsByIds(
      ids: peers.map((peer) => peer.peerId),
      reciprocalPeerIds: reciprocalPeerIds,
      trustsViewerPeerIds: trustsViewerPeerIds,
      viewerTrustsPeerIds: viewerTrustsPeerIds,
      scoresByPeerId: scoresByPeerId,
    );

    return [
      for (final peer in peers) ?profiles[peer.peerId],
    ];
  }
}
