/// Product-shaped push notification kinds (coordination semantics).
enum NotificationKind {
  needsMe,
  promiseMade,
  coordinationChanged,
  blockerOpened,
  blockerResolved,
  roomAccess,
  newRelay,
  commitmentEvent,
  reviewReady,
  roomActivityLowPriority,

  /// Personal `@handle` mention in room chat (coordination; default-on push).
  roomMention,
  staleRemind,
  inviteAccepted,
  commitmentDeclined,
  commitmentRemoved,
}
