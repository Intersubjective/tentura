// Pure domain tests use the workspace's transitive test dependency.
// ignore_for_file: depend_on_referenced_packages

import 'package:test/test.dart';

import 'fixtures/existing_layout_fixture_replay.dart';
import 'fixtures/resumable_layout_inputs.dart';
import 'fixtures/resumable_layout_probe.dart';

void main() {
  group(
    'resumable constellation layout',
    () {
      test('single-unit and uneven batches match one-shot full and incremental '
          'placement', () async {
        final cases = await runResumableLayoutProbe('stepping');
        final names = legacyLayoutInputs().keys;
        expect(cases.keys.toSet(), {
          for (final name in names) '$name/full',
          for (final name in names) '$name/incremental',
        });
        for (final entry in cases.entries) {
          final row = entry.value as Map<String, dynamic>;
          expect(row['oneUnit'], row['oneShot'], reason: entry.key);
          expect(row['uneven'], row['oneShot'], reason: entry.key);
        }
      });

      test('full plans preserve geometry for every existing layout fixture and '
          'seeded stability case', () async {
        final coverage = await runExistingLayoutFixtureCoverageProbe();
        final actual = await runResumableLayoutProbe('oracle');
        expect(
          (actual['sites'] as List<dynamic>).toSet(),
          (coverage['sites'] as List<dynamic>).toSet(),
        );
        final fixtures = actual['fixtures'] as Map<String, dynamic>;
        final counts = coverage['fixtureCounts'] as Map<String, dynamic>;
        expect(counts.keys.toSet(), existingLayoutFixtureFiles);
        expect(
          fixtures.length,
          counts.values.cast<int>().reduce((a, b) => a + b),
        );
        for (final entry in fixtures.entries) {
          final row = entry.value as Map<String, dynamic>;
          expect(
            row['full'],
            row['legacy'],
            reason: '${entry.key} (${row['site']})',
          );
        }
      });

      test('starting and taking zero units defers planning and obstacle '
          'preparation', () async {
        final cases = await runResumableLayoutProbe('deferred');
        expect(cases.keys.toSet(), {'full', 'incremental'});
        for (final value in cases.values) {
          final result = value as Map<String, dynamic>;
          expect(result['startVisits'], 0);
          expect(result['startOperations'], 0);
          final startReads = result['startInputReads'] as Map<String, dynamic>;
          expect(
            startReads.keys,
            containsAll({
              'nodeSizes',
              'satelliteRequestIdsByAuthor',
              'automaticKeptPeerIds',
              'pinnedPersonIds',
              'pinnedRequestIds',
              'supportPersonIds',
              'egoOwnRequestIds',
              'requestAuthorById',
              'anchorByNodeId',
              'footprints',
              'priorHints.positions',
              'priorHints.ring',
              'paths.depth',
              'paths.derived',
              'paths.parent',
              'paths.parentTier',
              'paths.attributed',
              'paths.keep',
              'paths.ring',
            }),
          );
          expect(startReads.values, everyElement(0));
          expect(result['zeroFinished'], isFalse);
          expect(result['zeroVisits'], 0);
          expect(result['zeroOperations'], 0);
          final zeroReads = result['zeroInputReads'] as Map<String, dynamic>;
          expect(zeroReads, startReads);
          expect(result['unfinishedResult'], 'StateError');
          expect(result['totalVisits'], greaterThan(0));
          expect(result['totalInputReads'], greaterThan(0));
          expect(result['completedNodes'], 1000);
        }
      });

      test('abandoning partially stepped jobs exposes no result and preserves '
          'published geometry', () async {
        final result = await runResumableLayoutProbe('cancellation');
        final attempts = result['attempts'] as List<dynamic>;
        expect(attempts.length, greaterThanOrEqualTo(3));
        for (final value in attempts) {
          final attempt = value as Map<String, dynamic>;
          expect(attempt['unfinishedResult'], 'StateError');
          expect(attempt['publishedAfter'], result['published']);
          expect(attempt['replacement'], attempt['expectedReplacement']);
          expect(attempt['inputAfter'], result['inputBefore']);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
