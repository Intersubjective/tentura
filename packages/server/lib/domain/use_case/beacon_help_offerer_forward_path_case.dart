import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';

import '_use_case_base.dart';

/// Builds the edge set for the V2 `beaconHelpOffererForwardPath` query.
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
/// addition, `helpOffererId` must currently be an active help offerer of
/// `beaconId`; otherwise an `IdNotFoundException` is thrown to avoid
/// leaking arbitrary user→beacon relationships.
@Singleton(order: 2)
final class BeaconHelpOffererForwardPathCase extends UseCaseBase {
  BeaconHelpOffererForwardPathCase(
    this._beaconRepository,
    this._forwardEdgeRepository,
    this._helpOfferRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;

  // TODO(contract): Phase-2 DTO migration — replace Map return with typed DTO at resolver boundary.
  // ignore: tentura_lints/no_map_dynamic_in_use_case_api
  Future<Map<String, dynamic>> asMap({
    required String beaconId,
    required String helpOffererId,
    required String currentUserId,
  }) async {
    final results = await Future.wait([
      _beaconRepository.getBeaconById(beaconId: beaconId),
      _helpOfferRepository.fetchAllByBeaconId(beaconId),
    ]);

    final beacon = results[0] as BeaconEntity;
    final helpOffers = results[1] as List<HelpOfferEntity>;

    final authorId = beacon.author.id;
    final activeHelpOffererIds = helpOffers
        .where((c) => c.status == 0)
        .map((c) => c.userId)
        .toSet();

    if (!activeHelpOffererIds.contains(helpOffererId)) {
      throw IdNotFoundException(
        id: helpOffererId,
        description:
            'User is not an active help offerer of the beacon',
      );
    }

    final allEdges = await _forwardEdgeRepository.fetchByBeaconId(beaconId);
    final isAuthor = currentUserId == authorId;
    final isInvolved =
        isAuthor ||
        activeHelpOffererIds.contains(currentUserId) ||
        allEdges.any(
          (e) =>
              e.senderId == currentUserId || e.recipientId == currentUserId,
        );
    if (!isInvolved) {
      throw const UnauthorizedException(
        description: 'Viewer is not involved in this beacon',
      );
    }

    final chainEdges = await _forwardEdgeRepository.fetchHelpOffererPathChain(
      beaconId: beaconId,
      helpOffererId: helpOffererId,
      viewerId: currentUserId,
    );

    return {
      'beaconId': beaconId,
      'authorId': authorId,
      'viewerId': currentUserId,
      'helpOffererIds': <String>[helpOffererId],
      'edges': [
        for (final e in chainEdges)
          {
            'id': e.id,
            'beaconId': e.beaconId,
            'senderId': e.senderId,
            'recipientId': e.recipientId,
            'parentEdgeId': e.parentEdgeId,
            'batchId': e.batchId,
          },
      ],
    };
  }
}
