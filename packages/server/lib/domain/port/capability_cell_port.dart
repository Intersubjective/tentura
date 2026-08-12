import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

abstract interface class CapabilityCellPort {
  Future<List<WitnessCellRow>> fetchCells({
    required List<String> subjectIds,
    required List<String> tagSlugs,
    required List<WitnessWeight> admittedWitnesses,
  });

  Future<void> rebuildCell(CellRef ref);

  Future<List<CellRef>> claimExpiredCells({
    required int limit,
    required String leaseOwner,
  });
}
