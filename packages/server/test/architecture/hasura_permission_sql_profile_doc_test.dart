// The #229 Hasura SQL profile doc must cover each operation with its stored
// raw EXPLAIN JSON, and its table must name the costliest node of that plan.

@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _operations = {
  'inbox': 'Inbox',
  'my-work': 'My work',
  'beacon-view': 'Beacon view',
  'people': 'People',
};

const _docPath = 'docs/plans/issue-229-hasura-sql-profile.md';
const _dir = 'docs/plans/issue-229-hasura-sql-profile';

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

File _file(String relPath) => File('${_repoRoot().path}/$relPath');

double _total(Map<String, dynamic> n) =>
    ((n['Actual Total Time'] as num?) ?? 0).toDouble() *
    ((n['Actual Loops'] as num?) ?? 1).toDouble();

List<Map<String, dynamic>> _children(Map<String, dynamic> n) =>
    ((n['Plans'] as List?) ?? const []).cast<Map<String, dynamic>>();

/// Label of the node with the largest exclusive time (own time minus children).
String _worstNodeLabel(Map<String, dynamic> root) {
  var bestTime = -1.0;
  var best = '';
  void walk(Map<String, dynamic> n) {
    final kids = _children(n);
    final own = _total(n) - kids.fold<double>(0, (s, c) => s + _total(c));
    if (own > bestTime) {
      bestTime = own;
      best = n['Subplan Name'] as String? ?? n['Node Type'] as String;
    }
    kids.forEach(walk);
  }

  walk(root);
  return best;
}

String _row(String doc, String label) => doc
    .split('\n')
    .firstWhere(
      (l) => l.startsWith('| $label |'),
      orElse: () => fail('no table row for "$label"'),
    );

void main() {
  test('doc and per-operation SQL and EXPLAIN JSON files exist', () {
    expect(_file(_docPath).existsSync(), isTrue);
    for (final op in _operations.keys) {
      expect(_file('$_dir/$op.sql').existsSync(), isTrue, reason: '$op.sql');
      expect(_file('$_dir/$op.json').existsSync(), isTrue, reason: '$op.json');
    }
  });

  test('raw EXPLAIN JSON files are ANALYZE plans', () {
    for (final op in _operations.keys) {
      final json = jsonDecode(_file('$_dir/$op.json').readAsStringSync());
      final top = (json as List).first as Map<String, dynamic>;
      expect(top['Plan'], isA<Map<String, dynamic>>(), reason: op);
      expect(top['Execution Time'], isA<num>(), reason: op);
    }
  });

  test('table row names the worst (costliest) node of the stored plan', () {
    final doc = _file(_docPath).readAsStringSync();
    _operations.forEach((op, label) {
      final json = jsonDecode(_file('$_dir/$op.json').readAsStringSync());
      final top = (json as List).first as Map<String, dynamic>;
      final worst = _worstNodeLabel(top['Plan'] as Map<String, dynamic>);
      expect(_row(doc, label), contains(worst), reason: op);
    });
  });
}
