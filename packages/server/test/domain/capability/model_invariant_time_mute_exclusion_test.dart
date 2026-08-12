import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

import 'model_world.dart';
import 'projection_standing.dart';

void main() {
  group('T — Time', () {
    test('T1: more recent identical evidence outranks older', () async {
      final recent = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          daysAgo: 10,
        );

      final stale = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          daysAgo: 200,
        );

      expect(
        await recent.standing('alice', 'carol', ModelWorld.transport),
        greaterThan(await stale.standing('alice', 'carol', ModelWorld.transport)),
      );
    });

    test('T2: seed decays faster than outcome', () async {
      final midAge = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..witnessWeight('alice', 'dylan', m: 1.0, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          daysAgo: 40,
        )
        ..seed(
          witness: 'dylan',
          subject: 'carol',
          tag: ModelWorld.manualWork,
          daysAgo: 40,
        );

      expect(
        await midAge.standing('alice', 'carol', ModelWorld.transport),
        greaterThan(
          await midAge.standing('alice', 'carol', ModelWorld.manualWork),
        ),
      );

      final later = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..witnessWeight('alice', 'dylan', m: 1.0, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          daysAgo: 70,
        )
        ..seed(
          witness: 'dylan',
          subject: 'carol',
          tag: ModelWorld.manualWork,
          daysAgo: 200,
        );

      expect(
        await later.hasProjection('alice', 'carol', ModelWorld.transport),
        isTrue,
      );
      expect(
        await later.hasProjection('alice', 'carol', ModelWorld.manualWork),
        isFalse,
      );
    });

    test('T3: out-of-window evidence contributes nothing', () async {
      final w = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          daysAgo: kCapWindowMonths * 30 + 5,
        );

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );

      final empty = ModelWorld()..ego('alice');
      expect(
        await w.standing('alice', 'carol', ModelWorld.transport),
        equals(await empty.standing('alice', 'carol', ModelWorld.transport)),
      );
    });

    test('T4: fresh seed does not outrank stale in-window outcome', () async {
      final w = ModelWorld()
        ..witnessWeight('alice', 'bob', m: 1.0, admitted: true)
        ..witnessWeight('alice', 'dylan', m: 1.0, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          daysAgo: 80,
        )
        ..seed(
          witness: 'dylan',
          subject: 'carol',
          tag: ModelWorld.manualWork,
          daysAgo: 0,
        );

      expect(
        await w.standing('alice', 'carol', ModelWorld.transport),
        greaterThan(await w.standing('alice', 'carol', ModelWorld.manualWork)),
      );
    });
  });

  group('M — Mute and tombstone', () {
    test('M1: subject mute suppresses network tiers for every ego', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('eve', 'bob')
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          strengthOverride: 0.35,
        )
        ..seed(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          strengthOverride: 0.30,
        );

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isTrue,
      );
      expect(
        await w.hasProjection('eve', 'carol', ModelWorld.transport),
        isTrue,
      );

      w.mute('carol', ModelWorld.transport);
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await w.hasProjection('eve', 'carol', ModelWorld.transport),
        isFalse,
      );
    });

    test('M2: subject mute never suppresses ego own evidence', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..ownOutcome(egoId: 'alice', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          strengthOverride: 0.35,
        )
        ..seed(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          strengthOverride: 0.30,
        )
        ..mute('carol', ModelWorld.transport);

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isTrue,
      );
      final rows = await w.project(
        egoId: 'alice',
        subjectIds: ['carol'],
        tagSlugs: [ModelWorld.transport],
      );
      expect(rows.single.tier, ProjectionTier.ownOutcome);
    });

    test('M3: mute is per (subject, tag) pair', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'bob', subject: 'alex', tag: ModelWorld.transport)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.pets)
        ..mute('carol', ModelWorld.transport);

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await w.hasProjection('alice', 'alex', ModelWorld.transport),
        isTrue,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.pets),
        isTrue,
      );
    });

    test('M4: ego tombstone suppresses all tiers for that ego only', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('eve', 'bob')
        ..ownOutcome(egoId: 'alice', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.pets)
        ..tombstone(egoId: 'alice', subject: 'carol', tag: ModelWorld.transport);

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.pets),
        isTrue,
      );
      expect(
        await w.hasProjection('eve', 'carol', ModelWorld.pets),
        isTrue,
      );
    });
  });

  group('X — Exclusions', () {
    test('X1: self-witnessed evidence contributes nothing', () async {
      final w = ModelWorld()
        ..vouches('alice', 'carol')
        ..outcome(witness: 'carol', subject: 'carol', tag: ModelWorld.transport);

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
    });

    test('X2: commitRole contributes nothing to anyone', () async {
      // commitRole is excluded at the repository read boundary (C5) and never
      // materializes into cells or own-evidence ports — projection stays empty.
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..ego('carol');

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await w.hasProjection('carol', 'carol', ModelWorld.transport),
        isFalse,
      );
    });

    test('X3: private label only on author own tier', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..ownRouting(egoId: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.pets);

      expect(
        await w.hasProjection('bob', 'carol', ModelWorld.transport),
        isTrue,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.pets),
        isTrue,
      );
    });

    test('X4: blocks remove witness contribution in both directions', () async {
      final egoWitness = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('alice', 'dave')
        ..block('alice', 'bob')
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'dave', subject: 'carol', tag: ModelWorld.pets);

      expect(
        await egoWitness.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await egoWitness.hasProjection('alice', 'carol', ModelWorld.pets),
        isTrue,
      );

      final witnessSubject = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('alice', 'dave')
        ..block('bob', 'carol')
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'bob', subject: 'other', tag: ModelWorld.tools)
        ..outcome(witness: 'dave', subject: 'carol', tag: ModelWorld.pets);

      expect(
        await witnessSubject.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await witnessSubject.hasProjection('alice', 'carol', ModelWorld.pets),
        isTrue,
      );
      expect(
        await witnessSubject.hasProjection('alice', 'other', ModelWorld.tools),
        isTrue,
      );
    });
  });
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
