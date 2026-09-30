@Tags(['pg'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// tentura-ting: the shared dev database can claim a schema version whose
/// objects it lacks (`trust_project_pair` missing), which broke the block
/// tests that ran on it. Block tests must run on their own disposable database
/// at the head schema, so the state of the ambient database must not matter:
/// pointing `POSTGRES_DBNAME` at a database that does not exist must neither
/// fail nor skip them.
const _blockPgTests = [
  'test/data/repository/user_block_adversarial_pg_test.dart',
  'test/data/repository/user_block_visibility_pg_test.dart',
];

void main() {
  for (final path in _blockPgTests) {
    test(
      '$path runs green with an unusable ambient database',
      () async {
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['test', path, '-j', '1', '--reporter', 'expanded'],
          environment: {'POSTGRES_DBNAME': 'tentura_no_such_ambient_db'},
        );
        final output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, 0, reason: output);
        expect(
          output,
          isNot(contains('Skip:')),
          reason: 'tests were skipped instead of run:\n$output',
        );
        expect(output, contains('All tests passed!'), reason: output);
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
