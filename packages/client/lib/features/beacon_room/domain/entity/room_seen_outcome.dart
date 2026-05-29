/// Result of attempting to persist room read state to the server.
sealed class RoomSeenOutcome {
  const RoomSeenOutcome();
}

final class RoomSeenSucceeded extends RoomSeenOutcome {
  const RoomSeenSucceeded(this.persistedAt);

  final DateTime persistedAt;
}

final class RoomSeenDenied extends RoomSeenOutcome {
  const RoomSeenDenied();
}

final class RoomSeenFailed extends RoomSeenOutcome {
  const RoomSeenFailed(this.error);

  final Object error;
}
