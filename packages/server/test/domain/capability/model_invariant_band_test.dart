import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/fnv1a64.dart';

import 'model_world.dart';

void main() {
  const beaconId = 'B_invariant_band';
  const ego = 'alice';

  group('B — Band behaviour', () {
    test('B1: zero-evidence candidate remains in exploration pool', () async {
      final w = ModelWorld()
        ..bandBeacon(beaconId: beaconId, needs: {ModelWorld.transport})
        ..bandCandidate(userId: 'carol', forwardMr: 0.9)
        ..bandCandidate(userId: 'empty_peer', forwardMr: 0.5)
        ..vouches(ego, 'bob')
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 2,
        );

      final band = await w.composeBand(egoId: ego);
      expect(band.any((row) => row.userId == 'empty_peer'), isTrue);
      expect(band.any((row) => row.isExploration), isTrue);
    });

    test('B2: band size is bounded regardless of evidence volume', () async {
      final w = ModelWorld()
        ..bandBeacon(beaconId: beaconId, needs: {ModelWorld.transport})
        ..vouches(ego, 'bob');

      for (var i = 0; i < 12; i++) {
        w
          ..bandCandidate(userId: 'peer_$i', forwardMr: 0.9 - i * 0.01)
          ..outcome(
            witness: 'bob',
            subject: 'peer_$i',
            tag: ModelWorld.transport,
          );
      }

      final band = await w.composeBand(egoId: ego);
      expect(
        band.length,
        lessThanOrEqualTo(kCapBandEvidenceSlots + kCapExplorationSlots),
      );
    });

    test('B3: only request needs appear in band labels', () async {
      final w = ModelWorld()
        ..bandBeacon(
          beaconId: beaconId,
          needs: {ModelWorld.transport},
          primaryNeedSlug: ModelWorld.transport,
        )
        ..bandCandidate(userId: 'carol', forwardMr: 0.9)
        ..vouches(ego, 'bob')
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 2,
        )
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.pets);

      final band = await w.composeBand(egoId: ego);
      final carol = band.firstWhere((row) => row.userId == 'carol');
      expect(
        carol.labels.every((label) => label.tagSlug == ModelWorld.transport),
        isTrue,
      );
      expect(carol.labels.any((label) => label.tagSlug == ModelWorld.pets), isFalse);
    });

    test('B4: exploration slots fill when pool is nonempty', () async {
      final w = ModelWorld()
        ..bandBeacon(beaconId: beaconId, needs: {ModelWorld.transport})
        ..bandCandidate(userId: 'carol', forwardMr: 0.9)
        ..bandCandidate(userId: 'explore_a', forwardMr: 0.6)
        ..bandCandidate(userId: 'explore_b', forwardMr: 0.5)
        ..vouches(ego, 'bob')
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 2,
        );

      final band = await w.composeBand(egoId: ego);
      final exploration = band.where((row) => row.isExploration).toList();
      expect(exploration, hasLength(kCapExplorationSlots));

      final pool = ['explore_a', 'explore_b'];
      final offset = fnv1a64Mod(beaconId, pool.length);
      expect(
        exploration.map((row) => row.userId).toList(),
        [pool[offset], pool[(offset + 1) % pool.length]],
      );
    });

    test('B5: band ordering is deterministic across runs', () async {
      final w = ModelWorld()
        ..bandBeacon(beaconId: beaconId, needs: {ModelWorld.transport, ModelWorld.tools})
        ..bandCandidate(userId: 'carol', forwardMr: 0.91)
        ..bandCandidate(userId: 'alex', forwardMr: 0.82)
        ..bandCandidate(userId: 'dave', forwardMr: 0.71)
        ..bandCandidate(userId: 'eve', forwardMr: 0.55)
        ..bandCandidate(userId: 'frank', forwardMr: 0.44)
        ..vouches(ego, 'bob')
        ..ownOutcome(egoId: ego, subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'bob', subject: 'alex', tag: ModelWorld.transport, count: 2)
        ..seed(witness: 'bob', subject: 'dave', tag: ModelWorld.tools);

      final first = await w.composeBand(egoId: ego);
      final second = await w.composeBand(egoId: ego);

      expect(
        first.map((row) => (row.userId, row.rank, row.isExploration)).toList(),
        second.map((row) => (row.userId, row.rank, row.isExploration)).toList(),
      );
      expect(first.map((row) => row.rank).toList(), [0, 1, 2, 3, 4]);
    });
  });
}
