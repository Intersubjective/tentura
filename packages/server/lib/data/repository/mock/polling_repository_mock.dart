import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/database/tentura_db.dart';

import '../polling_repository.dart';

@Injectable(
  as: PollingRepository,
  env: [Environment.test],
  order: 1,
)
class PollingRepositoryMock implements PollingRepository {
  @override
  Future<Polling?> findById(String pollingId) {
    throw UnimplementedError();
  }

  @override
  Future<String> create({
    required String authorId,
    required String question,
  }) {
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
