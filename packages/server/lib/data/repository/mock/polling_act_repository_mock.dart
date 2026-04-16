import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/polling_act_repository_port.dart';

@Injectable(
  as: PollingActRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class PollingActRepositoryMock implements PollingActRepositoryPort {
  @override
  Future<void> create({
    required String authorId,
    required String pollingId,
    required String variantId,
  }) {
    throw UnimplementedError();
  }
}
