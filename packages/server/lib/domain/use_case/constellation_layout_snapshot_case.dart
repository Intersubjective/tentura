import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/constellation_layout_snapshot.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_layout_snapshot_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ConstellationLayoutSnapshotCase extends UseCaseBase {
  ConstellationLayoutSnapshotCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ConstellationLayoutSnapshotRepositoryPort _repository;

  Future<List<ConstellationLayoutSnapshot>> list({required String viewerId}) =>
      _repository.list(viewerId);

  Future<ConstellationLayoutSnapshot> save({
    required String viewerId,
    required int kind,
    required int reason,
    required String clientOpId,
  }) {
    _checkOpId(clientOpId);
    if (kind < 0 ||
        kind >= ConstellationLayoutSnapshotKind.values.length ||
        reason < 0 ||
        reason >= ConstellationLayoutSnapshotReason.values.length) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
        description: 'Unknown layout snapshot kind or reason',
      );
    }
    return _repository.save(
      viewerId: viewerId,
      kind: ConstellationLayoutSnapshotKind.values[kind],
      reason: ConstellationLayoutSnapshotReason.values[reason],
      clientOpId: clientOpId,
    );
  }

  Future<ConstellationLayoutSnapshot> restore({
    required String viewerId,
    required String snapshotId,
    required String clientOpId,
  }) {
    _checkOpId(clientOpId);
    return _repository.restore(
      viewerId: viewerId,
      snapshotId: snapshotId,
      clientOpId: clientOpId,
    );
  }

  void _checkOpId(String clientOpId) {
    if (clientOpId.isEmpty || clientOpId.length > 64) {
      throw ConstellationException(
        constellationCode: ConstellationExceptionCode.invalidTarget,
        description:
            'A layout snapshot needs an operation id of 1 to 64 '
            'characters',
      );
    }
  }
}
