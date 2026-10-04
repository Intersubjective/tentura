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

  /// Personal participant mention in room chat (coordination; default-on push).
  roomMention,
  staleRemind,
  inviteAccepted,
  commitmentDeclined,
  commitmentRemoved,
  commitmentReleased,
  commitmentAccepted,
  commitmentResolved,
  commitmentCancelled,
  commitmentRedirected,
  deadlineChanged,
  deadlineReminder,

  /// A member's first response in a Post room, told to the Post author.
  postFirstResponse,

  /// «Who'll take it?» (baton) — plan §2.2/B3.
  batonAsked,
  batonTaken,
  batonAllAnswered,
}
