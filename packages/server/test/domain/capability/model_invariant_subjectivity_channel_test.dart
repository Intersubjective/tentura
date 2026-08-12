import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

import 'model_world.dart';
import 'projection_standing.dart';

void main() {
  group('S — Subjectivity', () {
    test('S1: two egos with different admitted sets see different tag sets', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..reaches('eve', 'bob', mr: 0.9)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..seed(witness: 'bob', subject: 'carol', tag: ModelWorld.pets);

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isTrue,
      );
      expect(
        await w.hasProjection('eve', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await w.hasProjection('eve', 'carol', ModelWorld.pets),
        isFalse,
      );
    });

    test('S2: ego admitting nobody sees own-tier tags only', () async {
      final w = ModelWorld()
        ..ego('alice')
        ..ownOutcome(egoId: 'alice', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.pets, count: 5)
        ..seed(witness: 'dylan', subject: 'carol', tag: ModelWorld.tools, count: 5);

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isTrue,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.pets),
        isFalse,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.tools),
        isFalse,
      );
    });

    test('S3: subject actions cannot create tags for a viewer', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..ownRouting(egoId: 'carol', subject: 'carol', tag: ModelWorld.pets)
        ..ownOutcome(egoId: 'carol', subject: 'carol', tag: ModelWorld.tools)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport);

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isTrue,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.pets),
        isFalse,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.tools),
        isFalse,
      );

      w.mute('carol', ModelWorld.transport);
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
    });

    test('S4: unreachable witness evidence is invisible', () async {
      final w = ModelWorld()
        ..vouches('alice', 'dave')
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'dave', subject: 'carol', tag: ModelWorld.pets);

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.pets),
        isTrue,
      );
    });
  });

  group('C — Channel and precedence', () {
    test('C1: outcome-derived standing beats seed regardless of mass', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('alice', 'dylan')
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..seed(
          witness: 'dylan',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 20,
        );

      final rows = await w.project(
        egoId: 'alice',
        subjectIds: ['carol'],
        tagSlugs: [ModelWorld.transport],
      );
      expect(rows.single.tier, ProjectionTier.networkOutcome);

      final crossTag = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('alice', 'dylan')
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.tools)
        ..seed(
          witness: 'dylan',
          subject: 'carol',
          tag: ModelWorld.pets,
          count: 20,
        );

      expect(
        await crossTag.standing('alice', 'carol', ModelWorld.tools),
        greaterThan(await crossTag.standing('alice', 'carol', ModelWorld.pets)),
      );
    });

    test('C2: row-tier order ownOutcome > networkOutcome > ownRouting > networkSeed', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..ownOutcome(egoId: 'alice', subject: 'carol', tag: ModelWorld.transport)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.tools)
        ..ownRouting(egoId: 'alice', subject: 'carol', tag: ModelWorld.pets)
        ..seed(witness: 'bob', subject: 'carol', tag: ModelWorld.legalNavigation);

      final ownOut = await w.standing('alice', 'carol', ModelWorld.transport);
      final netOut = await w.standing('alice', 'carol', ModelWorld.tools);
      final ownRoute = await w.standing('alice', 'carol', ModelWorld.pets);
      final netSeed = await w.standing('alice', 'carol', ModelWorld.legalNavigation);

      expect(ownOut, greaterThan(netOut));
      expect(netOut, greaterThan(ownRoute));
      expect(ownRoute, greaterThan(netSeed));
    });

    test('C3: profile is outcome-only; seed-only subject empty on profile', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..seed(witness: 'bob', subject: 'carol', tag: ModelWorld.transport);

      expect(
        await w.hasProjection(
          'alice',
          'carol',
          ModelWorld.transport,
          surface: ProjectionSurface.profile,
        ),
        isFalse,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isTrue,
      );
    });

    test('C4: Alice worked case — transport beats manual_work', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('alice', 'dylan')
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          daysAgo: 10,
        )
        ..seed(
          witness: 'dylan',
          subject: 'carol',
          tag: ModelWorld.manualWork,
          daysAgo: 10,
        );

      expect(
        await w.standing('alice', 'carol', ModelWorld.transport),
        greaterThan(await w.standing('alice', 'carol', ModelWorld.manualWork)),
      );
    });

    test('C5: ordering unchanged when Dylan m exceeds Bob m', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('alice', 'dylan')
        ..witnessWeight('alice', 'bob', m: 0.8, admitted: true)
        ..witnessWeight('alice', 'dylan', m: 1.0, admitted: true)
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          count: 2,
        )
        ..seed(witness: 'dylan', subject: 'carol', tag: ModelWorld.manualWork);

      expect(
        await w.standing('alice', 'carol', ModelWorld.transport),
        greaterThan(await w.standing('alice', 'carol', ModelWorld.manualWork)),
      );
    });

    test('C6: aged outcome past window flips ordering', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('alice', 'dylan')
        ..outcome(
          witness: 'bob',
          subject: 'carol',
          tag: ModelWorld.transport,
          daysAgo: kCapWindowMonths * 30 + 1,
        )
        ..seed(
          witness: 'dylan',
          subject: 'carol',
          tag: ModelWorld.manualWork,
          daysAgo: 10,
        );

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isFalse,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.manualWork),
        isTrue,
      );
      expect(
        await w.standing('alice', 'carol', ModelWorld.manualWork),
        greaterThan(await w.standing('alice', 'carol', ModelWorld.transport)),
      );
    });

    test('C7: Dylan not admitted removes manual_work only', () async {
      final w = ModelWorld()
        ..vouches('alice', 'bob')
        ..vouches('alice', 'dylan')
        ..witnessWeight('alice', 'dylan', m: 0.8, admitted: false)
        ..outcome(witness: 'bob', subject: 'carol', tag: ModelWorld.transport)
        ..seed(witness: 'dylan', subject: 'carol', tag: ModelWorld.manualWork);

      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.manualWork),
        isFalse,
      );
      expect(
        await w.hasProjection('alice', 'carol', ModelWorld.transport),
        isTrue,
      );
    });
  });
}
