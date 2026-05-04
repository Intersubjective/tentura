import 'package:injectable/injectable.dart';

import '../polling_repository.dart';

@Injectable(
  as: PollingRepository,
  env: [Environment.test],
  order: 1,
)
class PollingRepositoryMock implements PollingRepository {
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
  }) {
    throw UnimplementedError();
  }
}
