import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';

/// Domain-owned boundary for authoritative-projection invalidation signals.
abstract interface class RealtimeSyncPort {
  Stream<RealtimeEntityChange> get entityChanges;
  Stream<RealtimeCatchUp> get catchUps;
  Stream<RealtimeConnectionStatus> get connectionStatuses;

  void requestCatchUp(RealtimeCatchUpReason reason);
  void replaceWatch(RealtimeWatchGrant grant);
  void removeWatch(RealtimeWatchScope scope);
}
