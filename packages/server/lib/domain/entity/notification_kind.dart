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
  staleRemind,
  inviteAccepted,
  commitmentDeclined,
  commitmentRemoved,
}
