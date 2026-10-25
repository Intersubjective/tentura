import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/constellation_layout_snapshot.dart';
import 'package:tentura_server/domain/port/constellation_layout_snapshot_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_layout_snapshot_case.dart';
import 'package:tentura_server/env.dart';

/// «Rearrange everyone» saves the layout it is about to replace as a history
/// snapshot of its own kind, distinct from manual saves, restores and resets.
void main() {
  late _RecordingRepository repository;
  late ConstellationLayoutSnapshotCase useCase;

  setUp(() {
    repository = _RecordingRepository();
    useCase = ConstellationLayoutSnapshotCase(
      repository,
      env: Env(environment: Environment.test),
      logger: Logger('ConstellationLayoutSnapshotRebuildReasonTest'),
    );
  });

  test('a history snapshot can be saved with the rebuild reason', () async {
    final rebuildReason = ConstellationLayoutSnapshotReason.values.indexWhere(
      (reason) => reason.name == 'rebuild',
    );
    expect(
      rebuildReason,
      isNonNegative,
      reason: 'the snapshot reasons include rebuild',
    );

    final saved = await useCase.save(
      viewerId: 'U_viewer',
      kind: ConstellationLayoutSnapshotKind.history.index,
      reason: rebuildReason,
      clientOpId: 'op-rebuild',
    );

    expect(repository.saves, hasLength(1));
    expect(repository.saves.single.viewerId, 'U_viewer');
    expect(repository.saves.single.clientOpId, 'op-rebuild');
    expect(
      repository.saves.single.kind,
      ConstellationLayoutSnapshotKind.history,
    );
    expect(repository.saves.single.reason.name, 'rebuild');
    expect(saved.kind, ConstellationLayoutSnapshotKind.history);
    expect(saved.reason.name, 'rebuild');
  });
}

class _RecordingRepository
    implements ConstellationLayoutSnapshotRepositoryPort {
  final saves =
      <
        ({
          String viewerId,
          ConstellationLayoutSnapshotKind kind,
          ConstellationLayoutSnapshotReason reason,
          String clientOpId,
        })
      >[];

  @override
  Future<ConstellationLayoutSnapshot> save({
    required String viewerId,
    required ConstellationLayoutSnapshotKind kind,
    required ConstellationLayoutSnapshotReason reason,
    required String clientOpId,
  }) async {
    saves.add((
      viewerId: viewerId,
      kind: kind,
      reason: reason,
      clientOpId: clientOpId,
    ));
    return ConstellationLayoutSnapshot(
      id: 'LS_saved',
      kind: kind,
      reason: reason,
      anchorCount: 0,
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  Future<List<ConstellationLayoutSnapshot>> list(String viewerId) =>
      throw UnimplementedError();

  @override
  Future<ConstellationLayoutSnapshot> restore({
    required String viewerId,
    required String snapshotId,
    required String clientOpId,
  }) => throw UnimplementedError();

  @override
  Future<void> restoreFavourite({
    required String viewerId,
    required String snapshotId,
    required String clientOpId,
  }) => throw UnimplementedError();
}
