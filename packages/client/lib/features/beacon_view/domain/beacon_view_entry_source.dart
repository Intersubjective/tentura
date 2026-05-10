import 'package:tentura/consts.dart';

/// How the user arrived at beacon detail (route / push provenance).
enum BeaconViewEntrySource {
  myWork,
  inbox,
  forward,
  roomNotification,
  deepLink,
  unknown,
}

extension BeaconViewEntrySourceWire on BeaconViewEntrySource {
  String get wire => switch (this) {
    BeaconViewEntrySource.myWork => kBeaconEntryMyWork,
    BeaconViewEntrySource.inbox => kBeaconEntryInbox,
    BeaconViewEntrySource.forward => kBeaconEntryForward,
    BeaconViewEntrySource.roomNotification => kBeaconEntryRoomNotification,
    BeaconViewEntrySource.deepLink => kBeaconEntryDeepLink,
    BeaconViewEntrySource.unknown => kBeaconEntryUnknown,
  };

  static BeaconViewEntrySource parseQuery(String? raw) {
    if (raw == null || raw.isEmpty) return BeaconViewEntrySource.unknown;
    switch (raw.trim().toLowerCase()) {
      case kBeaconEntryMyWork:
        return BeaconViewEntrySource.myWork;
      case kBeaconEntryInbox:
        return BeaconViewEntrySource.inbox;
      case kBeaconEntryForward:
        return BeaconViewEntrySource.forward;
      case kBeaconEntryRoomNotification:
        return BeaconViewEntrySource.roomNotification;
      case kBeaconEntryDeepLink:
        return BeaconViewEntrySource.deepLink;
      case kBeaconEntryUnknown:
        return BeaconViewEntrySource.unknown;
      default:
        return BeaconViewEntrySource.unknown;
    }
  }
}

/// If [isDeepLink] is truthy, ignore spoofed `entry` query (external URLs).
BeaconViewEntrySource normalizeBeaconViewEntry({
  required String? isDeepLink,
  required BeaconViewEntrySource rawFromQuery,
}) {
  final dl = isDeepLink?.trim().toLowerCase();
  final deep = dl == '1' ||
      dl == 'true' ||
      dl == 'yes';
  if (deep) return BeaconViewEntrySource.deepLink;
  return rawFromQuery;
}
