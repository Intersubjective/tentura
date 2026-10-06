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

  /// Request plan («либретто», #220) — `plan-implementation.md` §4.6.
  /// Obligations: your step started / it is your turn / your step changed.
  planStepDue,
  planStepTurn,
  planChangePending,

  /// Optional: 15 minutes before start; once overdue (no immediate email,
  /// not in the digest — `kNoImmediateEmailKinds`, `kNoDigestKinds`).
  planStepReminder,
  planStepOverdue,

  /// Optional, to the Request author.
  planStepLate,
  planCantMake,
  planStepUnassigned,

  /// Ambient, never pushed.
  planEdited,
  planStepDone,
}
