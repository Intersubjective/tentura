import 'dart:convert';
import 'dart:io';

/// The **shared** cross-layer definition of the active-attention axis and of
/// the §6 surface indicators — read from the server side.
///
/// U15R-c gave the client a loader for `docs/contracts/…` so a client test
/// could not hand-build a number the server defines. The loop was open at the
/// other end: the PG test that *produces* those numbers never opened the file,
/// so a server change could move a total and leave the contract describing the
/// old one until some client test happened to notice.
///
/// U15R-d closes it. The PG test drives its expectations from here, and
/// [assertMatchesServerSql] proves the predicate transcriptions still say what
/// `AttentionDismissibleSql` says, so drift fails on whichever side moved.
///
/// Deliberately a near-copy of `packages/client/test/support/
/// attention_axis_contract.dart` rather than a shared package: the two
/// packages do not depend on each other, and the thing that must not be
/// duplicated — the *contract* — is the JSON both of them read.
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

  Map<String, dynamic> get surfaceSummaryFields =>
      (_json['surfaceSummaryFields'] as Map).cast<String, dynamic>();

  List<Map<String, dynamic>> get axisCases => [
    for (final c in _json['axisCases'] as List)
      (c as Map).cast<String, dynamic>(),
  ];

  /// One recorded case, by the substring of its name the test is written
  /// around. Throws rather than defaulting: a case that quietly stopped being
  /// read is a contract entry nothing checks.
  AttentionAxisCase axisCase(String nameFragment) {
    final matches = axisCases
        .where((c) => (c['name'] as String).contains(nameFragment))
        .toList();
    if (matches.length != 1) {
      throw StateError(
        'expected exactly one axis case matching "$nameFragment", '
        'found ${matches.length}',
      );
    }
    return AttentionAxisCase(matches.single);
  }

  /// Proves the transcription still matches the server source it claims to
  /// quote. The client asserts the same thing from its side.
  void assertMatchesServerSql() {
    final source = _serverSql();
    for (final entry in predicates.entries) {
      if (entry.key.startsWith('_')) continue;
      final expected = (entry.value as String).replaceAll('{a}', r'$alias');
      if (!source.contains(expected)) {
        throw StateError(
          'docs/contracts/attention-active-attention-axis.json records\n'
          '  ${entry.key} = ${entry.value}\n'
          'but lib/data/repository/attention_dismissible_sql.dart no longer '
          'contains it. The contract and the server have drifted; update the '
          'contract and every test on both sides that reads it.',
        );
      }
    }
  }

  static String _serverSql() {
    for (final candidate in const [
      'lib/data/repository/attention_dismissible_sql.dart',
      'packages/server/lib/data/repository/attention_dismissible_sql.dart',
    ]) {
      final file = File(candidate);
      if (file.existsSync()) return file.readAsStringSync();
    }
    throw StateError('attention_dismissible_sql.dart not found');
  }
}

/// One `axisCases` entry, read by name instead of by index.
extension type AttentionAxisCase(Map<String, dynamic> _case) {
  String get name => _case['name'] as String;

  /// Throws for a field the contract does not record, so a test cannot
  /// silently assert a default the contract never agreed to.
  Object? field(String key) {
    if (!_case.containsKey(key)) {
      throw StateError('axis case "$name" records no "$key"');
    }
    return _case[key];
  }

  int get myDeskCount => field('myDeskCount')! as int;
  bool get myDeskDot => field('myDeskDot')! as bool;
  bool get forYouDot => field('forYouDot')! as bool;
}
