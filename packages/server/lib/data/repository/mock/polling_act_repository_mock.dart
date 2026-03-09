import 'package:injectable/injectable.dart';

import '../polling_act_repository.dart';

@Injectable(
  as: PollingActRepository,
  env: [Environment.test],
  order: 1,
)
class PollingActRepositoryMock implements PollingActRepository {
  @override
  Future<void> create({
    required String authorId,
    required String pollingId,
    required String variantId,
  }) {
    throw UnimplementedError();
  }
}
