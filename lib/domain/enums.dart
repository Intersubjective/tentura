enum WebSocketState {
  connected,
  disconnected,
}

enum UserPresenceStatus {
  unknown,
  online,
  offline,
  inactive,
}

enum ComplaintType {
  unknown,
  violatesCsaePolicy,
  violatesPlatformRules,
  accountDeletionRequest,
}

/// Derived availability view for request-receptiveness. Never stored or used as a
/// wire/database ordinal.
enum AvailabilityView {
  open,
  limited,
  paused,
}
