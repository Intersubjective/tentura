/// Post opacity floor reached at the end of the active window.
const kConstellationPostFadeFloor = 0.25;

const _fadeStart = Duration(hours: 48);
const _fadeEnd = Duration(hours: 72);

/// 1 until 48 h after [lastActivityAt], then linear down to
/// [kConstellationPostFadeFloor] at 72 h (and beyond).
double constellationPostFade({
  required DateTime lastActivityAt,
  required DateTime asOfUtc,
}) {
  final age = asOfUtc.difference(lastActivityAt);
  if (age <= _fadeStart) {
    return 1;
  }
  if (age >= _fadeEnd) {
    return kConstellationPostFadeFloor;
  }
  final t =
      (age - _fadeStart).inMicroseconds / (_fadeEnd - _fadeStart).inMicroseconds;
  return 1 - t * (1 - kConstellationPostFadeFloor);
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
