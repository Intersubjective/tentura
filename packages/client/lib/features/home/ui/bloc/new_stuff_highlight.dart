import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart' show NewStuffCubit;

/// Row/card classification for [NewStuffCubit] markers (Inbox / My Work).
enum InboxRowHighlightKind {
  none,

  /// New forward (or inbox) activity since last Inbox visit.
  newForwardActivity,

  /// Beacon content changed since last visit without newer forward activity.
  updatedBeaconOnly,
}

enum MyWorkCardHighlightKind {
  none,

  /// Beacon created after last My Work visit.
  newBeacon,

  /// Beacon edited after last visit (already existed at or before last visit).
  updatedBeaconOnly,
}
