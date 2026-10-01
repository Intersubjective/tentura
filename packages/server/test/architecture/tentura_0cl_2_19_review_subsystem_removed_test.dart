import 'dart:io';

import 'package:test/test.dart';

/// A18: the review subsystem is deleted from the server,
/// together with its tests.
void main() {
  const removedPaths = <String>[
    // use cases
    'lib/domain/use_case/eval'
        'uation_case.dart',
    'lib/domain/use_case/eval'
        'uation',
    'lib/domain/use_case/eval'
        'uation/eval'
        'uation_draft_purger.dart',
    'lib/domain/use_case/eval'
        'uation/eval'
        'uation_participant_draft.dart',
    'lib/domain/use_case/eval'
        'uation/eval'
        'uation_participant_graph_builder.dart',
    'lib/domain/use_case/eval'
        'uation/eval'
        'uation_prompt_variant.dart',
    'lib/domain/use_case/eval'
        'uation/review_finalization_case.dart',
    // domain model
    'lib/domain/eval'
        'uation',
    'lib/domain/entity/eval'
        'uation',
    'lib/domain/entity/review_finalization_result.dart',
    'lib/domain/entity/review_finalization_result.freezed.dart',
    'lib/domain/entity/review_close_snapshot.dart',
    'lib/domain/entity/review_close_snapshot.freezed.dart',
    'lib/domain/entity/gql_public/beacon_close_review_result.dart',
    'lib/domain/entity/gql_public/beacon_extend_review_result.dart',
    // GraphQL result entities
    'lib/domain/entity/gql_public/eval'
        'uation_participant_result.dart',
    'lib/domain/entity/gql_public/eval'
        'uation_draft_row_result.dart',
    'lib/domain/entity/gql_public/eval'
        'uation_summary_result.dart',
    'lib/domain/entity/gql_public/eval'
        'uation_received_result.dart',
    'lib/domain/entity/gql_public/review'
        '_window_status_result.dart',
    // ports, repositories, mocks
    'lib/domain/port/eval'
        'uation_repository_port.dart',
    'lib/domain/port/review_finalization_port.dart',
    'lib/data/repository/eval'
        'uation_repository.dart',
    'lib/data/repository/mock/eval'
        'uation_repository_mock.dart',
    // GraphQL controllers
    'lib/api/controllers/graphql/mutation/mutation_eval'
        'uation.dart',
    'lib/api/controllers/graphql/query/query_eval'
        'uation.dart',
    // tests go together with the code
    'test/domain/eval'
        'uation',
    'test/domain/use_case/eval'
        'uation',
    'test/domain/use_case/eval'
        'uation_submit_ack_policy_pg_test.dart',
    'test/domain/use_case/review_finalization_outcome_evidence_pg_test.dart',
    'test/data/repository/eval'
        'uation_repository_submit_atomic_pg_test.dart',
    'test/data/repository/eval'
        'uation_repository_review_status_pg_test.dart',
    'test/api/controllers/graphql/query_eval'
        'uation_test.dart',
    'test/support/review_finalization_test_support.dart',
    'test/api/graphql_review_extension_type_test.dart',
  ];

  for (final path in removedPaths) {
    test('$path no longer exists', () {
      expect(FileSystemEntity.typeSync(path), FileSystemEntityType.notFound);
    });
  }

  test('no Dart file or directory is named after the review subsystem', () {
    final name = RegExp(
      r'eval'
      r'uation|review'
      r'_window|review_finalization',
      caseSensitive: false,
    );
    final hits = <String>[];
    for (final root in ['lib', 'test']) {
      for (final e in Directory(root).listSync(recursive: true)) {
        if (e.path.contains('/migration/')) continue;
        if (e.path.endsWith(
          'tentura_0cl_2_19_review_subsystem_removed_test.dart',
        )) {
          continue;
        }
        if (name.hasMatch(e.path)) hits.add(e.path);
      }
    }
    expect(hits, isEmpty, reason: hits.take(40).join('\n'));
  });

  test('no runtime Dart references the review subsystem', () {
    // Exactly the A18 allowlist; nothing else is stripped.
    final allowlist = RegExp(
      r'\bBeaconStatus\.reviewOpen\b|\bkMaxReviewReopens\b',
    );
    final pattern = RegExp(
      r"eval"
      r"uation|review"
      r"Window|review"
      r"_window|Review"
      r"Finalization|"
      r"UnimplementedError\('removed in "
      r"A18'\)|"
      r'ReviewWindow|gqlTypeEvaluation|gqlTypeBeaconCloseReviewResult|'
      r'gqlTypeBeaconExtendReviewResult|BeaconCloseReviewResult|'
      r'BeaconExtendReviewResult|ReviewCloseSnapshot|review_close_snapshot',
    );
    final hits = <String>[];
    for (final root in ['lib', 'test']) {
      for (final f in Directory(root).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.contains('/migration/') || f.path.endsWith('.g.dart')) {
          continue;
        }
        if (f.path.endsWith(
          'tentura_0cl_2_19_review_subsystem_removed_test.dart',
        )) {
          continue;
        }
        final text = f.readAsStringSync().replaceAll(allowlist, '');
        if (pattern.hasMatch(text)) hits.add(f.path);
      }
    }
    expect(hits, isEmpty, reason: hits.take(40).join('\n'));
  });

  test('removed review attention event types are gone', () {
    final pattern = RegExp(
      r'\b(reviewOpened|reviewAllPackagesIn|review'
      r'WindowCancelled|'
      r'review'
      r'WindowExpired|review'
      r'WindowOpened|reviewExpired|'
      r'reviewParticipant|receivedReviews|trustGivenChanged|'
      r'trustReceivedChanged)\b',
    );
    final hits = <String>[];
    for (final root in ['lib', 'test']) {
      for (final f in Directory(root).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.contains('/migration/') || f.path.endsWith('.g.dart')) {
          continue;
        }
        if (f.path.endsWith(
          'tentura_0cl_2_19_review_subsystem_removed_test.dart',
        )) {
          continue;
        }
        if (pattern.hasMatch(f.readAsStringSync())) hits.add(f.path);
      }
    }
    expect(hits, isEmpty, reason: hits.take(40).join('\n'));
  });

  test('server lib and test analyze without errors (compiles)', () {
    final r = Process.runSync('dart', [
      'analyze',
      '--no-fatal-warnings',
      'lib',
      'test',
    ]);
    final out = '${r.stdout}\n${r.stderr}';
    final errors = out
        .split('\n')
        .where((l) => l.trimLeft().startsWith('error'))
        .toList();
    expect(errors, isEmpty, reason: errors.take(20).join('\n'));
    expect(r.exitCode, 0, reason: out);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
