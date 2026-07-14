import 'package:tentura/domain/entity/realtime/realtime_watch.dart';

/// Obtains a server-authorized, short-lived grant for a fetched projection.
abstract interface class RealtimeWatchGrantPort {
  Future<RealtimeWatchGrant> requestGrant(
    RealtimeWatchDescriptor descriptor,
  );
}
