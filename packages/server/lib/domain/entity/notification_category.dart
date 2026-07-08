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
      NotificationKind.roomAccess =>
        NotificationCategory.asksOfMe,
      NotificationKind.blockerResolved ||
      NotificationKind.reviewReady =>
        NotificationCategory.unblocksMe,
      NotificationKind.promiseMade ||
      NotificationKind.coordinationChanged ||
      NotificationKind.blockerOpened ||
      NotificationKind.commitmentEvent ||
      NotificationKind.newRelay =>
        NotificationCategory.coordination,
      NotificationKind.inviteAccepted => NotificationCategory.connections,
      NotificationKind.roomActivityLowPriority => NotificationCategory.ambient,
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
