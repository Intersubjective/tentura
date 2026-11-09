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

  /// A contract built from [json] instead of the shared file, for checking
  /// how the reader reports a malformed contract.
  factory AttentionAxisContract.fromJson(Map<String, dynamic> json) =>
      AttentionAxisContract._(json);

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

  /// `forwardOutcomeTick` — when a forward row relabelled to an outcome
  /// carries one unread tick (the server's `seen_at IS NULL`) and where it
  /// sits (`created_at`). The server pg test reads the same cases.
  ForwardOutcomeTickContract get forwardOutcomeTick {
    final entry = _json['forwardOutcomeTick'];
    if (entry is! Map) {
      throw StateError(
        'docs/contracts/attention-active-attention-axis.json has no '
        '"forwardOutcomeTick" object; the forward-row outcome tick rule '
        'both layers read is missing.',
      );
    }
    return ForwardOutcomeTickContract._(entry.cast<String, dynamic>());
  }

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

/// The client's view of `forwardOutcomeTick`: its recorded cases.
final class ForwardOutcomeTickContract {
  ForwardOutcomeTickContract._(this._entry);

  final Map<String, dynamic> _entry;

  List<ForwardOutcomeTickCase> get cases {
    final value = _entry['cases'];
    if (value is! List || value.isEmpty) {
      throw StateError(
        'forwardOutcomeTick records no "cases" list; the client cannot '
        'check its mirror of the outcome tick against the server rule.',
      );
    }
    return [
      for (final c in value)
        ForwardOutcomeTickCase._((c as Map).cast<String, dynamic>()),
    ];
  }
}

/// One recorded forward-outcome-tick case.
final class ForwardOutcomeTickCase {
  ForwardOutcomeTickCase._(this._case);

  final Map<String, dynamic> _case;

  Object _field(String key) {
    final Object? value = _case[key];
    if (value == null) {
      throw StateError('forwardOutcomeTick case "$name" records no "$key"');
    }
    return value;
  }

  String get name => _case['name'] as String? ?? '<unnamed>';

  /// `otherUser`, `viewer` or `nobody`.
  String get relabelledBy => _field('relabelledBy') as String;
  bool get markedSeenAfter => _field('markedSeenAfter') as bool;
  bool get unseen => _field('unseen') as bool;

  /// `outcome_changed_at` or `entry_at`: the timestamp the row's
  /// `created_at` must equal.
  String get positionKey => _field('positionKey') as String;
}
