import 'dart:io';

import 'package:test/test.dart';

/// A10: the old valence types are deleted; the forward engine was their last
/// user.
void main() {
  const removed = <String>[
    'lib/domain/trust/trust_bin.dart',
    'lib/domain/trust/trust_context.dart',
    'lib/domain/trust/trust_math.dart',
    'lib/domain/trust/trust_source_type.dart',
    'lib/domain/trust/trust_evidence.dart',
    'lib/domain/trust/trust_evidence_metadata.dart',
    'lib/domain/trust/forward/forward_outcome_policy.dart',
    'lib/domain/trust/forward/forward_outcome_finalizer.dart',
    'lib/domain/port/trust_evidence_repository_port.dart',
    'lib/data/repository/trust_evidence_repository.dart',
    'lib/data/repository/mock/trust_evidence_repository_mock.dart',
    'test/domain/trust/trust_math_test.dart',
    'test/domain/trust/forward_outcome_policy_test.dart',
    'test/domain/trust/forward_outcome_finalizer_test.dart',
  ];

  for (final path in removed) {
    test('$path no longer exists', () {
      expect(File(path).existsSync(), isFalse);
    });
  }

  test('forward_routing_settlement.dart exists', () {
    expect(
      File('lib/domain/trust/forward/forward_routing_settlement.dart')
          .existsSync(),
      isTrue,
    );
  });

  test('no lib or test code references the removed trust types', () {
    final pattern = RegExp(
      r'\bTrustEvidenceRepository(Port|Mock)?\b|\bTrustBin\b|'
      r'\bTrustSourceType\b|\bTrustContext\b|\bTrustMath\b|'
      r'unsuccessfulRequestForward|trust/trust_(bin|context|math|source_type)\.dart|'
      r'trust/trust_evidence(_metadata)?\.dart|forward_outcome_(policy|finalizer)\.dart',
    );
    final hits = <String>[];
    for (final root in ['lib', 'test']) {
      for (final f in Directory(root).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('tentura_0cl_2_9_old_trust_types_removed_test.dart')) {
          continue;
        }
        if (pattern.hasMatch(f.readAsStringSync())) hits.add(f.path);
      }
    }
    expect(hits, isEmpty);
  });

  test('server lib and test analyze without errors (compiles)', () {
    final r = Process.runSync('dart', ['analyze', 'lib', 'test']);
    final errors = '${r.stdout}'
        .split('\n')
        .where((l) => l.trimLeft().startsWith('error'))
        .toList();
    expect(errors, isEmpty, reason: errors.take(20).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 8)));
}
