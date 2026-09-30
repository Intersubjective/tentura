import 'dart:io';

import 'package:test/test.dart';

/// A5: vote, reciprocal-vote, block and maintenance callers project through
/// `trust_project_pair`; behaviour is covered by
/// `test/data/repository/trust_callers_ledger_mr_test.dart`. These scans only
/// pin what a pg test cannot reach cheaply.
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// Source of the method/function whose declaration contains [signature].
String _body(String code, String signature) {
  final start = code.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature not found');
  final open = code.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    if (code[i] == '{') depth++;
    if (code[i] == '}' && --depth == 0) return code.substring(open, i + 1);
  }
  fail('unbalanced braces after $signature');
}

void main() {
  test(
    'no trust_rebuild_effective reference in lib (shipped migrations are '
    'immutable and are the only permitted exception)',
    () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (RegExp(r'/migration/m\d{4}\.dart$').hasMatch(f.path)) continue;
        if (f.readAsStringSync().contains('trust_rebuild_effective')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    },
  );

  test('_setVoteAmountCore writes no evidence and projects the pair', () {
    final body = _body(
      _code('lib/data/repository/user_trust_edge_repository.dart'),
      'Future<void> _setVoteAmountCore(',
    );
    expect(body, isNot(contains('.record(')));
    expect(body, isNot(contains('TrustEvidence')));
    expect(body, isNot(contains('voteAmountToBin')));
    expect(body, contains('trust_project_pair'));
  });

  test(
    '_applyReciprocalTrustEdges projects both pairs sorted, no evidence',
    () {
      final body = _body(
        _code('lib/data/repository/user_repository.dart'),
        'Future<void> _applyReciprocalTrustEdges(',
      );
      expect(body, isNot(contains('.record(')));
      expect(body, isNot(contains('TrustEvidence')));
      expect(body, contains('trust_project_pair'));
      // Sorting must happen before the first projection; both pairs are
      // covered behaviourally by the bindMutual pg test.
      final sortAt = [
        body.indexOf('.sort('),
        body.indexOf('compareTo'),
      ].where((i) => i >= 0).fold<int>(1 << 30, (m, i) => i < m ? i : m);
      expect(sortAt, lessThan(body.indexOf('trust_project_pair')));
    },
  );

  test('maintenance sweep reads user_trust_edge keyset, not evidence', () {
    final body = _body(
      _code('lib/domain/use_case/trust_maintenance_case.dart'),
      'Future<void> _runProjectionSweep(',
    );
    expect(body, contains('trust_project_pair'));
    expect(body, contains('user_trust_edge'));
    expect(body, isNot(contains('trust_evidence')));
  });
}
