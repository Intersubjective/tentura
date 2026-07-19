import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/coordination/resolve_forward_parent_edge.dart';
import 'package:tentura_server/domain/entity/gql_public/forward_inbound_edge_result.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ForwardInboundQueryCase extends UseCaseBase {
  ForwardInboundQueryCase(
    this._beaconRepository,
    this._forwardEdgeRepository,
    this._userRepository,
    this._guard, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final UserRepositoryPort _userRepository;
  final BeaconAccessGuard _guard;

  Future<List<ForwardInboundEdgeResult>> listEligible({
    required String beaconId,
    required String viewerId,
  }) async {
    if (!await _guard.canReadInvolvement(
      beaconId: beaconId,
      viewerId: viewerId,
    )) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request involvement',
      );
    }

    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    final inbound = await _forwardEdgeRepository.fetchActiveInboundEdges(
      beaconId: beaconId,
      recipientId: viewerId,
    );
    if (inbound.isEmpty) return const [];

    final suggestedId = resolveForwardParentEdgeId(
      clientParentEdgeId: null,
      activeInboundEdges: inbound,
      senderId: viewerId,
      authorId: beacon.author.id,
    );

    final senderIds = inbound.map((e) => e.senderId).toSet();
    final names = <String, String>{};
    for (final senderId in senderIds) {
      final user = await _userRepository.getById(senderId);
      names[senderId] = user.displayName;
    }

    return inbound
        .map(
          (e) => ForwardInboundEdgeResult(
            edgeId: e.id,
            senderId: e.senderId,
            senderName: names[e.senderId] ?? e.senderId,
            createdAt: e.createdAt,
            isSuggestedSource: e.id == suggestedId,
          ),
        )
        .toList();
  }
}
