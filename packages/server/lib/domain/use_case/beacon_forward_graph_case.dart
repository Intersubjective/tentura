import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/gql_public/forward_graph_result.dart';
import 'package:tentura_server/domain/entity/forward_tree_edge.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/utils/typed_wait.dart';

import '_use_case_base.dart';

/// Builds the forward tree powering the V2 `beaconForwardGraph` query.
///
/// A chain participant gets every live edge: the author, anyone who sent or
/// received a live edge, anyone with a help offer (any status) and, for a
/// Post, admitted room members. Other viewers who may read involvement get
/// the chains to active help offerers (and, for a Post steward, to admitted
/// members) with their ancestors.
///
/// Reading the tree never changes visibility, trust or anchors: everyone in
/// it is named unless a block hides them from the viewer.
@Singleton(order: 2)
final class BeaconForwardGraphCase extends UseCaseBase {
  BeaconForwardGraphCase(
    this._beaconRepository,
    this._forwardEdgeRepository,
    this._helpOfferRepository,
    this._guard,
    this._roomRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final BeaconAccessGuard _guard;
  final BeaconRoomRepositoryPort _roomRepository;

  Future<ForwardGraphResult> asMap({
    required String beaconId,
    required String currentUserId,
  }) async {
    if (!await _guard.canReadInvolvement(
      beaconId: beaconId,
      viewerId: currentUserId,
    )) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request involvement',
      );
    }

    final (beacon, tree, helpOffers) = await (
      _beaconRepository.getBeaconById(beaconId: beaconId),
      _forwardEdgeRepository.fetchForwardTree(
        beaconId: beaconId,
        viewerId: currentUserId,
      ),
      _helpOfferRepository.fetchAllByBeaconId(beaconId),
    ).waitAll;

    final authorId = beacon.author.id;
    final helpOffererIds = helpOffers
        .where((c) => c.status == 0)
        .map((c) => c.userId)
        .toSet();

    // A Post has no help offers: admitted room members take part (#718).
    var admittedIds = const <String>{};
    if (beacon.kind == BeaconKind.post) {
      admittedIds = (await _roomRepository.listParticipants(beaconId))
          .where((p) => p.roomAccess == RoomAccessBits.admitted)
          .map((p) => p.userId)
          .toSet();
    }

    final isParticipant =
        currentUserId == authorId ||
        admittedIds.contains(currentUserId) ||
        helpOffers.any((offer) => offer.userId == currentUserId) ||
        tree.any(
          (e) =>
              e.edge.senderId == currentUserId ||
              e.edge.recipientId == currentUserId,
        );

    final visible = isParticipant
        ? tree
        : _chainsToSeeds(
            tree,
            seedRecipientIds: {
              ...helpOffererIds,
              // A steward reads how each current member of a Post got in.
              if (admittedIds.isNotEmpty &&
                  await _roomRepository.isBeaconSteward(
                    beaconId: beaconId,
                    userId: currentUserId,
                  ))
                ...admittedIds,
            },
          );

    final forwardedOnIds = {
      for (final e in tree)
        if (e.edge.parentEdgeId != null) e.edge.parentEdgeId!,
    };

    return ForwardGraphResult(
      beaconId: beaconId,
      authorId: authorId,
      helpOffererIds: helpOffererIds.toList(),
      edges: [
        for (final e in visible)
          _edgeToResult(
            e,
            forwardedOn: forwardedOnIds.contains(e.edge.id),
            // Read and «can't make it» states are private to the author and
            // the sender of that edge.
            showPrivate:
                currentUserId == authorId || currentUserId == e.edge.senderId,
          ),
      ],
    );
  }

  /// Edges delivering the beacon to [seedRecipientIds], with their ancestors,
  /// in tree order.
  static List<ForwardTreeEdge> _chainsToSeeds(
    List<ForwardTreeEdge> tree, {
    required Set<String> seedRecipientIds,
  }) {
    final edgeById = {for (final e in tree) e.edge.id: e};
    final visibleIds = <String>{};
    for (final seed in tree) {
      if (!seedRecipientIds.contains(seed.edge.recipientId)) continue;
      ForwardTreeEdge? cursor = seed;
      while (cursor != null && visibleIds.add(cursor.edge.id)) {
        final parentId = cursor.edge.parentEdgeId;
        if (parentId == null) break;
        cursor = edgeById[parentId];
      }
    }
    return [
      for (final e in tree)
        if (visibleIds.contains(e.edge.id)) e,
    ];
  }

  static ForwardTreeEdgeResult _edgeToResult(
    ForwardTreeEdge e, {
    required bool forwardedOn,
    required bool showPrivate,
  }) => ForwardTreeEdgeResult(
    id: e.edge.id,
    beaconId: e.edge.beaconId,
    senderId: e.edge.senderId,
    recipientId: e.edge.recipientId,
    parentEdgeId: e.edge.parentEdgeId,
    batchId: e.edge.batchId,
    createdAt: e.edge.createdAt,
    sender: e.sender,
    recipient: e.recipient,
    forwardedOn: forwardedOn,
    offerStatus: e.recipientOffer,
    readAt: showPrivate ? e.edge.recipientReadAt : null,
    declinedInvite: showPrivate ? e.recipientDeclined : null,
  );
}
