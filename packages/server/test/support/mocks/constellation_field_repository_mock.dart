import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';

@Injectable(
  as: ConstellationFieldRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationFieldRepositoryMock
    implements ConstellationFieldRepositoryPort {
  @override
  Future<ConstellationFieldSnapshot> readSnapshot({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  }) => Future.value(
    ConstellationFieldSnapshot(
      loadedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      context: context,
      peers: const [],
      edges: const [],
      requests: const [],
      peersCapped: false,
      requestsCapped: false,
    ),
  );

  @override
  Future<({Set<String> ids, bool capped})> visibleGraphPeerIds({
    required String viewerId,
    required String context,
    required int cap,
  }) => Future.value((ids: const <String>{}, capped: false));

  @override
  Future<List<ConstellationEdgeRecord>> trustEdges({
    required String viewerId,
    required String context,
    required Set<String> nodeIds,
  }) => Future.value(const []);

  @override
  Future<List<ConstellationRequestRecord>> ownRequests({
    required String viewerId,
  }) => Future.value(const []);

  @override
  Future<List<ConstellationRequestRecord>> discoverableRequests({
    required String viewerId,
    required String context,
    required int cap,
  }) => Future.value(const []);

  @override
  Future<List<ConstellationPeerRecord>> peerProfiles({
    required Set<String> ids,
  }) => Future.value(const []);
}
