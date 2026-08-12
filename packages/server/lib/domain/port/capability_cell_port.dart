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

  Future<void> releaseSweepLease({
    required CellRef ref,
    required String leaseOwner,
  });

  /// Deletes generation rows with no live ledger row and no cached cell.
  /// Takes [cap_cell_lock] per candidate before delete.
  Future<int> gcOrphanGenerations({int limit = 100});

  Future<DateTime?> nextExpiryAt(CellRef ref);
}
