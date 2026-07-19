import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/forward_attribution_entity.dart';
import 'package:tentura_server/domain/entity/forward_attribution_method.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';

@LazySingleton(
  as: ForwardAttributionRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class ForwardAttributionRepositoryMock
    implements ForwardAttributionRepositoryPort {
  const ForwardAttributionRepositoryMock();

  @override
  Future<List<ForwardAttributionEntity>> fetchByBatchIds(
    List<String> batchIds,
  ) async =>
      const [];

  @override
  Future<void> record({
    required String batchId,
    required Map<String, double> weightByParentEdgeId,
    required ForwardAttributionMethod method,
  }) async {}
}
