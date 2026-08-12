import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/port/band_candidate_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: BandCandidatePort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class BandCandidateRepository implements BandCandidatePort {
  const BandCandidateRepository(
    this._database,
    this._forwardEdgeRepository,
    this._helpOfferRepository,
    this._inboxRepository,
  );

  final TenturaDb _database;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final InboxRepositoryPort _inboxRepository;

  @override
  Future<List<BandCandidate>> candidatesFor({
    required String egoId,
    required String beaconId,
    required String normalizedContext,
  }) async {
    final authorId = await _fetchBeaconAuthorId(beaconId);
    if (authorId == null) {
      return const [];
    }

    final results = await Future.wait([
      _forwardEdgeRepository.fetchByBeaconId(beaconId),
      _helpOfferRepository.fetchAllByBeaconId(beaconId),
      _inboxRepository.fetchRejectedUserIdsByBeacon(beaconId),
      _forwardEdgeRepository.fetchAllByBeaconId(beaconId),
      _fetchVisibilityPeers(egoId: egoId, normalizedContext: normalizedContext),
    ]);

    final activeEdges = results[0] as List<ForwardEdgeEntity>;
    final helpOffers = results[1] as List<HelpOfferEntity>;
    final rejectedIds = (results[2] as List<String>).toSet();
    final allEdges = results[3] as List<ForwardEdgeEntity>;
    final visibilityPeers = results[4] as List<_VisibilityPeer>;
    final helpOfferedIds = helpOffers
        .where((c) => c.status == 0)
        .map((c) => c.userId)
        .toSet();
    final withdrawnIds = helpOffers
        .where((c) => c.status == 1)
        .map((c) => c.userId)
        .toSet();
    final myForwardedRecipientIds = activeEdges
        .where((e) => e.senderId == egoId)
        .map((e) => e.recipientId)
        .toSet();
    final lastForwardedAtByRecipient = <String, DateTime>{};
    for (final edge in allEdges) {
      if (edge.senderId != egoId) continue;
      final prior = lastForwardedAtByRecipient[edge.recipientId];
      if (prior == null || edge.createdAt.isAfter(prior)) {
        lastForwardedAtByRecipient[edge.recipientId] = edge.createdAt;
      }
    }

    final candidates = <BandCandidate>[];
    for (final peer in visibilityPeers) {
      final userId = peer.peerId;
      if (_excludeFromCandidateList(
        userId: userId,
        authorId: authorId,
        rejectedIds: rejectedIds,
        myForwardedRecipientIds: myForwardedRecipientIds,
      )) {
        continue;
      }

      candidates.add(
        BandCandidate(
          userId: userId,
          forwardMr: peer.forwardMr,
          canForwardTo: _canForwardTo(
            userId: userId,
            authorId: authorId,
            helpOfferedIds: helpOfferedIds,
            withdrawnIds: withdrawnIds,
            myForwardedRecipientIds: myForwardedRecipientIds,
            rejectedIds: rejectedIds,
          ),
          alreadyForwarded: myForwardedRecipientIds.contains(userId),
          lastForwardedAt: lastForwardedAtByRecipient[userId],
        ),
      );
    }

    candidates.sort((a, b) {
      final mr = b.forwardMr.compareTo(a.forwardMr);
      if (mr != 0) return mr;
      return a.userId.compareTo(b.userId);
    });
    return candidates;
  }

  @override
  Future<Set<String>> recentlyForwardedTo({
    required String egoId,
    required int withinDays,
  }) =>
      _forwardEdgeRepository.fetchRecipientIdsForwardedBySenderWithinDays(
        senderId: egoId,
        withinDays: withinDays,
      );

  Future<String?> _fetchBeaconAuthorId(String beaconId) async {
    final row = await _database.managers.beacons
        .filter((b) => b.id.equals(beaconId))
        .getSingleOrNull();
    return row?.userId;
  }

  Future<List<_VisibilityPeer>> _fetchVisibilityPeers({
    required String egoId,
    required String normalizedContext,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT peer_id, forward_mr
FROM public.person_visibility_peers($1, $2) p
WHERE forward_mr > 0
  AND p.is_mutually_visible
  AND NOT public.block_hides($1, p.peer_id)
''',
          variables: [
            Variable<String>(egoId),
            Variable<String>(normalizedContext),
          ],
          readsFrom: {},
        )
        .get();

    return [
      for (final row in rows)
        _VisibilityPeer(
          peerId: row.read<String>('peer_id'),
          forwardMr: row.read<double>('forward_mr'),
        ),
    ];
  }

  /// Peers excluded from the band candidate list entirely (not merely
  /// `canForwardTo == false`).
  static bool _excludeFromCandidateList({
    required String userId,
    required String authorId,
    required Set<String> rejectedIds,
    required Set<String> myForwardedRecipientIds,
  }) =>
      userId == authorId ||
      rejectedIds.contains(userId) ||
      myForwardedRecipientIds.contains(userId);

  /// Mirrors client [ForwardCase.computeInvolvement] + [ForwardCandidate.canForwardTo].
  static bool _canForwardTo({
    required String userId,
    required String authorId,
    required Set<String> helpOfferedIds,
    required Set<String> withdrawnIds,
    required Set<String> myForwardedRecipientIds,
    required Set<String> rejectedIds,
  }) {
    if (userId == authorId) return false;
    if (helpOfferedIds.contains(userId)) return false;
    if (withdrawnIds.contains(userId)) return false;
    if (myForwardedRecipientIds.contains(userId)) return false;
    if (rejectedIds.contains(userId)) return false;
    return true;
  }
}

class _VisibilityPeer {
  const _VisibilityPeer({required this.peerId, required this.forwardMr});

  final String peerId;
  final double forwardMr;
}
