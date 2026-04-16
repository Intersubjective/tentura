import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/meritrank_repository_port.dart';

@Injectable(
  as: MeritrankRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class MeritrankRepositoryMock implements MeritrankRepositoryPort {
  @override
  Future<void> calculate({
    bool isBlocking = true,
    Duration timeout = const Duration(minutes: 10),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteEdge({
    required String nodeA,
    required String nodeB,
    String context = '',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> init() {
    throw UnimplementedError();
  }

  @override
  Future<void> putEdge({
    required String nodeA,
    required String nodeB,
    double weight = 1.0,
    String context = '',
    int ticker = 0,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> reset() {
    throw UnimplementedError();
  }
}
