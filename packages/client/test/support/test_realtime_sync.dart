import 'dart:async';

import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

final class TestRealtimeSyncPort implements RealtimeSyncPort {
  final _changes = StreamController<RealtimeEntityChange>.broadcast();
  final _catchUps = StreamController<RealtimeCatchUp>.broadcast();
  final _statuses = StreamController<RealtimeConnectionStatus>.broadcast();

  @override
  Stream<RealtimeCatchUp> get catchUps => _catchUps.stream;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses => _statuses.stream;

  @override
  Stream<RealtimeEntityChange> get entityChanges => _changes.stream;

  void emitChange(RealtimeEntityChange change) => _changes.add(change);

  void emitCatchUp({
    String accountId = 'account-a',
    int connectionEpoch = 2,
    RealtimeCatchUpReason reason = RealtimeCatchUpReason.webSocketReconnected,
  }) => _catchUps.add(
    RealtimeCatchUp(
      accountId: accountId,
      connectionEpoch: connectionEpoch,
      reason: reason,
    ),
  );

  void emitStatus(RealtimeConnectionStatus status) => _statuses.add(status);

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) =>
      emitCatchUp(reason: reason);

  @override
  Future<void> dispose() async {
    await _changes.close();
    await _catchUps.close();
    await _statuses.close();
  }
}

({RealtimeSyncCase case_, TestRealtimeSyncPort port}) buildTestRealtimeSync() {
  final port = TestRealtimeSyncPort();
  return (case_: RealtimeSyncCase(port), port: port);
}
