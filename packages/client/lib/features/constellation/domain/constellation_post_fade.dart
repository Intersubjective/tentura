import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'entity/constellation_field.dart';

/// Post opacity floor reached when the Post expires.
const kConstellationPostFadeFloor = 0.25;

const _fadeWindow = Duration(hours: 24);

/// Whether [post] is on the Field at [asOfUtc]: open (a closed Post keeps its
/// `expiresAt`) and not yet at its deadline. A Post without a deadline never
/// expires.
bool constellationPostActive(ConstellationPost post, DateTime asOfUtc) =>
    post.status == BeaconStatus.open.smallintValue &&
    (post.expiresAt == null || post.expiresAt!.isAfter(asOfUtc));

/// 1 while [_fadeWindow] or more is left before [expiresAt], then linear down
/// to [kConstellationPostFadeFloor] when nothing is left.
double constellationPostFade({
  required DateTime? expiresAt,
  required DateTime asOfUtc,
}) {
  if (expiresAt == null) {
    return 1;
  }
  final left = expiresAt.difference(asOfUtc);
  if (left >= _fadeWindow) {
    return 1;
  }
  if (left <= Duration.zero) {
    return kConstellationPostFadeFloor;
  }
  final t = left.inMicroseconds / _fadeWindow.inMicroseconds;
  return kConstellationPostFadeFloor + t * (1 - kConstellationPostFadeFloor);
}

/// «+N» chip count: members the server hid plus visible members that were not
/// placed because of the render cap.
int constellationPostOverflowCount({
  required int hiddenReachCount,
  required int visibleMemberCount,
  required int placedMemberCount,
}) =>
    hiddenReachCount +
    (visibleMemberCount > placedMemberCount
        ? visibleMemberCount - placedMemberCount
        : 0);
