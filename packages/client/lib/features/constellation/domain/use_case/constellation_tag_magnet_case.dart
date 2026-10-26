import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../entity/constellation_tag_magnet.dart';
import '../port/constellation_tag_magnet_repository_port.dart';

/// Keeps the viewer's tag magnets on the server, so they survive a reload and
/// follow the viewer to other devices.
@lazySingleton
final class ConstellationTagMagnetCase extends UseCaseBase {
  ConstellationTagMagnetCase(
    this._repository,
    this._realtime, {
    required super.env,
    required super.logger,
  });

  final ConstellationTagMagnetRepositoryPort _repository;
  final RealtimeSyncCase _realtime;

  static const _uuid = Uuid();

  /// Fires when the viewer's tag state changed (a `person_tag` hint); the
  /// server publishes one on every magnet change, from any session.
  Stream<void> get changes =>
      _realtime.changesFor(const {RealtimeEntityKind.personTag});

  Future<List<ConstellationTagMagnet>> list() => _repository.list();

  Future<ConstellationTagMagnet> save({
    required String tagId,
    required double xUnits,
    required double yUnits,
  }) => _repository.upsert(
    tagId: tagId,
    xUnits: xUnits,
    yUnits: yUnits,
    clientOpId: _uuid.v4(),
  );

  Future<void> remove(String tagId) =>
      _repository.remove(tagId: tagId, clientOpId: _uuid.v4());
}
