import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/forward_graph_result.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/help_path_node.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';

import '_use_case_base.dart';

/// Builds the ordered help path and the existing forwards-graph edge set.
///
/// The graph is centered on a single active help offerer of `beaconId` and
/// returns the **union** of:
/// * every forward edge whose ancestor closure delivered the beacon to the
///   help offerer (`recipient_id == helpOffererId`), plus
/// * every forward edge in which the viewer is sender or recipient and
///   their ancestor closure (so case 2 — viewer is "an involved person" —
///   sees how they fit between the author and the help offerer).
///
/// When the viewer is the beacon author the second seed matches nothing
/// extra and the result reduces to the help offerer's chain. When the viewer
/// is the help offerer themselves the second seed coincides with the first.
///
/// Authorization mirrors `BeaconForwardGraphCase`: viewer must be the
/// beacon author OR have at least one forward edge for the beacon (as
/// sender or recipient) OR have an active help offer on the beacon. In
/// addition, `helpOffererId` must have a non-withdrawn help offer on
/// `beaconId`; otherwise an `IdNotFoundException` is thrown to avoid
/// leaking arbitrary user→beacon relationships.
@Singleton(order: 1)
final class BeaconHelpOffererForwardPathCase extends UseCaseBase {
  BeaconHelpOffererForwardPathCase(
    this._beaconRepository,
    this._forwardEdgeRepository,
    this._helpOfferRepository,
    this._guard, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final BeaconAccessGuard _guard;

  Future<ForwardGraphResult> asMap({
    required String beaconId,
    required String helpOffererId,
    required String currentUserId,
  }) async {
    // Guard first — canReadInvolvement covers author, forward edges,
    // room participants, and help offerers, matching the same contract as
    // BeaconForwardGraphCase.
    if (!await _guard.canReadInvolvement(
      beaconId: beaconId,
      viewerId: currentUserId,
    )) {
      throw const UnauthorizedException(
        description: 'Viewer is not involved in this request',
      );
    }

    final (beacon, offer) = await _target(beaconId, helpOffererId);
    final authorId = beacon.author.id;

    final chainEdges = await _forwardEdgeRepository.fetchHelpOffererPathChain(
      beaconId: beaconId,
      helpOffererId: helpOffererId,
      viewerId: currentUserId,
    );
    final path = await _pathFor(beacon, offer, viewerId: currentUserId);
    final onPath =
        currentUserId == authorId ||
        currentUserId == helpOffererId ||
        path.any((node) => node.userId == currentUserId);

    return ForwardGraphResult(
      beaconId: beaconId,
      authorId: authorId,
      viewerId: currentUserId,
      helpOffererIds: [helpOffererId],
      edges: chainEdges.map(_edgeToResult).toList(),
      path: onPath ? path : const [],
    );
  }

  /// Server-side notification reads use the same canonical route, without
  /// applying a particular viewer's block mask. This is not a public query.
  Future<List<HelpPathNode>> helpPathFor({
    required String beaconId,
    required String helperId,
  }) async {
    final (beacon, offer) = await _target(beaconId, helperId);
    return _pathFor(beacon, offer);
  }

  Future<(BeaconEntity, HelpOfferEntity)> _target(
    String beaconId,
    String helperId,
  ) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    final offers = await _helpOfferRepository.fetchAllByBeaconId(beaconId);
    final offer = offers.where((offer) => offer.userId == helperId).firstOrNull;
    // Acceptance is room/commitment state; an accepted offer remains active
    // in beacon_help_offer. Closure does not invalidate that arrival history.
    if (offer == null || !offer.isActive) {
      throw IdNotFoundException(
        id: helperId,
        description: 'User is not an active help offerer of the request',
      );
    }
    return (beacon, offer);
  }

  Future<List<HelpPathNode>> _pathFor(
    BeaconEntity beacon,
    HelpOfferEntity offer, {
    String? viewerId,
  }) async => HelpPathNode.collapseAnonymous(
    await _forwardEdgeRepository.fetchHelpPath(
      beaconId: beacon.id,
      helperId: offer.userId,
      authorId: beacon.author.id,
      offerCreatedAt: offer.createdAt,
      viewerId: viewerId,
    ),
  );
}

ForwardGraphEdgeResult _edgeToResult(ForwardEdgeEntity e) =>
    ForwardGraphEdgeResult(
      id: e.id,
      beaconId: e.beaconId,
      senderId: e.senderId,
      recipientId: e.recipientId,
      parentEdgeId: e.parentEdgeId,
      batchId: e.batchId,
    );
