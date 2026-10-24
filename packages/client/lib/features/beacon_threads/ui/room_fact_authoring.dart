import 'package:flutter/widgets.dart';

/// A room host that can open its own Add-fact form (#481).
///
/// The room body finds it with `context.read<RoomFactAuthoring?>()`, so it
/// needs no import of the Request feature. Request rooms provide one
/// (BeaconViewScope); Post rooms do not, and then the empty fact picker
/// offers no "Pin your first fact".
abstract interface class RoomFactAuthoring {
  /// Whether the viewer may pin a fact in this room right now.
  bool get canAddFact;

  /// Opens the Add-fact form over [context]; completes with true when a fact
  /// was pinned, false when the form was cancelled or dismissed.
  Future<bool> openAddFact(BuildContext context);
}
