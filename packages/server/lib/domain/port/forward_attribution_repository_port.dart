import 'package:tentura_server/domain/entity/forward_attribution_entity.dart';
import 'package:tentura_server/domain/entity/forward_attribution_method.dart';

abstract class ForwardAttributionRepositoryPort {
  /// Weights must sum to 1 (± 1e-9). Must be called inside the forwarding
  /// transaction (same ambient-transaction contract as the evidence writer).
  Future<void> record({
    required String batchId,
    required Map<String, double> weightByParentEdgeId,
    required ForwardAttributionMethod method,
  });

  Future<List<ForwardAttributionEntity>> fetchByBatchIds(List<String> batchIds);
}
