import 'package:flutter/widgets.dart';

import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_constants.dart';

/// Whether the ROOM surface is visible: CHAT tab selected or split room pane
/// mounted (plan §4.8 — replaces route-name probes).
bool isBeaconRoomPresented({
  required bool isSplit,
  required BeaconSurface selectedSurface,
}) => isSplit || selectedSurface == BeaconSurface.room;

typedef OpenBeaconGeneralAnchor =
    Future<void> Function({
      String? messageId,
      String? coordinationItemId,
    });

/// In-request coordination anchor navigation (plan §4.8).
///
/// Provided by [BeaconViewScreen] so message / coordination taps never push
/// [ThreadDetailRoute].
class BeaconRoomNavigationScope extends InheritedWidget {
  const BeaconRoomNavigationScope({
    required this.isRoomPresented,
    required this.roomLease,
    required this.openGeneralAnchor,
    required super.child,
    super.key,
  });

  final bool isRoomPresented;
  final BeaconRoomLease roomLease;
  final OpenBeaconGeneralAnchor openGeneralAnchor;

  static BeaconRoomNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BeaconRoomNavigationScope>();

  @override
  bool updateShouldNotify(BeaconRoomNavigationScope oldWidget) =>
      isRoomPresented != oldWidget.isRoomPresented ||
      roomLease != oldWidget.roomLease ||
      openGeneralAnchor != oldWidget.openGeneralAnchor;
}
