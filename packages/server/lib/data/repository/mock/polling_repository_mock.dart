import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';

@Injectable(
  as: PollingRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class PollingRepositoryMock implements PollingRepositoryPort {
  @override
  Future<PollingVotePolicy?> findById(String pollingId) {
    throw UnimplementedError();
  }

  @override
  Future<String> createWithVariants({
    required String authorId,
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) {
    throw UnimplementedError();
  }
}
