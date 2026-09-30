import 'dart:io';

import 'package:test/test.dart';

/// A2 step 6: the legacy repository projects through `trust_project_pair`
/// and no longer references the dropped `trust_rebuild_effective_edge`.
void main() {
  final source = File(
    'lib/data/repository/trust_evidence_repository.dart',
  ).readAsStringSync();

  test('legacy TrustEvidenceRepository does not call the dropped function', () {
    expect(source, isNot(contains('trust_rebuild_effective_edge')));
  });

  test('legacy TrustEvidenceRepository projects via trust_project_pair', () {
    final code = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(
      code,
      matches(RegExp(r'SELECT\s+(public\.)?trust_project_pair\s*\(')),
    );
  });
}
