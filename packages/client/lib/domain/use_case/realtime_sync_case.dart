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

  Stream<RealtimeEntityChange> changesForAggregate({
    required Set<RealtimeEntityKind> kinds,
    required String aggregateId,
  }) => changesFor(
    kinds,
  ).where((change) => change.aggregateId == aggregateId);
}
