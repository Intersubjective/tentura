import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/witness_window_policy.dart';

RawPeerFact _peer(String id, double mr, {bool trusted = false}) =>
    RawPeerFact(peerId: id, forwardMr: mr, explicitlyTrusted: trusted);

void main() {
  group('computeFloor', () {
    test('empty trusted vote list yields no floor', () {
      expect(computeFloor([]), isNull);
    });

    test('n=1 vote list floor equals that vouch score', () {
      expect(computeFloor([0.42]), closeTo(0.42, 1e-9));
    });
  });

  group('computeREgo', () {
    test('single peer uses max (that peer score)', () {
      expect(computeREgo([_peer('a', 0.75)]), closeTo(0.75, 1e-9));
    });

    test('two peers use max not average', () {
      expect(
        computeREgo([_peer('a', 0.5), _peer('b', 0.3)]),
        closeTo(0.5, 1e-9),
      );
    });

    test('outlier trio 0.5/0.02/0.015 yields r_ego = 0.02', () {
      final facts = RawWindowFacts(
        topPeers: [
          _peer('high', 0.5),
          _peer('mid', 0.02),
          _peer('low', 0.015),
        ],
        trustedScores: const [],
      );
      expect(computeREgo(facts.topPeers), closeTo(0.02, 1e-9));
    });
  });

  group('computeM', () {
    test('single peer m = 1.0', () {
      expect(
        computeM(forwardMr: 0.75, rEgo: 0.75),
        closeTo(1.0, 1e-9),
      );
    });

    test('outlier second peer m = 1.0 when r_ego = 0.02', () {
      expect(
        computeM(forwardMr: 0.02, rEgo: 0.02),
        closeTo(1.0, 1e-9),
      );
    });

    test('guards r_ego = 0', () {
      expect(computeM(forwardMr: 0.5, rEgo: 0), closeTo(0, 1e-9));
    });
  });

  group('computeWitnessWeights', () {
    test('empty vote list admits nobody', () {
      final weights = computeWitnessWeights(
        RawWindowFacts(
          topPeers: [_peer('a', 0.5), _peer('b', 0.3)],
          trustedScores: const [],
        ),
      );
      expect(weights.every((w) => !w.admitted), isTrue);
    });

    test('n=1 inviter vouch admits inviter at floor', () {
      const inviterMr = 0.42;
      final weights = computeWitnessWeights(
        RawWindowFacts(
          topPeers: [_peer('inviter', inviterMr, trusted: true)],
          trustedScores: const [inviterMr],
        ),
      );
      expect(weights, hasLength(1));
      expect(weights.single.witnessUserId, 'inviter');
      expect(weights.single.admitted, isTrue);
      expect(weights.single.m, closeTo(1.0, 1e-9));
    });

    test('explicit trust admits even when floor absent for others', () {
      final weights = computeWitnessWeights(
        RawWindowFacts(
          topPeers: [
            _peer('trusted', 0.1, trusted: true),
            _peer('other', 0.9),
          ],
          trustedScores: const [0.1],
        ),
      );
      final trusted = weights.firstWhere((w) => w.witnessUserId == 'trusted');
      final other = weights.firstWhere((w) => w.witnessUserId == 'other');
      expect(trusted.admitted, isTrue);
      expect(other.admitted, isTrue);
    });

    test('deterministic tie ordering preserved from topPeers input', () {
      final weights = computeWitnessWeights(
        RawWindowFacts(
          topPeers: [
            _peer('peer_b', 0.5),
            _peer('peer_a', 0.5),
          ],
          trustedScores: const [0.5],
        ),
      );
      expect(
        weights.map((w) => w.witnessUserId),
        ['peer_b', 'peer_a'],
      );
    });

    test('zero forward_mr peers are excluded upstream — policy never sees them', () {
      final weights = computeWitnessWeights(
        const RawWindowFacts(
          topPeers: [],
          trustedScores: [],
        ),
      );
      expect(weights, isEmpty);
    });
  });

  group('continuousPercentile', () {
    test('matches PostgreSQL percentile_cont for a trio', () {
      expect(
        continuousPercentile([0.5, 0.02, 0.015], 0.33),
        closeTo(0.0183, 1e-4),
      );
    });
  });
}
