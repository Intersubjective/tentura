import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_rearrange_all.dart';
import 'package:tentura/features/constellation/domain/constellation_rearrange_layout_jobs.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

import 'fixtures/layout_work_gate.dart';

const _ego = 'ego';
const _spacing = 16.0;
const _n = 400;
const _tagCount = 6;

ConstellationEdgeRef _e(String src, String dst, int tier) => (
  src: src,
  dst: dst,
  tier: tier,
);

void main() {
  test(
    'rearrange-all layout job: per-unit work bound and exact match vs sync',
    () {
      final people = List<String>.generate(_n, (i) => 'p$i');
      final everyone = {...people, _ego};
      final paths = resolveConstellationPaths(
        egoId: _ego,
        visiblePeerIds: everyone,
        holderIds: everyone,
        edges: [for (final id in people) _e(_ego, id, 1)],
      );
      const nodeSize = (width: 64.0, height: 64.0);
      final nodeSizes = <String, ConstellationSize>{
        for (final id in everyone) id: nodeSize,
      };
      final tagMap = <String, Set<String>>{
        for (var t = 0; t < _tagCount; t++)
          'tag_$t': {
            for (final id in people)
              if (int.parse(id.substring(1)) % _tagCount == t) id,
          },
      };
      final input = (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: everyone,
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: nodeSizes,
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: _spacing,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
        rearrangeOwnTagPeopleByTagId: tagMap,
        rearrangeTagMagnetsByTagId: const <String, ConstellationPoint>{},
      );

      final expected = computeConstellationRearrangeAll(input);

      final job = ConstellationRearrangeAllLayoutJob(input);
      job.start();
      final counts = countStepWork(
        step: job.step,
        workOfLastStep: () => lastStepWorkOf(job),
      );
      expectStepWorkWithinBound(
        counts,
        bound: unitWorkBoundOf(job) * layoutWorkBoundHeadroom,
        label: 'ConstellationRearrangeAllLayoutJob',
      );
      final outcome = job.completeOutcome();
      expect(outcome.layout.positions, expected.layout.positions);
      expect(outcome.layout.ring, expected.layout.ring);
      expect(outcome.pinned, expected.pinned);
      expect(outcome.tagCentres, expected.tagCentres);
    },
  );
}
