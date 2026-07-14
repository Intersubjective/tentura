import 'package:tentura_server/domain/entity/realtime_watch_grant.dart';

/// Re-runs the authoritative visibility path and intersects requested subjects.
abstract interface class RealtimeWatchAuthorizationPort {
  Future<Set<String>> authorizeSubjects({
    required String viewerId,
    required RealtimeWatchDescriptor descriptor,
  });
}
