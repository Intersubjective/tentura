// Contract helpers for tentura-3eyp (parent tentura-jszi): pg test seeds and
// fixtures must match post-m0202 `public.user_trust_edge` (no `anchor_at` or
// legacy tier columns on INSERT; reads must use projection columns).

import 'dart:io';

/// Pg tests reported in tentura-3eyp for stale `user_trust_edge` seed SQL.
const k3eypUserTrustEdgeSeedRegressionPaths = [
  'test/data/database/constellation_trust_edges_pg_test.dart',
  'test/data/repository/user_trust_edge_degree_test.dart',
  'test/graph_edges_between_test.dart',
  'test/data/repository/block_cascade_candidates_pg_test.dart',
  'test/data/repository/user_block_withdrawal_gate_pg_test.dart',
  'test/data/repository/user_block_graph_enforcement_pg_test.dart',
];

/// Columns removed from `user_trust_edge` in migration m0202 step 10.
const kM0202DroppedUserTrustEdgeColumns = [
  'anchor_at',
  's_very_bad',
  's_bad',
  's_no_effect',
  's_good',
  's_very_good',
];

final _userTrustEdgeInsertColumnList = RegExp(
  r'INSERT\s+INTO\s+public\.user_trust_edge\s*\(([^)]*)\)',
  multiLine: true,
  caseSensitive: false,
);

/// Select list must not contain another `FROM public.` (avoids spanning to
/// `DELETE FROM public.user_trust_edge` in the same Dart string).
final _userTrustEdgeSelectFrom = RegExp(
  r'SELECT\s+((?:(?!FROM\s+public\.)[\s\S])*?)\s+FROM\s+public\.user_trust_edge\b',
  multiLine: true,
  caseSensitive: false,
);

bool _columnListReferencesAny(String columnList, List<String> names) {
  for (final name in names) {
    if (RegExp(r'\b' + name + r'\b').hasMatch(columnList)) {
      return true;
    }
  }
  return false;
}

/// True when [source] still lists a dropped column on a `user_trust_edge` INSERT.
bool sourceInsertsLegacyUserTrustEdgeColumns(String source) {
  for (final match in _userTrustEdgeInsertColumnList.allMatches(source)) {
    final columnList = match.group(1)!;
    if (_columnListReferencesAny(columnList, kM0202DroppedUserTrustEdgeColumns)) {
      return true;
    }
  }
  return false;
}

/// True when [source] SELECTs dropped tier / anchor columns from `user_trust_edge`.
bool sourceSelectsLegacyUserTrustEdgeColumns(String source) {
  for (final match in _userTrustEdgeSelectFrom.allMatches(source)) {
    final selectList = match.group(1)!;
    if (_columnListReferencesAny(selectList, kM0202DroppedUserTrustEdgeColumns)) {
      return true;
    }
  }
  return false;
}

Directory serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final dir = Directory(path);
    final candidate = File('${dir.path}/lib/env.dart');
    if (candidate.existsSync()) {
      return dir.absolute;
    }
  }
  throw StateError('server package root not found');
}

String readServerTestSource(String relativePath) {
  final file = File('${serverPackageRoot().path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('server test file not found: ${file.path}');
  }
  return file.readAsStringSync();
}
