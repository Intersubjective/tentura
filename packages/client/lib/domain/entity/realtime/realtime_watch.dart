enum RealtimeWatchScope { graph, profile, people }

/// Closed description of an authoritative projection the client just fetched.
///
/// Subject IDs are sent only to the authenticated grant endpoint. The socket
/// receives the resulting opaque grant, never this descriptor.
final class RealtimeWatchDescriptor {
  const RealtimeWatchDescriptor.graph({
    required this.requestedSubjectIds,
    required String this.focusId,
    required String this.context,
    required bool this.positiveOnly,
  }) : scope = RealtimeWatchScope.graph,
       profileId = null,
       beaconId = null;

  const RealtimeWatchDescriptor.profile({
    required this.requestedSubjectIds,
    required String this.profileId,
  }) : scope = RealtimeWatchScope.profile,
       focusId = null,
       context = null,
       positiveOnly = null,
       beaconId = null;

  const RealtimeWatchDescriptor.people({
    required this.requestedSubjectIds,
    required String this.beaconId,
  }) : scope = RealtimeWatchScope.people,
       focusId = null,
       context = null,
       positiveOnly = null,
       profileId = null;

  final RealtimeWatchScope scope;
  final Set<String> requestedSubjectIds;

  final String? focusId;
  final String? context;
  final bool? positiveOnly;

  final String? profileId;
  final String? beaconId;
}

/// Short-lived server authorization for one active projection watch.
final class RealtimeWatchGrant {
  const RealtimeWatchGrant({
    required this.token,
    required this.scope,
    required this.authorizedSubjectIds,
    required this.expiresAt,
  });

  final String token;
  final RealtimeWatchScope scope;
  final Set<String> authorizedSubjectIds;
  final DateTime expiresAt;
}
