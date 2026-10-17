// MERITRANK_RECV_TIMEOUT_MSEC (whole-call budget) must be identical in compose
// and CI, and sit above the cold MR cost recorded in the U45 journal section.

@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/compose.prod.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repo root not found');
    }
    dir = parent;
  }
  return dir;
}

final _budgetRe = RegExp(r'MERITRANK_RECV_TIMEOUT_MSEC=(\d+)');

Set<int> _budgets(String relPath) => _budgetRe
    .allMatches(File('${_repoRoot().path}/$relPath').readAsStringSync())
    .map((m) => int.parse(m.group(1)!))
    .toSet();

String _u45Section() {
  final text = File(
    '${_repoRoot().path}/docs/plans/'
    'issue-235-constellation-interactive-journal.md',
  ).readAsStringSync();
  final start = text.indexOf('## UNIT U45');
  expect(start, isNonNegative, reason: 'journal has no U45 section');
  final next = text.indexOf('\n## ', start + 1);
  return text.substring(start, next < 0 ? text.length : next);
}

void main() {
  const files = [
    'compose.dev.yaml',
    'compose.prod.yaml',
    '.github/workflows/pipeline.yml',
  ];

  test('journal records the chosen budget and it matches compose', () {
    final section = _u45Section();
    final chosen = RegExp(
      r'MERITRANK_RECV_TIMEOUT_MSEC=(\d+)',
    ).firstMatch(section);
    expect(chosen, isNotNull, reason: 'journal does not record the budget');
    final value = int.parse(chosen!.group(1)!);
    for (final f in files) {
      expect(_budgets(f), {value}, reason: f);
    }
  });

  test('budget is above the cold cost recorded in the journal', () {
    final section = _u45Section();
    final cold = RegExp(
      r'Worst cold first read: ([\d.]+) s',
    ).firstMatch(section);
    expect(cold, isNotNull, reason: 'journal has no measured cold cost');
    final coldMsec = double.parse(cold!.group(1)!) * 1000;
    for (final f in files) {
      expect(_budgets(f).single, greaterThan(coldMsec), reason: f);
    }
  });
}
