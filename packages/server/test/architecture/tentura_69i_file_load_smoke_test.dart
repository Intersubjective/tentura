// Like the server's other architecture checks, test_api/test_core are
// transitive test dependencies. Use the runner's own metadata semantics.
// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:io';

import 'package:test/test.dart';
import 'package:test_api/src/backend/declarer.dart';
import 'package:test_api/src/backend/group.dart';
import 'package:test_api/src/backend/test.dart' as backend;
import 'package:test_core/src/runner/parse_metadata.dart';

import 'tentura_21x_unused_test_setup_test.dart' as unused_setup;
import 'tentura_fx7_pg_acceptance_probe_test.dart' as fx7;
import 'tentura_j0q_pg_acceptance_probe_test.dart' as j0q;

// A bare top-level `dart test` can still start cleanup: these real test files
// register callbacks that invoke run_with_test_cleanup.sh. In particular,
// runGuardedPgTestFile in tentura_21x uses a different TMPDIR; the wrapper's
// process sweep is global, so that does not isolate the outer VM compiler.
// Keeping PG work out of --exclude-tags pg is an independent, focused gate.
// Assert the pg tag even when a short wrapper timeout skips nested suites:
// the normal 45-minute suite does not set that skip flag.
// This check collects declarations only: no PG body, compiler, or nested
// suite is executed. It does not infer a 1613-test ceiling from toy probes.
void main() {
  group('tentura-69i real non-pg suite selection', () {
    for (final (path, declare, pgNames) in <(String, void Function(), List<String>)>[
      (
        'test/architecture/tentura_21x_unused_test_setup_test.dart',
        unused_setup.main,
        [
          for (final relative in [
            'test/data/database/attention_additive_schema_pg_test.dart',
            'test/data/database/m0141_person_capability_event_ledger_test.dart',
            'test/domain/use_case/user_delete_attention_pg_test.dart',
            'test/data/repository/attention_repository_pg_test.dart',
            'test/domain/use_case/beacon_hierarchy_erasure_pg_test.dart',
          ])
            'bead-listed PG test files stay green $relative',
        ],
      ),
      (
        'test/architecture/tentura_fx7_pg_acceptance_probe_test.dart',
        fx7.main,
        ['tentura-50o regression pg files run green under pg tag filter'],
      ),
      (
        'test/architecture/tentura_j0q_pg_acceptance_probe_test.dart',
        j0q.main,
        [
          'tentura-acz hasura isolation pg files run green under pg tag filter',
          'tentura-acz trust-closure pg files run green under pg tag filter',
        ],
      ),
    ]) {
      test('$path excludes PG callbacks from non-pg selection', () {
        final source = File(path).readAsStringSync();
        final declarer = Declarer(
          metadata: parseMetadata(path, source, const {}),
        );
        declarer.declare(declare);
        final declarations = _tests(declarer.build()).toList();
        final pg = declarations
            .where((entry) => pgNames.any(entry.name.endsWith))
            .toList();

        expect(
          pg,
          hasLength(pgNames.length),
          reason: 'Collect every real PG callback without running its body.',
        );
        expect(
          declarations.where(
            (entry) => !pg.contains(entry) && _selectedByNonPg(entry),
          ),
          isNotEmpty,
          reason: 'The independent unit checks must remain in the non-pg run.',
        );
        expect(
          pg
              .where((entry) => !entry.metadata.tags.contains('pg'))
              .map((entry) => entry.name),
          isEmpty,
          reason:
              'Every nested PG workload must carry the pg tag so that '
              '--exclude-tags pg excludes it regardless of timeout or CI '
              'skip flags. No test bodies were executed.',
        );
      });
    }
  });
}

bool _selectedByNonPg(backend.Test entry) =>
    !entry.metadata.skip && !entry.metadata.tags.contains('pg');

Iterable<backend.Test> _tests(Group group) sync* {
  for (final entry in group.entries) {
    if (entry is Group) {
      yield* _tests(entry);
    } else if (entry is backend.Test) {
      yield entry;
    }
  }
}
