import 'package:test/test.dart';
import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

void main() {
  group('capability_consts', () {
    test('half-lives are in seconds, not days', () {
      expect(kCapHalfLifeOutSeconds, 31536000);
      expect(kCapHalfLifeSeedSeconds, 7776000);
      expect(kCapHalfLifeOutSeconds, 365 * 86400);
      expect(kCapHalfLifeSeedSeconds, 90 * 86400);
      // A mistaken Days constant would be 365 and 90 — not seconds-scale.
      expect(kCapHalfLifeOutSeconds, greaterThan(86400));
      expect(kCapHalfLifeSeedSeconds, greaterThan(86400));
    });

    test('threshold and window constants match plan §2', () {
      expect(kCapKOut, 2.0);
      expect(kCapKSeed, 1.0);
      expect(kCapThetaOut, 0.30);
      expect(kCapThetaSeed, 0.25);
      expect(kCapWindowMonths, 24);
      expect(kCapFloorPercentile, 0.33);
      expect(kCapWitnessWindowK, 200);
      expect(kCapBandEvidenceSlots, 3);
      expect(kCapExplorationSlots, 2);
      expect(kCapMaxTagsPerSubjectBeacon, 3);
      expect(kCapExplorationRecentForwardDays, 30);
      expect(kCapWindowTtlMinutes, 15);
    });
  });

  group('ProjectionTier precedence', () {
    test('declaration order is channel-first precedence', () {
      expect(ProjectionTier.values, [
        ProjectionTier.ownOutcome,
        ProjectionTier.networkOutcome,
        ProjectionTier.ownRouting,
        ProjectionTier.networkSeed,
      ]);
    });

    test('index reflects strict ordering for D2 row-tier reduction', () {
      expect(
        ProjectionTier.ownOutcome.index,
        lessThan(ProjectionTier.networkOutcome.index),
      );
      expect(
        ProjectionTier.networkOutcome.index,
        lessThan(ProjectionTier.ownRouting.index),
      );
      expect(
        ProjectionTier.ownRouting.index,
        lessThan(ProjectionTier.networkSeed.index),
      );
    });
  });

  group('capability_evidence_models contracts', () {
    test('ForwardBandRow allows null rowTier and empty labels for exploration', () {
      const row = ForwardBandRow(
        userId: 'u1',
        rank: 0,
        isExploration: true,
      );
      expect(row.rowTier, isNull);
      expect(row.labels, isEmpty);
      expect(row.isExploration, isTrue);
    });

    test('TagProjection carries tier without score', () {
      const projection = TagProjection(
        subjectUserId: 's1',
        tagSlug: 'transport',
        tier: ProjectionTier.networkOutcome,
      );
      expect(projection.tier, ProjectionTier.networkOutcome);
    });

    test('WitnessCellRow exposes effective strengths only', () {
      const cell = WitnessCellRow(
        observerUserId: 'w1',
        subjectUserId: 's1',
        tagSlug: 'transport',
        eOut: 0.4,
        eSeed: 0.1,
        m: 0.8,
      );
      expect(cell.eOut, 0.4);
      expect(cell.eSeed, 0.1);
    });

    test('EvidenceChannel distinguishes outcome vs seed', () {
      expect(EvidenceChannel.values, [EvidenceChannel.outcome, EvidenceChannel.seed]);
    });

    test('PromptStateValue wire order for invite seed prompt', () {
      expect(PromptStateValue.values, [
        PromptStateValue.pending,
        PromptStateValue.answered,
        PromptStateValue.skipped,
      ]);
    });
  });
}
