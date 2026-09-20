// Regenerates the squashed schema baseline migration from the migration chain.
//
// Builds a disposable database from the registry, dumps its `public` schema
// with `pg_dump` (run inside the Postgres container — `pg_dump` is not
// installed on dev machines), strips the parts migrant supplies or that would
// leak session state, splits the result into single statements, and emits a
// `Migration` part file.
//
// Usage:
//   dart run tool/squash_baseline.dart --version <v> \
//     [--through <v>] [--out lib/data/database/migration/m<v>.dart] \
//     [--dump-to /tmp/chain.sql] [--db <name>] [--container postgres]
//
// `--version` is the version the baseline claims, and it must be the head of
// the chain it replaces: migrant compares version strings, so a baseline
// numbered below head would be re-offered to a database that is already past
// it. `--through` builds the reference database only that far, for a partial
// squash that leaves later migrations in place.
//
// Keep the `--dump-to` file from the pre-squash chain: re-running with
// `--verify-against <that file>` rebuilds the schema from the current registry
// and fails unless it is character-identical. That is the gate that says the
// squash changed nothing.
//
// The emitted file is generated output: regenerate it, never hand-edit it.
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);

  Endpoint endpoint(String database) => Endpoint(
    host: options.host,
    port: options.port,
    database: database,
    username: options.username,
    password: options.password,
  );
  const settings = ConnectionSettings(sslMode: SslMode.disable);

  stdout.writeln('Building ${options.database} from the migration chain…');
  final admin = await Connection.open(endpoint('postgres'), settings: settings);
  try {
    await admin.execute(
      'DROP DATABASE IF EXISTS "${options.database}" WITH (FORCE)',
    );
    await admin.execute('CREATE DATABASE "${options.database}"');
  } finally {
    await admin.close();
  }

  final connection = await Connection.open(
    endpoint(options.database),
    settings: settings,
  );
  try {
    // Function bodies reference the pgmer2 extension's `mr_*` functions, which
    // a fresh database does not have. Without this the chain dies on the first
    // such body with `42883: function mr_node_score(text, text, text) does not
    // exist`.
    await connection.execute('SET check_function_bodies = false');
    if (options.through == null) {
      await migrateDbSchema(connection);
    } else {
      await migrateDbSchemaThrough(connection, options.through!);
    }
    _assertSeedsCover(
      await _rowCounts(connection),
      built: options.verifyAgainst != null,
    );
  } finally {
    await connection.close();
  }

  stdout.writeln('Dumping the schema…');
  final dump = await _pgDump(options);
  if (options.dumpTo != null) {
    File(options.dumpTo!).writeAsStringSync(dump);
  }

  final stripped = _strip(dump);
  final all = splitSqlStatements(stripped);
  _assertRoundTrips(stripped, all);
  final statements =
      all.where((statement) => !_isDropped(statement)).toList();

  if (options.verifyAgainst != null) {
    _verify(File(options.verifyAgainst!).readAsStringSync(), stripped);
    stdout.writeln(
      'Schema and seed rows match ${options.verifyAgainst}.',
    );
    return;
  }

  stdout.writeln('Emitting ${options.out} (${statements.length} statements)…');
  File(options.out).writeAsStringSync(_emit(options.version, statements));
  stdout.writeln('Done.');
}

Future<String> _pgDump(_Options options) async {
  final result = await Process.run('docker', [
    'exec',
    options.container,
    'pg_dump',
    '-U',
    options.username,
    '-d',
    options.database,
    '--schema-only',
    '--schema=public',
    '--no-owner',
    '--no-privileges',
  ]);
  if (result.exitCode != 0) {
    throw ProcessException('docker', ['exec', options.container, 'pg_dump'],
        result.stderr.toString(), result.exitCode);
  }
  return result.stdout as String;
}

/// Lines and statements that must not reach the baseline.
///
/// - `\restrict` / `\unrestrict` are psql meta-commands, not SQL, and carry a
///   per-dump nonce.
/// - `set_config('search_path', '', false)` would persist on the connection the
///   server goes on to use. The dump qualifies every name, so it is not needed.
/// - `schema_version` is migrant's own bookkeeping table: its gateway creates
///   it in `initialize()` before the baseline runs, and the dump's `CREATE
///   TABLE` has no `IF NOT EXISTS`.
/// - `COMMENT ON SCHEMA public` is noise that no migration set.
///
/// `CREATE SCHEMA public` is rewritten rather than dropped: `CREATE DATABASE`
/// inherits `public` from `template1`, so the dump's bare form fails with
/// `42P06: schema "public" already exists`. `m0001` said `IF NOT EXISTS` for
/// the same reason.
String _strip(String dump) {
  final kept = <String>[];
  for (final line in const LineSplitter().convert(dump)) {
    if (line.startsWith(r'\restrict') || line.startsWith(r'\unrestrict')) {
      continue;
    }
    kept.add(
      line.replaceFirst(
        RegExp('^CREATE SCHEMA public;'),
        'CREATE SCHEMA IF NOT EXISTS public;',
      ),
    );
  }
  return kept.join('\n');
}

bool _isDropped(String statement) {
  final normalized = statement.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.startsWith("SELECT pg_catalog.set_config('search_path'") ||
      normalized.startsWith('CREATE TABLE public.schema_version') ||
      normalized.startsWith('ALTER TABLE ONLY public.schema_version') ||
      normalized.startsWith('COMMENT ON SCHEMA public');
}

/// Splits `sql` into single statements on top-level `;`.
///
/// Statements must stay one per string: migrant runs `ctx.execute(statement)`
/// over the extended protocol, which rejects multi-statement strings, and
/// `QueryMode.simple` is not an escape hatch because migrant's own version
/// insert is parameterised.
///
/// Semicolons appear inside 127 function bodies, so this tracks dollar quotes
/// (`$tag$`), single- and double-quoted literals, `E''` backslash escapes, and
/// both comment forms rather than splitting on the character.
List<String> splitSqlStatements(String sql) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var index = 0;

  void flush() {
    final statement = _withoutComments(buffer.toString());
    buffer.clear();
    if (statement.isNotEmpty) statements.add(statement);
  }

  while (index < sql.length) {
    final char = sql[index];

    if (char == '-' && index + 1 < sql.length && sql[index + 1] == '-') {
      final end = sql.indexOf('\n', index);
      final stop = end == -1 ? sql.length : end;
      buffer.write(sql.substring(index, stop));
      index = stop;
      continue;
    }

    if (char == '/' && index + 1 < sql.length && sql[index + 1] == '*') {
      var depth = 0;
      final start = index;
      while (index < sql.length) {
        if (sql.startsWith('/*', index)) {
          depth++;
          index += 2;
        } else if (sql.startsWith('*/', index)) {
          depth--;
          index += 2;
          if (depth == 0) break;
        } else {
          index++;
        }
      }
      buffer.write(sql.substring(start, index));
      continue;
    }

    if (char == r'$') {
      final tag = _dollarTagAt(sql, index);
      if (tag != null) {
        final close = sql.indexOf(tag, index + tag.length);
        if (close == -1) {
          throw FormatException('unterminated dollar quote $tag at $index');
        }
        final end = close + tag.length;
        buffer.write(sql.substring(index, end));
        index = end;
        continue;
      }
    }

    if (char == "'") {
      final escaped = _isEscapeStringAt(sql, index);
      final start = index;
      index++;
      while (index < sql.length) {
        if (escaped && sql[index] == r'\') {
          index += 2;
          continue;
        }
        if (sql[index] == "'") {
          if (index + 1 < sql.length && sql[index + 1] == "'") {
            index += 2;
            continue;
          }
          index++;
          break;
        }
        index++;
      }
      buffer.write(sql.substring(start, index));
      continue;
    }

    if (char == '"') {
      final start = index;
      index++;
      while (index < sql.length) {
        if (sql[index] == '"') {
          if (index + 1 < sql.length && sql[index + 1] == '"') {
            index += 2;
            continue;
          }
          index++;
          break;
        }
        index++;
      }
      buffer.write(sql.substring(start, index));
      continue;
    }

    if (char == ';') {
      index++;
      flush();
      continue;
    }

    buffer.write(char);
    index++;
  }
  flush();
  return statements;
}

/// Drops the banner pg_dump puts before each object, leaving the SQL.
///
/// Only the *leading* comment lines go. Comments inside a function body are
/// part of the body: Postgres stores `prosrc` verbatim and dumps it back, so
/// stripping them would make the rebuilt schema differ from the reference.
String _withoutComments(String statement) {
  final lines = statement.split('\n');
  var start = 0;
  while (start < lines.length) {
    final line = lines[start].trim();
    if (line.isEmpty || line.startsWith('--')) {
      start++;
    } else {
      break;
    }
  }
  return lines.skip(start).join('\n').trim();
}

/// Returns the dollar-quote tag opening at [index] (`$$`, `$body$`), or null
/// when the `$` is something else — a `$1` placeholder or part of an identifier.
String? _dollarTagAt(String sql, int index) {
  final close = sql.indexOf(r'$', index + 1);
  if (close == -1) return null;
  final label = sql.substring(index + 1, close);
  if (label.isNotEmpty && !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(label)) {
    return null;
  }
  return sql.substring(index, close + 1);
}

/// True when the quote at [index] opens an `E'…'` string, whose backslashes
/// escape rather than stand for themselves.
bool _isEscapeStringAt(String sql, int index) {
  if (index == 0) return false;
  final prefix = sql[index - 1];
  if (prefix != 'E' && prefix != 'e') return false;
  if (index == 1) return true;
  return !RegExp('[A-Za-z0-9_]').hasMatch(sql[index - 2]);
}

/// The split must account for every character of the dump. A splitter that
/// ate, merged or duplicated a function body fails here rather than at deploy
/// time.
void _assertRoundTrips(String stripped, List<String> all) {
  // Compares SQL substance only: every `--` line goes from both sides, since
  // the dump's per-object banners are not part of any statement. Comment loss
  // inside function bodies is caught by [_verify], which diffs the rebuilt
  // schema against the reference dump.
  String normalize(String value) => value
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n')
      .replaceAll(';', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final expected = normalize(stripped);
  final actual = normalize(all.join(';'));
  if (expected != actual) {
    var at = 0;
    while (at < expected.length && at < actual.length &&
        expected[at] == actual[at]) {
      at++;
    }
    final from = at < 120 ? 0 : at - 120;
    throw StateError(
      'round-trip check failed at $at of ${expected.length}/${actual.length}\n'
      'expected: ...${expected.substring(from, (at + 120).clamp(0, expected.length))}\n'
      'actual:   ...${actual.substring(from, (at + 120).clamp(0, actual.length))}',
    );
  }
  for (final statement in all) {
    final tags = RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$')
        .allMatches(statement)
        .map((match) => match.group(0)!)
        .toList();
    for (final tag in tags.toSet()) {
      if (tags.where((other) => other == tag).length.isOdd) {
        throw StateError('unbalanced dollar quote $tag in: $statement');
      }
    }
  }
}

/// Gate G1: the schema this registry builds must be character-identical to the
/// reference dump, which is the dump of the chain the baseline replaced.
void _verify(String reference, String actual) {
  final expected = _strip(reference);
  if (expected == actual) return;
  final expectedLines = const LineSplitter().convert(expected);
  final actualLines = const LineSplitter().convert(actual);
  final report = StringBuffer('schema differs from the reference dump:');
  for (final line in expectedLines.toSet().difference(actualLines.toSet())) {
    report.write('\n  only in reference: $line');
  }
  for (final line in actualLines.toSet().difference(expectedLines.toSet())) {
    report.write('\n  only in built:     $line');
  }
  throw StateError(report.toString());
}

/// Rows the replaced chain seeded, transcribed verbatim from the migrations
/// that introduced them (`m0122` for the trust tables, `m0142` for the publish
/// epoch) rather than captured with `pg_dump --data-only`.
///
/// A data dump would bake the `DEFAULT now()` timestamps of whatever machine
/// generated the baseline into every future deployment. These statements leave
/// those columns to their defaults, which is what the migrations did.
const _seedPublishEpoch =
    'INSERT INTO public.mr_publish_epoch DEFAULT VALUES '
    'ON CONFLICT DO NOTHING';

const _seedTrustPolicy =
    'INSERT INTO public.trust_policy (half_life_seconds, epsilon)\n'
    'VALUES (15724800, 0.1)\n'
    'ON CONFLICT DO NOTHING';

const _seedTrustContextConfig =
    'INSERT INTO public.trust_context_config '
    '(trust_context, evidence_multiplier)\n'
    "VALUES ('legacy', 1.0), ('personal', 1.0), ('commitment', 1.0), "
    "('forward', 0.20)\n"
    'ON CONFLICT (trust_context) DO NOTHING';

const _seedStatements = <String>[
  _seedPublishEpoch,
  _seedTrustPolicy,
  _seedTrustContextConfig,
];

/// What [_seedStatements] must produce. `schema_version` is migrant's own and
/// is excluded everywhere.
const _expectedSeedRows = <String, int>{
  'mr_publish_epoch': 1,
  'trust_context_config': 4,
  'trust_policy': 1,
};

/// Exact row counts per table — `pg_stat_user_tables.n_live_tup` is an estimate
/// and reads zero until the table is analysed.
Future<Map<String, int>> _rowCounts(Connection connection) async {
  // `query_to_xml` stays indented mid-line on purpose: at the start of a line
  // it trips the repo's no_raw_graphql_in_dart lint, which reads `query…(` as
  // a GraphQL operation.
  final rows = await connection.execute('''
SELECT relname, (xpath('/row/c/text()', query_to_xml(
         format('SELECT count(*) AS c FROM %I.%I', schemaname, relname),
         false, true, '')))[1]::text::bigint AS rows
FROM pg_stat_user_tables
WHERE schemaname = 'public' AND relname <> 'schema_version'
''');
  return {
    for (final row in rows)
      if ((row[1]! as int) > 0) row[0]! as String: row[1]! as int,
  };
}

/// Gate G2. A schema-only dump carries no rows, so any table the chain left
/// non-empty must be covered by [_seedStatements] — and a seed that silently
/// stopped inserting must not pass either.
void _assertSeedsCover(Map<String, int> counts, {required bool built}) {
  if (const MapEquality<String, int>().equals(counts, _expectedSeedRows)) {
    return;
  }
  final what = built ? 'the baseline produced' : 'the chain left';
  throw StateError(
    'seed mismatch: $what $counts, expected $_expectedSeedRows.\n'
    'A migration seeded a table that _seedStatements does not cover; add it '
    'there (omitting DEFAULT now() columns) and regenerate.',
  );
}

String _emit(String version, List<String> statements) {
  final buffer = StringBuffer()
    ..writeln('// Generated by tool/squash_baseline.dart. Do not edit.')
    ..writeln('// ignore_for_file: unnecessary_raw_strings')
    ..writeln()
    ..writeln("part of '_migrations.dart';")
    ..writeln()
    ..writeln('/// Squashed schema baseline.')
    ..writeln('///')
    ..writeln('/// Generated by `tool/squash_baseline.dart` from a `pg_dump` of a database')
    ..writeln('/// built by the migration chain this migration replaces. Regenerate it; do')
    ..writeln('/// not hand-edit it.')
    ..writeln('///')
    ..writeln('/// migrant reads only `MAX(schema_version.version)`, so a database already at')
    ..writeln("/// or past '$version' never sees this migration and nothing here re-runs. A")
    ..writeln('/// database *below* it would be handed this baseline by `getNext` and would')
    ..writeln('/// create objects over live ones — check `MAX(version)` before deploying.')
    ..writeln("final m$version = Migration('$version', [");
  for (final statement in [...statements, ..._seedStatements]) {
    buffer
      ..writeln('  ${_dartLiteral(statement.trim())},')
      ..writeln();
  }
  buffer.writeln(']);');
  return buffer.toString();
}

String _dartLiteral(String statement) {
  final body = statement.endsWith("'") ? '$statement\n' : statement;
  if (!body.contains("'''")) {
    return "r'''\n$body\n'''";
  }
  final escaped = body
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'''", r"\'\'\'");
  return "'''\n$escaped\n'''";
}

class _Options {
  _Options({
    required this.version,
    required this.through,
    required this.out,
    required this.dumpTo,
    required this.verifyAgainst,
    required this.database,
    required this.container,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  factory _Options.parse(List<String> args) {
    String? valueOf(String name) {
      final index = args.indexOf('--$name');
      return index == -1 || index + 1 >= args.length ? null : args[index + 1];
    }

    final environment = Platform.environment;
    final version = valueOf('version') ?? '0193';
    return _Options(
      version: version,
      through: valueOf('through'),
      out: valueOf('out') ??
          'lib/data/database/migration/m$version.dart',
      dumpTo: valueOf('dump-to'),
      verifyAgainst: valueOf('verify-against'),
      database: valueOf('db') ?? 'tentura_test_squash_baseline',
      container: valueOf('container') ?? 'postgres',
      host: environment['POSTGRES_HOST'] ?? '127.0.0.1',
      port: int.tryParse(environment['POSTGRES_PORT'] ?? '') ?? 5432,
      username: environment['POSTGRES_USERNAME'] ?? 'postgres',
      password: environment['POSTGRES_PASSWORD'] ?? 'password',
    );
  }

  final String version;
  final String? through;
  final String out;
  final String? dumpTo;
  final String? verifyAgainst;
  final String database;
  final String container;
  final String host;
  final int port;
  final String username;
  final String password;
}
