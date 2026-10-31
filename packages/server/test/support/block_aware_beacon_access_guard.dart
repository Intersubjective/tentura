import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';

import 'fake_beacon_access_guard.dart';

/// Simulates S6 `beacon_can_read_content` block_hides(author, viewer) for unit
/// tests that do not hit Postgres.
class BlockAwareBeaconAccessGuard implements BeaconAccessGuard {
  BlockAwareBeaconAccessGuard({
    required UserBlockRepositoryPort blocks,
    required BeaconRepositoryPort beaconRepo,
    FakeBeaconAccessGuard? fallback,
  }) : _blocks = blocks,
       _beaconRepo = beaconRepo,
       _fallback = fallback ?? FakeBeaconAccessGuard();

  final UserBlockRepositoryPort _blocks;
  final BeaconRepositoryPort _beaconRepo;
  final FakeBeaconAccessGuard _fallback;

  @override
  Future<bool> canReadContent({
    required String beaconId,
    required String viewerId,
  }) async {
    final beacon = await _beaconRepo.getBeaconById(beaconId: beaconId);
    if (await _blocks.isBlockedPair(a: viewerId, b: beacon.author.id)) {
      return false;
    }
    return _fallback.canReadContent(beaconId: beaconId, viewerId: viewerId);
  }

  @override
  Future<Set<String>> readableContentIds({
    required Iterable<String> beaconIds,
    required String viewerId,
  }) async => {
    for (final beaconId in beaconIds)
      if (await canReadContent(beaconId: beaconId, viewerId: viewerId))
        beaconId,
  };

  @override
  Future<Set<String>> readableContentViewerIds({
    required String beaconId,
    required Iterable<String> viewerIds,
  }) async => {
    for (final viewerId in viewerIds)
      if (await canReadContent(beaconId: beaconId, viewerId: viewerId))
        viewerId,
  };

  @override
  Future<bool> canReadInvolvement({
    required String beaconId,
    required String viewerId,
  }) =>
      _fallback.canReadInvolvement(beaconId: beaconId, viewerId: viewerId);

  @override
  Future<bool> canReadTombstone({
    required String beaconId,
    required String viewerId,
  }) =>
      _fallback.canReadTombstone(beaconId: beaconId, viewerId: viewerId);
}
