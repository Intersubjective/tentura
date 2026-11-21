@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../support/viewer_can_forward_profile.dart';

const _migrationPath = 'packages/server/lib/data/database/migration';
const _startingRevision = 'c2d0bb484529a6b27b3254c6974db22d294f8d76';
const _shippedThrough = 'm0326.dart';
const _nextMigration = 'm0327.dart';
// SHA-256 of sorted `filename sha256(file bytes)\n` lines from the starting
// revision. This also checks the shipped files in shallow CI checkouts.
const _shippedDigest =
    '1387d2893d831ccc4555065086d7d02b50a7361ef7a33ff24e0c9d85e9108955';
final _migrationFile = RegExp(r'^m\d{4}\.dart$');
const _explainFields = {
  'inbox_fetch.graphql': {'inbox_item'},
  'my_work_fetch.graphql': {
    'authoredNonArchived',
    'helpOfferedNonArchived',
    'archivedIdHints',
    'obligationBeacons',
  },
};
const _nonForwardingFields = {'archivedIdHints'};

// As in the Hasura SQL profile, use one section per operation, naming its
// GraphQL file in the heading. SQL can be fenced inline or linked as .sql.
// Timing rows use Body | Warm runs | Median (ms) | p95 (ms), followed by a
// Verdict line. Label the optional third body by its migration version or Fix.
// The Parity section includes the SQL and its result, with lines of the form
// `Parity viewers: Ufirst, Usecond, Uthird` and `Parity mismatches: 0`.
final _timingRow = RegExp(
  r'^\s*\|\s*(m\d{4}|fix)\s*\|\s*(\d+)\s*\|'
  r'\s*(\d+(?:\.\d+)?)\s*(?:ms)?\s*\|'
  r'\s*(\d+(?:\.\d+)?)\s*(?:ms)?\s*\|\s*$',
  caseSensitive: false,
  multiLine: true,
);

void main() {
  test(
    'the profile identifies the database and viewer for both SQL captures',
    () {
      final note = _profileNote();
      final markdown = note.readAsStringSync();
      expect(markdown, contains('tentura_perfsynth'));
      expect(
        _plain(markdown),
        matches(
          RegExp(
            r'\b(?:git(?:\s+sha)?|commit|sha)\s*:?\s+[0-9a-f]{7,40}\b',
            caseSensitive: false,
          ),
        ),
        reason: 'record the measured git SHA',
      );
      expect(markdown, contains('/v1/graphql/explain'));
      final viewerInSession = RegExp(
        '"x-hasura-user-id"\\s*:\\s*"${RegExp.escape(_viewer(markdown))}"',
      );

      for (final MapEntry(key: name, value: operation)
          in forwardingProfileOperations.entries) {
        final section = forwardingProfileSection(markdown, operation);
        final captures = _sqlCaptures(note, section).toList();
        final generatedSql = _readExplainSql(note, section, operation);
        expect(captures, isNotEmpty, reason: '$name needs the measured SQL');
        for (final sql in captures) {
          expect(
            generatedSql,
            contains(_statement(sql)),
            reason:
                '$name must reproduce a complete SQL statement from its Hasura explain response',
          );
          expect(
            _projectsForwardingFlag(sql, viewerInSession),
            isTrue,
            reason:
                '$name SQL must select the forwarding flag for the recorded viewer',
          );
        }
      }
    },
  );

  test('warm latency measurements justify both verdicts and any follow-up', () {
    final note = _profileNote();
    final markdown = note.readAsStringSync();
    expect(
      markdown,
      matches(
        RegExp(r'EXPLAIN\s*\(\s*ANALYZE\s*,\s*BUFFERS\b', caseSensitive: false),
      ),
    );

    final profiles = [
      for (final operation in forwardingProfileOperations.values)
        _readTimings(forwardingProfileSection(markdown, operation), operation),
    ];
    final needsFix = profiles.any((profile) => profile.slower);
    for (final profile in profiles) {
      final fixed = profile.fixed;
      if (!needsFix) {
        expect(
          fixed,
          isNull,
          reason: '${profile.operation} must report the two measured bodies',
        );
        continue;
      }
      expect(
        fixed,
        isNotNull,
        reason: '${profile.operation} needs a post-fix measurement',
      );
      expect(
        fixed!.median,
        closeTo(profile.baseline.median, profile.baseline.median * 0.1),
        reason:
            '${profile.operation} post-fix median must be within 10% '
            'of the baseline',
      );
    }
    _expectParityReport(note, markdown);
    _expectMigrationDelivery(note, needsFix: needsFix);
  });
}

String _viewer(String markdown) {
  final viewer = RegExp(
    r'^\s*(?:-\s+)?viewer(?:[ _-]+id)?\s*:\s*([\w-]+)',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(_plain(markdown))?.group(1);
  if (viewer == null) fail('record the measured Viewer ID');
  return viewer;
}

// Link the raw JSON under "Hasura explain response:" in each operation's
// section. The SQL fence or linked .sql holds the full measured statement.
List<String> _readExplainSql(File note, String section, String operation) {
  final links = RegExp(
    r'hasura explain response\s*:[ \t]*\[[^\]\n]+\]\(([^\s()]+\.json)\)',
    caseSensitive: false,
  ).allMatches(section).toList();
  expect(
    links,
    hasLength(1),
    reason: '$operation needs its raw Hasura explain response',
  );
  final uri = note.uri.resolve(links.single[1]!);
  expect(
    uri.scheme,
    'file',
    reason: 'commit the raw explain response alongside the note',
  );
  final report = File.fromUri(uri);
  expect(
    report.existsSync(),
    isTrue,
    reason: 'missing Hasura explain response ${report.path}',
  );
  final rows = jsonDecode(report.readAsStringSync()) as List<Object?>;
  final fields = <String, Map<String, Object?>>{};
  for (final entry in rows) {
    final row = entry! as Map<String, Object?>;
    final name = row['field']! as String;
    expect(
      fields,
      isNot(contains(name)),
      reason: '$operation repeats root field $name',
    );
    fields[name] = row;
  }
  expect(
    fields.keys.toSet(),
    _explainFields[operation],
    reason: 'the explain response must cover the complete $operation operation',
  );
  return [
    for (final entry in fields.entries)
      if (!_nonForwardingFields.contains(entry.key))
        _statement(entry.value['sql']! as String),
  ];
}

String _statement(String sql) => sql
    .trimLeft()
    .replaceFirst(RegExp(r'^(?:[ \t]*--[^\n]*(?:\n|$))+'), '')
    .trim()
    .replaceFirst(RegExp(r';$'), '')
    .trimRight();

bool _projectsForwardingFlag(String sql, RegExp viewerInSession) {
  final projection = RegExp(
    r'"?beacon_get_viewer_can_forward"?\([^)]*\)\s+AS\s+"?viewer_can_forward\b',
    caseSensitive: false,
  ).allMatches(_statement(sql));
  final roleInSession = RegExp(r'"x-hasura-role"\s*:\s*"user"');
  return projection.any(
    (match) =>
        viewerInSession.hasMatch(match[0]!) &&
        roleInSession.hasMatch(match[0]!),
  );
}

void _expectParityReport(File note, String markdown) {
  final parity = forwardingProfileSection(markdown, 'parity');
  final viewersLine = RegExp(
    r'^\s*(?:-\s+)?parity viewers\s*:\s*([^\n]+)',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(_plain(parity))?.group(1);
  final viewers = RegExp(
    r'[\w-]+',
  ).allMatches(viewersLine ?? '').map((match) => match[0]!).toSet();
  expect(
    viewers,
    hasLength(greaterThanOrEqualTo(3)),
    reason: 'record the distinct viewers used for the all-row comparison',
  );
  expect(viewers, contains(_viewer(markdown)));
  expect(parity, contains('tentura_perfsynth'));
  expect(
    _sqlCaptures(note, parity).map(_sqlTokens),
    anyElement(equals(_sqlTokens(_allBeaconParitySql(viewers)))),
    reason:
        'compare the shipped function to the m0318 expression for every beacon and viewer',
  );
  expect(
    _plain(parity),
    matches(
      RegExp(
        r'^\s*(?:-\s+)?parity mismatches\s*:\s*0\s*$',
        caseSensitive: false,
        multiLine: true,
      ),
    ),
    reason: 'record the zero mismatches returned by the parity query',
  );
}

// The report uses an inline m0318 oracle so this query can be replayed
// read-only. The CROSS JOIN and sole mismatch predicate cover the whole table.
String _allBeaconParitySql(Set<String> viewers) =>
    '''
SELECT count(*)
FROM public.beacon AS b
CROSS JOIN (VALUES ${viewers.map((viewer) => "('$viewer')").join(', ')}) AS v(id)
WHERE public.beacon_get_viewer_can_forward(
  b, json_build_object('x-hasura-role', 'user', 'x-hasura-user-id', v.id)
) IS DISTINCT FROM COALESCE(
  b.status IN (0, 7, 8)
  AND (b.forward_policy = 1 OR b.user_id = v.id)
  AND public.beacon_can_read_involvement(b.id, v.id),
  false
)
''';

List<String> _sqlTokens(String sql) =>
    RegExp(
      r"'(?:''|[^'])*'|[a-zA-Z_][\w$]*|\d+|[^\s]",
    ).allMatches(_statement(sql)).map((match) {
      final token = match[0]!;
      return token.startsWith("'") ? token : token.toLowerCase();
    }).toList();

void _expectMigrationDelivery(File note, {required bool needsFix}) {
  final root = note.parent.parent.parent.path;
  final migrations =
      Directory('$root/$_migrationPath')
          .listSync()
          .whereType<File>()
          .where((file) => _migrationFile.hasMatch(file.uri.pathSegments.last))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final manifest = StringBuffer();
  final newNames = <String>[];
  for (final file in migrations) {
    final name = file.uri.pathSegments.last;
    if (name.compareTo(_shippedThrough) <= 0) {
      manifest.writeln('$name ${sha256.convert(file.readAsBytesSync())}');
    } else {
      newNames.add(name);
    }
  }
  expect(
    sha256.convert(manifest.toString().codeUnits).toString(),
    _shippedDigest,
    reason: 'all shipped migration files must remain byte-identical',
  );

  ProcessResult git(List<String> args) =>
      Process.runSync('git', args, workingDirectory: root);
  // Once the note lands, check its delivery revision so later work can still
  // append migrations. Shallow checkouts can always verify the shipped digest
  // and that the fix, when required, has its next-version file.
  if (git(['cat-file', '-e', _startingRevision]).exitCode != 0) {
    if (needsFix) expect(newNames, contains(_nextMigration));
    return;
  }
  final history = git([
    'log',
    '-1',
    '--diff-filter=A',
    '--format=%H',
    '--',
    forwardingProfilePath,
  ]);
  expect(history.exitCode, 0, reason: '${history.stderr}');
  final delivery = (history.stdout as String).trim();
  if (delivery.isNotEmpty) {
    final tree = git(['ls-tree', '--name-only', delivery, '$_migrationPath/']);
    expect(tree.exitCode, 0, reason: '${tree.stderr}');
    final delivered = (tree.stdout as String)
        .split('\n')
        .map((path) => path.split('/').last)
        .where(
          (name) =>
              _migrationFile.hasMatch(name) &&
              name.compareTo(_shippedThrough) > 0,
        );
    expect(
      delivered,
      needsFix ? [_nextMigration] : isEmpty,
      reason:
          'the delivery must append exactly the next migration only when needed',
    );
    return;
  }
  expect(
    newNames,
    needsFix ? [_nextMigration] : isEmpty,
    reason:
        'the worktree must append exactly the next migration only when needed',
  );
}

File _profileNote() {
  var root = Directory.current.absolute;
  while (!File('${root.path}/compose.prod.yaml').existsSync()) {
    final parent = root.parent;
    if (parent.path == root.path) fail('Tentura repository root not found');
    root = parent;
  }
  final note = File('${root.path}/$forwardingProfilePath');
  expect(
    note.existsSync(),
    isTrue,
    reason:
        'the forwarding benchmark has no measurement note at $forwardingProfilePath',
  );
  return note;
}

String _plain(String markdown) => markdown.replaceAll(RegExp('[`*]'), '');

Iterable<String> _sqlCaptures(File note, String section) sync* {
  for (final match in RegExp(r'```sql\s*\n([\s\S]*?)```').allMatches(section)) {
    yield match[1]!;
  }
  for (final match in RegExp(r'\]\(([^\s()]+\.sql)\)').allMatches(section)) {
    final link = note.uri.resolve(match[1]!);
    if (link.scheme != 'file') continue;
    final capture = File.fromUri(link);
    expect(
      capture.existsSync(),
      isTrue,
      reason: 'missing SQL capture ${match[1]}',
    );
    yield capture.readAsStringSync();
  }
}

typedef _Timing = ({int runs, double median, double p95});

({String operation, _Timing baseline, bool slower, _Timing? fixed})
_readTimings(
  String section,
  String operation,
) {
  final timings = <String, _Timing>{};
  for (final match in _timingRow.allMatches(_plain(section))) {
    final body = match[1]!.toLowerCase();
    final timing = (
      runs: int.parse(match[2]!),
      median: double.parse(match[3]!),
      p95: double.parse(match[4]!),
    );
    expect(timings, isNot(contains(body)), reason: '$operation repeats $body');
    expect(timing.runs, greaterThanOrEqualTo(20), reason: '$operation $body');
    expect(timing.median, greaterThan(0), reason: '$operation $body');
    expect(
      timing.p95,
      greaterThanOrEqualTo(timing.median),
      reason: '$operation $body',
    );
    timings[body] = timing;
  }

  final baseline = timings.remove('m0211');
  final current = timings.remove('m0318');
  expect(baseline, isNotNull, reason: '$operation needs the m0211 timing');
  expect(current, isNotNull, reason: '$operation needs the m0318 timing');
  expect(
    timings.length,
    lessThanOrEqualTo(1),
    reason: '$operation can include one follow-up timing',
  );
  final slower = current!.median * 10 > baseline!.median * 11;
  expect(
    forwardingProfileVerdict(section),
    slower,
    reason: '$operation verdict must use the 10% median threshold',
  );
  return (
    operation: operation,
    baseline: baseline,
    slower: slower,
    fixed: timings.values.singleOrNull,
  );
}
