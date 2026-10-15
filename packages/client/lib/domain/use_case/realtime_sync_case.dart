import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';

/// UI-facing application boundary for realtime projection convergence.
@singleton
final class RealtimeSyncCase {
  const RealtimeSyncCase(this._syncPort);

  final RealtimeSyncPort _syncPort;

  Stream<RealtimeEntityChange> get entityChanges => _syncPort.entityChanges;
  Stream<RealtimeCatchUp> get catchUps => _syncPort.catchUps;
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      _syncPort.connectionStatuses;

  void requestCatchUp(RealtimeCatchUpReason reason) =>
      _syncPort.requestCatchUp(reason);

  Stream<RealtimeEntityChange> changesFor(Set<RealtimeEntityKind> kinds) =>
      entityChanges.where((change) => kinds.contains(change.kind));

  /// Block and unblock markers addressed to this account, whichever side of
  /// the block it is on and whichever session made it. The server's
  /// `user_block` trigger emits `constellation_field` with the blocker's id to
  /// both parties (m0232); trust and MR changes emit the same kind with id
  /// [globalConstellationFieldId] to everyone, so those are left out here.
  Stream<RealtimeEntityChange> get blockMarkers =>
      changesFor(const {RealtimeEntityKind.constellationField}).where(
        (change) => change.aggregateId != globalConstellationFieldId,
      );

  static const globalConstellationFieldId = 'global';

  Stream<RealtimeEntityChange> changesForAggregate({
    required Set<RealtimeEntityKind> kinds,
    required String aggregateId,
  }) => changesFor(
    kinds,
  ).where((change) => change.aggregateId == aggregateId);
}
