import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/band_candidate_port.dart';

@Injectable(
  as: BandCandidatePort,
  env: [Environment.test],
  order: 1,
)
class BandCandidateRepositoryMock implements BandCandidatePort {
  @override
  Future<List<BandCandidate>> candidatesFor({
    required String egoId,
    required String beaconId,
    required String normalizedContext,
  }) => Future.value(const []);

  @override
  Future<Set<String>> recentlyForwardedTo({
    required String egoId,
    required int withinDays,
  }) => Future.value(const {});
}
