enum RealtimeWatchScope {
  graph,
  profile,
  people;

  static RealtimeWatchScope? fromWire(Object? value) => switch (value) {
    'graph' => graph,
    'profile' => profile,
    'people' => people,
    _ => null,
  };
}

/// Closed description of an authoritative projection the client just fetched.
final class RealtimeWatchDescriptor {
  const RealtimeWatchDescriptor({
    required this.scope,
    required this.requestedSubjectIds,
    this.focusId,
    this.context,
    this.positiveOnly,
    this.profileId,
    this.beaconId,
  });

  final RealtimeWatchScope scope;
  final Set<String> requestedSubjectIds;

  final String? focusId;
  final String? context;
  final bool? positiveOnly;

  final String? profileId;
  final String? beaconId;
}

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

/// Verified, purpose-bound claims used only by the WebSocket registry.
final class RealtimeWatchGrantClaims {
  const RealtimeWatchGrantClaims({
    required this.viewerId,
    required this.scope,
    required this.subjectIds,
    required this.expiresAt,
    required this.tokenId,
  });

  final String viewerId;
  final RealtimeWatchScope scope;
  final Set<String> subjectIds;
  final DateTime expiresAt;
  final String tokenId;
}
