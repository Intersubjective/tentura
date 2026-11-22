import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';

@Injectable(
  as: WitnessWindowPort,
  env: [Environment.test],
  order: 1,
)
class WitnessWindowRepositoryMock implements WitnessWindowPort {
  @override
  Future<RawWindowFacts> rawWindowFacts({
    required String egoId,
    required String normalizedContext,
    required int topK,
  }) => Future.value(
    const RawWindowFacts(topPeers: [], trustedScores: []),
  );

  @override
  Future<void> storeWindow({
    required String egoId,
    required String normalizedContext,
    required List<WitnessWeight> weights,
  }) => Future.value();

  @override
  Future<List<WitnessWeight>> cachedWindow({
    required String egoId,
    required String normalizedContext,
  }) => Future.value(const []);

  @override
  Future<void> invalidateFor({required String userId}) => Future.value();

  @override
  Future<void> bumpMrEpoch() => Future.value();

  @override
  Future<int> gcStaleWindows() => Future.value(0);
}
