import 'notification_kind.dart';

/// Purpose-based grouping of the raw [NotificationKind]s.
///
/// Categories — not per-kind toggles — are the control granularity exposed to
/// users: per-kind switches cause decision fatigue and contradict the goal of
/// keeping people in control without annoying them.
enum NotificationCategory {
  /// The network is waiting on me; I block others. Highest stakes.
  asksOfMe,

  /// A resolution that lets me move forward.
  unblocksMe,

  /// Situational awareness; usually not an obligation.
  coordination,

  /// Social graph / invitations / relationship signals.
  connections,

  /// Background room hum. Lowest priority.
  ambient,
}

/// Single source of truth mapping a raw kind to its semantic category.
NotificationCategory categoryOf(NotificationKind kind) => switch (kind) {
  NotificationKind.needsMe ||
  NotificationKind.staleRemind ||
  NotificationKind.roomAccess => NotificationCategory.asksOfMe,
  NotificationKind.blockerResolved ||
  NotificationKind.reviewReady => NotificationCategory.unblocksMe,
  NotificationKind.promiseMade ||
  NotificationKind.coordinationChanged ||
  NotificationKind.blockerOpened ||
  NotificationKind.commitmentEvent ||
  NotificationKind.commitmentDeclined ||
  NotificationKind.commitmentRemoved ||
  NotificationKind.commitmentReleased ||
  NotificationKind.commitmentCancelled ||
  NotificationKind.newRelay ||
  NotificationKind.roomMention ||
  NotificationKind.postFirstResponse ||
  NotificationKind.batonAsked ||
  NotificationKind.batonTaken ||
  NotificationKind.batonAllAnswered => NotificationCategory.coordination,
  NotificationKind.commitmentAccepted ||
  NotificationKind.commitmentResolved => NotificationCategory.unblocksMe,
  NotificationKind.commitmentRedirected => NotificationCategory.asksOfMe,
  NotificationKind.deadlineChanged => NotificationCategory.coordination,
  NotificationKind.deadlineReminder => NotificationCategory.asksOfMe,
  NotificationKind.inviteAccepted => NotificationCategory.connections,
  NotificationKind.roomActivityLowPriority => NotificationCategory.ambient,
  NotificationKind.planStepDue ||
  NotificationKind.planChangePending ||
  NotificationKind.planStepReminder ||
  NotificationKind.planStepOverdue => NotificationCategory.asksOfMe,
  NotificationKind.planStepTurn => NotificationCategory.unblocksMe,
  NotificationKind.planStepLate ||
  NotificationKind.planCantMake ||
  NotificationKind.planStepUnassigned => NotificationCategory.coordination,
  NotificationKind.planEdited ||
  NotificationKind.planStepDone => NotificationCategory.ambient,
};

/// Kinds that never trigger an immediate email even in [NotificationCategory]
/// `asksOfMe` (plan K15): a reminder or an overdue nudge is only useful as a
/// push, and an email minutes later would be noise.
const kNoImmediateEmailKinds = <NotificationKind>{
  NotificationKind.planStepReminder,
  NotificationKind.planStepOverdue,
};

/// Kinds left out of the email digest: time-bound nudges and plan hum.
const kNoDigestKinds = <NotificationKind>{
  NotificationKind.planStepReminder,
  NotificationKind.planStepOverdue,
  NotificationKind.planEdited,
  NotificationKind.planStepDone,
};

/// Parse a category from its persisted name, or null if unknown.
NotificationCategory? notificationCategoryFromName(String name) {
  for (final c in NotificationCategory.values) {
    if (c.name == name) {
      return c;
    }
  }
  return null;
}
