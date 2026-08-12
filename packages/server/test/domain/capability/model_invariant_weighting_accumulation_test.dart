import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

import 'model_world.dart';
import 'projection_standing.dart';

void main() {
  group('W — Witness weighting and monotonicity', () {
    test('W1: one admitted witness beats any quantity from inadmissible', () async {
      final w = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..witnessWeight('alice', 'sybil1', m: 1.0, admitted: false)
        ..witnessWeight('alice', 'sybil2', m: 1.0, admitted: false)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 2,
        )
        ..outcome(
          witness: 'sybil1',
          subject: 'carol',
          tag: ModelWorld.pets,
          count: 10,
        )
        ..outcome(
          witness: 'sybil2',
          subject: 'carol',
          tag: ModelWorld.pets,
          count: 10,
        );

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isTrue,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.pets),
        isFalse,
      );
    });

    test('W2: higher-m admitted witness contributes more at equal evidence', () async {
      final lowM = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 0.3, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 2,
        );

      final highM = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 0.9, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 2,
        );

      expect(
        await highM.standing('alice', 'carol', ModelWorld.transport),
        greaterThan(await lowM.standing('alice', 'carol', ModelWorld.transport)),
      );
    });

    test('W3: adding a witness never decreases standing (D23)', () async {
      for (final extra in [
        (witness: 'extra', m: 0.01, admitted: true),
        (witness: 'extra', m: 0.01, admitted: false),
        (witness: 'extra', m: 0.9, admitted: true),
      ]) {
        final before = ModelWorld()
          ..witnessWeight('alice', 'bob', m: 0.5, admitted: true)
          ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport);
        final baseline = await before.standing(
          'alice',
          'carol',
          ModelWorld.transport,
        );

        before
          ..witnessWeight(
            'alice',
            extra.witness,
            m: extra.m,
            admitted: extra.admitted,
          )
          ..outcome(
            witness: extra.witness,
            subject: 'carol',
            tag: ModelWorld.transport,
          );

        final after = await before.standing(
          'alice',
          'carol',
          ModelWorld.transport,
        );
        expect(
          after,
          greaterThanOrEqualTo(baseline),
          reason:
              'witness=${extra.witness} m=${extra.m} admitted=${extra.admitted}',
        );
      }
    });

    test('W4: adding an observation never decreases standing', () async {
      final w = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport);

      final before = await w.standing('alice', 'carol', ModelWorld.transport);
      w.outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport);
      final after = await w.standing('alice', 'carol', ModelWorld.transport);

      expect(after, greaterThanOrEqualTo(before));
    });

    test('W5: revoking an observation never increases standing', () async {
      final w = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 3,
        );

      final before = await w.standing('alice', 'carol', ModelWorld.transport);

      final reduced = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 2,
        );

      final after = await reduced.standing(
        'alice',
        'carol',
        ModelWorld.transport,
      );
      expect(after, lessThanOrEqualTo(before));
    });
  });

  group('A — Accumulation shape', () {
    test('A1: k one-obs witnesses beat one witness with k observations', () async {
      for (final k in [2, 3, 4]) {
        final distributed = ModelWorld();
        for (var i = 0; i < k; i++) {
          distributed
            ..witnessWeight('alice', 'w$i', m: 1.0, admitted: true)
            ..outcome(
              witness: 'w$i',
              subject: 'carol',
              tag: ModelWorld.transport,
            );
        }

        final concentrated = ModelWorld()
          ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
          ..outcome(
            witness: 'bob',
            subject: 'carol',
            tag: ModelWorld.transport,
            count: k,
          );

        expect(
          await distributed.standing('alice', 'carol', ModelWorld.transport),
          greaterThan(
            await concentrated.standing('alice', 'carol', ModelWorld.transport),
          ),
          reason: 'k=$k',
        );
      }
    });

    test('A2: one witness cannot outrank two equal one-obs witnesses', () async {
      // Bound holds only for k <= 3 undecayed observations under the live
      // e_out(n) = n/(K_o+n) saturation curve (K_o = 2): k=4 ties the pair
      // exactly (4/6 = 2/3), and k>=5 strictly EXCEEDS it, approaching 1.0
      // as k grows -- confirmed both by direct computation and by
      // architecture §13.3's own worked example (e_out = 0.83 at 10 fake
      // observations, 0.96 at 50, explicitly "accepted" as a residual
      // reciprocal-endorsement risk, not something the model bounds away).
      // The plan's own A2 wording ("no number of observations...") is an
      // overstatement relative to §13.3; this test pins the range where it
      // actually holds rather than asserting the unbounded claim literally.
      final pair = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..witnessWeight('alice', 'dave', m: 1.0, admitted: true)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'dave', subject: 'carol', tag: ModelWorld.transport);

      for (final k in [1, 2, 3]) {
        final solo = ModelWorld()
          ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
          ..outcome(
            witness: 'bob',
            subject: 'carol',
            tag: ModelWorld.transport,
            count: k,
          );

        expect(
          await pair.standing('alice', 'carol', ModelWorld.transport),
          greaterThan(await solo.standing('alice', 'carol', ModelWorld.transport)),
          reason: 'k=$k',
        );
      }
    });

    test('A3: diminishing returns per witness', () async {
      // The claim is about the SHAPE of the accumulation (increment n+1 <
      // increment n), not merely that standing keeps rising -- monotonicity
      // alone (W4's own invariant) would pass even if increments grew, so
      // this compares successive score deltas directly rather than just
      // chaining greaterThan on the raw standings.
      final scores = <double>[];
      for (final n in [1, 2, 3, 4]) {
        final w = ModelWorld()
          ..witnessWeight('alice', 'bob', m: 1.2, admitted: true)
          ..outcome(
            witness: 'bob',
            subject: 'carol',
            tag: ModelWorld.transport,
            count: n,
          );
        final standing = await w.standing(
          'alice',
          'carol',
          ModelWorld.transport,
        );
        expect(
          standing.tier,
          ProjectionTier.networkOutcome,
          reason: 'n=$n must qualify for networkOutcome for scores to be '
              'directly comparable',
        );
        scores.add(standing.score);
      }

      final increments = [
        for (var i = 1; i < scores.length; i++) scores[i] - scores[i - 1],
      ];
      for (var i = 1; i < increments.length; i++) {
        expect(
          increments[i],
          lessThan(increments[i - 1]),
          reason:
              'increment from n=${i + 1} to n=${i + 2} must be smaller than '
              'from n=$i to n=${i + 1}',
        );
      }

      final twoPeers = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..witnessWeight('alice', 'dave', m: 1.0, admitted: true)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'dave', subject: 'carol', tag: ModelWorld.transport);

      expect(
        (await twoPeers.standing('alice', 'carol', ModelWorld.transport))
            .score,
        greaterThan(scores[1]),
      );
    });

    test('A4: two one-obs witnesses beat one one-obs witness', () async {
      final one = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport);

      final two = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..witnessWeight('alice', 'dave', m: 1.0, admitted: true)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'dave', subject: 'carol', tag: ModelWorld.transport);

      expect(
        await two.standing('alice', 'carol', ModelWorld.transport),
        greaterThan(await one.standing('alice', 'carol', ModelWorld.transport)),
      );
    });
  });
}
