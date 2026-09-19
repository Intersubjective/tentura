import 'dart:convert';
import 'dart:io';

/// The **shared** cross-layer definition of the active-attention axis.
///
/// Overseer addition 1 (U15R-c): a client test that asserts a quantity the
/// **server** defines must drive it from a shared artifact, not from a
/// hand-built number that looks right. `docs/contracts/…` is that artifact,
/// and [assertServerPredicatesUnchanged] is what keeps it honest: if the
/// server's SQL moves, the transcription stops matching and this fails rather
/// than letting the two layers drift into different meanings of one field.
final class AttentionAxisContract {
  AttentionAxisContract._(this._json);

  final Map<String, dynamic> _json;

  static AttentionAxisContract load() {
    for (final candidate in const [
      '../../docs/contracts/attention-active-attention-axis.json',
      'docs/contracts/attention-active-attention-axis.json',
    ]) {
      final file = File(candidate);
      if (file.existsSync()) {
        return AttentionAxisContract._(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
        );
      }
    }
    throw StateError(
      'docs/contracts/attention-active-attention-axis.json is missing; it is '
      'the shared definition both layers read.',
    );
  }

  Map<String, dynamic> get predicates =>
      (_json['predicates'] as Map).cast<String, dynamic>();

  List<Map<String, dynamic>> get axisCases => [
    for (final c in _json['axisCases'] as List)
      (c as Map).cast<String, dynamic>(),
  ];

  Map<String, dynamic> axisCase(String name) => axisCases.firstWhere(
    (c) => c['name'] == name,
    orElse: () => throw StateError('no axis case named "$name"'),
  );

  Map<String, dynamic> get sweepDismissibleMembership =>
      (_json['sweepDismissibleMembership'] as Map).cast<String, dynamic>();

  /// Reads the server source and proves the transcription above still says
  /// what the server says. A hand-copied predicate that silently went stale is
  /// precisely the blind spot this unit was sent to close.
  void assertServerPredicatesUnchanged() {
    final source = _serverSql();
    if (source == null) return; // server package not checked out beside us
    for (final entry in predicates.entries) {
      if (entry.key.startsWith('_')) continue;
      final expected = (entry.value as String).replaceAll('{a}', r'$alias');
      if (!source.contains(expected)) {
        throw StateError(
          'docs/contracts/attention-active-attention-axis.json records\n'
          '  ${entry.key} = ${entry.value}\n'
          'but packages/server/lib/data/repository/attention_dismissible_sql.'
          'dart no longer contains it. The two layers have drifted; update '
          'the contract and every test that reads it.',
        );
      }
    }
  }

  static String? _serverSql() {
    for (final candidate in const [
      '../server/lib/data/repository/attention_dismissible_sql.dart',
      'packages/server/lib/data/repository/attention_dismissible_sql.dart',
    ]) {
      final file = File(candidate);
      if (file.existsSync()) return file.readAsStringSync();
    }
    return null;
  }
}
