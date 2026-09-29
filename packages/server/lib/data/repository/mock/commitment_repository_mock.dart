import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';

@Injectable(
  as: CommitmentRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class CommitmentRepositoryMock implements CommitmentRepositoryPort {
  @override
  Future<void> record({
    required String beaconId,
    required String userId,
    required String actorUserId,
    required CommitmentEventKind kind,
    String? reason,
  }) => Future.value();

  @override
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(String beaconId) =>
      Future.value(const {});

  @override
  Future<List<CommitmentEvent>> eventsForPair({
    required String beaconId,
    required String userId,
  }) => Future.value(const []);
}
