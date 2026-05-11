import 'beacon_surface_mode.dart';
import 'beacon_view_entry_source.dart';

/// Pure initial surface resolution (see product plan).
BeaconSurfaceMode resolveInitialBeaconSurfaceMode({
  required BeaconViewEntrySource entry,
  required bool hasRoomAccess,
  required bool explicitRoomRequested,
  required bool explicitStatusRequested,
}) {
  // Non-null `viewTab` / `surface=status` implies Status even if `surface=room`
  // was also passed (query forgery / conflicting links).
  if (explicitStatusRequested) {
    return BeaconSurfaceMode.status;
  }

  if (explicitRoomRequested) {
    return hasRoomAccess ? BeaconSurfaceMode.room : BeaconSurfaceMode.status;
  }

  switch (entry) {
    case BeaconViewEntrySource.roomNotification:
      return hasRoomAccess ? BeaconSurfaceMode.room : BeaconSurfaceMode.status;

    case BeaconViewEntrySource.myWork:
    case BeaconViewEntrySource.inbox:
    case BeaconViewEntrySource.forward:
    case BeaconViewEntrySource.deepLink:
    case BeaconViewEntrySource.unknown:
      return BeaconSurfaceMode.status;
  }
}

/// `surface=room` / legacy room redirect / shared link `dest=room`.
bool explicitRoomSurfaceRequested({
  required String? surfaceQuery,
  required bool navigatedFromLegacyRoomPath,
  required bool sharedLinkDestRoom,
}) {
  if (navigatedFromLegacyRoomPath || sharedLinkDestRoom) return true;
  final s = surfaceQuery?.trim().toLowerCase();
  return s == 'room';
}

/// `surface=status` **or** any `viewTab` selects Status tabs (Overview / People / Activity).
bool explicitStatusSurfaceRequested({
  required String? surfaceQuery,
  required String? viewTab,
}) {
  final s = surfaceQuery?.trim().toLowerCase();
  if (s == 'status') return true;
  final vt = viewTab?.trim();
  return vt != null && vt.isNotEmpty;
}
