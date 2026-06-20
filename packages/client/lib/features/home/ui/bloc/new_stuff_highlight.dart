import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart' show NewStuffCubit;

/// Row classification for [NewStuffCubit] markers (Inbox).
enum InboxRowHighlightKind {
  none,

  /// New forward (or inbox) activity since last Inbox visit.
  newForwardActivity,

  /// Beacon content changed since last visit without newer forward activity.
  updatedBeaconOnly,
}
