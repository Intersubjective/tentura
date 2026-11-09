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

  /// The forward-row outcome tick: when a forward row relabelled to an
  /// outcome moves up and carries one unread tick. Throws when the contract
  /// does not record it, so the rule cannot exist only in SQL.
  ForwardOutcomeTickContract get forwardOutcomeTick {
    final entry = _json['forwardOutcomeTick'];
    if (entry is! Map) {
      throw StateError(
        'docs/contracts/attention-active-attention-axis.json records no '
        '"forwardOutcomeTick" object; the forward-row outcome tick rule '
        '(position and unseen) must be written down where both layers read it.',
      );
    }
    return ForwardOutcomeTickContract(entry.cast<String, dynamic>());
  }

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

/// `forwardOutcomeTick` — the rule that lets a forward row relabelled to an
/// outcome by somebody else move up with one unread tick.
///
/// Expected shape:
/// ```json
/// "forwardOutcomeTick": {
///   "position": "GREATEST(entry_at, outcome_changed_at)",
///   "unseen": "outcome_changed_by <> viewer AND outcome_changed_at > COALESCE(outcome_seen_at, '-infinity')",
///   "markSeen": "markSeen with an inbox:<beaconId> id sets the viewer's outcome_seen_at",
///   "sql": {
///     "position": "<literal fragment of attention_repository.dart>",
///     "unseen": "<literal fragment of attention_repository.dart>",
///     "markSeen": "<literal fragment of attention_repository.dart>"
///   },
///   "cases": [
///     {
///       "name": "…",
///       "relabelledBy": "otherUser" | "viewer" | "nobody",
///       "markedSeenAfter": false,
///       "unseen": true,
///       "positionKey": "outcome_changed_at" | "entry_at"
///     }
///   ]
/// }
/// ```
extension type ForwardOutcomeTickContract(Map<String, dynamic> _entry) {
  String _string(String key) {
    final value = _entry[key];
    if (value is! String) {
      throw StateError('forwardOutcomeTick records no "$key" string');
    }
    return value;
  }

  String get position => _string('position');
  String get unseen => _string('unseen');
  String get markSeen => _string('markSeen');

  /// The server SQL the rule is transcribed from, as literal fragments of
  /// `lib/data/repository/attention_repository.dart` (`position`, `unseen`,
  /// `markSeen`). [assertMatchesServerSql] fails when the source no longer
  /// contains one of them.
  Map<String, String> get sql {
    final value = _entry['sql'];
    if (value is! Map) {
      throw StateError(
        'forwardOutcomeTick records no "sql" object (the literal server SQL '
        'fragments for position, unseen and markSeen)',
      );
    }
    final fragments = <String, String>{};
    for (final key in const ['position', 'unseen', 'markSeen']) {
      final fragment = value[key];
      if (fragment is! String || fragment.trim().isEmpty) {
        throw StateError('forwardOutcomeTick.sql records no "$key" fragment');
      }
      fragments[key] = fragment;
    }
    return fragments;
  }

  /// Proves every `sql` fragment still appears in the server source
  /// (whitespace-insensitive), so the recorded rule and the shipped SQL
  /// cannot drift apart silently.
  void assertMatchesServerSql() {
    String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final source = squash(_attentionRepositorySource());
    for (final entry in sql.entries) {
      if (!source.contains(squash(entry.value))) {
        throw StateError(
          'docs/contracts/attention-active-attention-axis.json records\n'
          '  forwardOutcomeTick.sql.${entry.key} = ${entry.value}\n'
          'but lib/data/repository/attention_repository.dart no longer '
          'contains it. The contract and the server have drifted.',
        );
      }
    }
  }

  static String _attentionRepositorySource() {
    for (final candidate in const [
      'lib/data/repository/attention_repository.dart',
      'packages/server/lib/data/repository/attention_repository.dart',
    ]) {
      final file = File(candidate);
      if (file.existsSync()) return file.readAsStringSync();
    }
    throw StateError('attention_repository.dart not found');
  }

  List<ForwardOutcomeTickCase> get cases {
    final value = _entry['cases'];
    if (value is! List) {
      throw StateError('forwardOutcomeTick records no "cases" list');
    }
    return [
      for (final c in value)
        ForwardOutcomeTickCase((c as Map).cast<String, dynamic>()),
    ];
  }
}

/// One recorded forward-outcome-tick case.
extension type ForwardOutcomeTickCase(Map<String, dynamic> _case) {
  Object? _field(String key) {
    if (!_case.containsKey(key)) {
      throw StateError('forwardOutcomeTick case "$name" records no "$key"');
    }
    return _case[key];
  }

  String get name => _case['name'] as String? ?? '<unnamed>';

  /// `otherUser`, `viewer` or `nobody`.
  String get relabelledBy => _field('relabelledBy')! as String;
  bool get markedSeenAfter => _field('markedSeenAfter')! as bool;
  bool get unseen => _field('unseen')! as bool;

  /// `outcome_changed_at` or `entry_at`: which timestamp the row's
  /// `created_at` (its position in the stream) must equal.
  String get positionKey => _field('positionKey')! as String;
}
