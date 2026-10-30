import 'dart:async';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';

/// Reloads an open Final check when the Request changes, the way the Request
/// page does (`RepositoryEventInvalidate` / `RepositoryEventUpdate`).
///
/// [readBeaconStatus] fills in a hint that carries only the id. The caller
/// decides what a non-review status means after [reload].
StreamSubscription<RepositoryEvent<Beacon>>? listenForClosureReviewHints({
  required Stream<RepositoryEvent<Beacon>>? changes,
  required String beaconId,
  required bool Function() isClosed,
  required Future<BeaconStatus?> Function()? readBeaconStatus,
  required Future<void> Function() reload,
  required void Function({required bool beaconLeftReview}) onReloaded,
}) {
  if (changes == null) return null;
  var generation = 0;
  return changes.listen((event) {
    if (isClosed() || event.id != beaconId) return;
    if (event is! RepositoryEventUpdate<Beacon> &&
        event is! RepositoryEventInvalidate<Beacon>) {
      return;
    }
    final gen = ++generation;
    unawaited(() async {
      BeaconStatus? beaconStatus = switch (event) {
        RepositoryEventUpdate<Beacon>(:final value) => value.status,
        _ => null,
      };
      beaconStatus ??= await readBeaconStatus?.call();
      if (isClosed() || gen != generation) return;
      await reload();
      if (isClosed() || gen != generation) return;
      onReloaded(
        beaconLeftReview:
            beaconStatus != null && beaconStatus != BeaconStatus.reviewOpen,
      );
    }());
  });
}
