import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

/// Domain-owned boundary for authoritative-projection invalidation signals.
abstract interface class RealtimeSyncPort {
  Stream<RealtimeEntityChange> get entityChanges;
}
