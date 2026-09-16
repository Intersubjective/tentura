import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/forward_candidate_peer_row.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/port/forward_candidates_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ForwardCandidatesCase extends UseCaseBase {
  ForwardCandidatesCase(
    this._peers,
    this._profiles,
    this._personVisibility, {
    required super.env,
    required super.logger,
  });

  final ForwardCandidatesRepositoryPort _peers;
  final UserProfileBatchLookup _profiles;
  final PersonVisibilityRepositoryPort _personVisibility;

  /// Trust peers (unchanged) followed by bond-only peers with zero MR/trust.
  /// Every bonded peer is flagged with `sharesActiveContext` (issue #146).

  Future<List<UserPublicRecord>> fetch({
    required String viewerId,
    required String context,
  }) async {
    if (viewerId.trim().isEmpty) {
      return const [];
    }

    final trustPeers = await _peers.fetchVisiblePeers(
      viewerId: viewerId,
      context: context,
    );
    final bondPeerIds = await _personVisibility.bondPeerIds(
      viewerId: viewerId,
    );
    final trustPeerIds = {for (final peer in trustPeers) peer.peerId};
    final peers = [
      ...trustPeers,
      for (final id in bondPeerIds)
        if (!trustPeerIds.contains(id))
          ForwardCandidatePeerRow(
            peerId: id,
            forwardMr: 0,
            reverseMr: 0,
            viewerTrusts: false,
            trustsViewer: false,
          ),
    ];
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
      for (final peer in peers)
        if (profiles[peer.peerId] case final profile?)
          bondPeerIds.contains(peer.peerId)
              ? _withSharedContext(profile)
              : profile,
    ];
  }

  static UserPublicRecord _withSharedContext(UserPublicRecord u) =>
      UserPublicRecord(
        id: u.id,
        displayName: u.displayName,
        description: u.description,
        handle: u.handle,
        myVote: u.myVote,
        isMutualFriend: u.isMutualFriend,
        subjectExplicitlyTrustsViewer: u.subjectExplicitlyTrustsViewer,
        sharesActiveContext: true,
        image: u.image,
        scores: u.scores,
        userPresence: u.userPresence,
        userAvailability: u.userAvailability,
      );
}
