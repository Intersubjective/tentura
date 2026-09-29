import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/capability_cell_port.dart';

@Injectable(
  as: CapabilityCellPort,
  env: [Environment.test],
  order: 1,
)
class CapabilityCellRepositoryMock implements CapabilityCellPort {
  @override
  Future<List<WitnessCellRow>> fetchCells({
    required List<String> subjectIds,
    required List<String> tagSlugs,
    required List<WitnessWeight> admittedWitnesses,
  }) => Future.value(const []);

  @override
  Future<void> rebuildCell(CellRef ref) => Future.value();

  @override
  Future<List<CellRef>> claimExpiredCells({
    required int limit,
    required String leaseOwner,
  }) => Future.value(const []);

  @override
  Future<void> releaseSweepLease({
    required CellRef ref,
    required String leaseOwner,
  }) => Future.value();

  @override
  Future<int> gcOrphanGenerations({int limit = 100}) => Future.value(0);

  @override
  Future<DateTime?> nextExpiryAt(CellRef ref) => Future.value();
}
