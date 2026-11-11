@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'each race round has its own test lifecycle under parallel PG load',
    () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          'test',
          '-j',
          '4',
          '--reporter=json',
          '--name=bud ∥ block|withdraw ∥ accept|PostCase.publish',
          'test/domain/use_case/post_bud_concurrency_pg_test.dart',
          'test/domain/use_case/post_case_publish_without_meritrank_pg_test.dart',
        ],
        environment: {
          ...Platform.environment,
          'TENTURA_PG_TESTS_REQUIRED': '1',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      final names = <String>[];
      for (final line in const LineSplitter().convert(
        result.stdout as String,
      )) {
        // Dart's build hooks may print before the JSON reporter starts.
        if (!line.startsWith('{')) continue;
        final event = jsonDecode(line) as Map<String, dynamic>;
        if (event['type'] != 'testStart') continue;
        final test = event['test'] as Map<String, dynamic>;
        names.add(test['name'] as String);
      }
      for (final scenario in [
        'bud ∥ block(budder, invitee)',
        'withdraw ∥ accept',
      ]) {
        expect(
          names.where(
            (name) => name.startsWith('Post bud concurrency $scenario'),
          ),
          unorderedEquals([
            for (var round = 0; round < 6; round++)
              'Post bud concurrency $scenario round $round',
          ]),
          reason:
              'Each schedule must finish before the next test can reset its '
              'fixtures; six rounds must not share one 30-second test budget.',
        );
      }
      const publishSuite = 'PostCase.publish on a database without MeritRank';
      const absentFunctionTest =
          'the MeritRank function is absent from public in this database';
      const missingTrustTest =
          'fails the whole call with a domain error and writes nothing when a '
          'recipient has no trust edge';
      expect(
        names.where(
          (name) => name.startsWith('PostCase.publish on a database'),
        ),
        containsAll([
          '$publishSuite $absentFunctionTest',
          '$publishSuite $missingTrustTest',
        ]),
      );
    },
    // This orchestrates fourteen child tests; each child retains its own
    // default 30-second timeout.
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
