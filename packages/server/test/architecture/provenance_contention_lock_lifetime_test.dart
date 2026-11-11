// The analyzer is a transitive dependency, as in the other AST guards.
// ignore_for_file: depend_on_referenced_packages
@Tags(['pg', 'repo-files'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';

const _suite =
    'test/data/repository/'
    'constellation_received_request_provenance_contention_pg_test.dart';
const _group = 'with competing database provisioning';

class _Registrations extends RecursiveAstVisitor<void> {
  final calls = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'test' || node.methodName.name == 'setUpAll') {
      calls.add(node);
    }
    super.visitMethodInvocation(node);
  }
}

String _absoluteImports(String source, File original) =>
    source.replaceAllMapped(
      RegExp("import '([^']+)';|import '([^']+)' as provenance;"),
      (match) {
        final path = match[1] ?? match[2]!;
        if (Uri.parse(path).hasScheme) return match[0]!;
        return match[0]!.replaceFirst(
          path,
          original.absolute.uri.resolve(path).toString(),
        );
      },
    );

// Copy the existing helpers so the real provisioning connection can publish
// its own pg_backend_pid immediately before requesting the lifecycle lock.
// A Zone marks only the original forwarded-field provisioning call; preflight,
// the contention holder, teardown, and unrelated sessions cannot claim its PID.
Map<String, String> _instrumentedSupport(Directory directory) {
  final names = [
    'disposable_pg_target.dart',
    'drift_executor_wait_guard.dart',
    'meritrank_lock_probe.dart',
    'forwarded_request_field_response.dart',
  ];
  final paths = <String, String>{
    for (final name in names)
      File('test/support/$name').absolute.uri.toString(): File(
        '${directory.path}/$name',
      ).absolute.uri.toString(),
  };
  for (final name in names) {
    final original = File('test/support/$name');
    var source = original.readAsStringSync();
    if (name == 'disposable_pg_target.dart') {
      const lock = "Sql.named('SELECT pg_advisory_lock(hashtext(@key))'),";
      expect(lock.allMatches(source), hasLength(1));
      source = source.replaceFirst(
        '    await connection.execute(\n      $lock',
        r'''
    if (Zone.current[#provenanceProvisioning] == true) {
      final identity = await connection.execute('SELECT pg_backend_pid()');
      observedProvenanceProvisioningPid = identity.first[0]! as int;
      print('PROVENANCE_PROVISIONING_PID:$observedProvenanceProvisioningPid');
    }
    await connection.execute(
      ''' +
            lock,
      );
      source =
          "import 'dart:async';\n$source\n"
          'int? observedProvenanceProvisioningPid;\n';
    } else if (name == 'forwarded_request_field_response.dart') {
      expect(source, contains('return setUpDisposablePgWriter('));
      source = source.replaceFirst(
        'return setUpDisposablePgWriter(',
        'return runZoned(() => setUpDisposablePgWriter(',
      );
      source = source.replaceFirst(
        'createPgmer2Extension: true,\n  );',
        'createPgmer2Extension: true,\n  ), '
            'zoneValues: {#provenanceProvisioning: true});',
      );
      source = "import 'dart:async';\n$source";
    }
    source = _absoluteImports(source, original);
    for (final entry in paths.entries) {
      source = source.replaceAll("'${entry.key}'", "'${entry.value}'");
    }
    File.fromUri(
      Uri.parse(paths[original.absolute.uri.toString()]!),
    ).writeAsStringSync(source);
  }
  return paths;
}

// The snapshot runs in another process while the test worker is synchronously
// paused at complete(). It therefore cannot create a waiter by allowing that
// worker to advance provisioning after it has already decided to release.
// The subprocess has its own hard timeout and only reads the identified PID.
const _snapshotSource = r'''
import 'dart:io';
import 'package:postgres/postgres.dart';
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final connection = await Connection.open(
    Endpoint(host: env['POSTGRES_HOST'] ?? '127.0.0.1',
      port: int.parse(env['POSTGRES_PORT'] ?? '5432'),
      database: env['POSTGRES_ADMIN_DBNAME'] ?? 'postgres',
      username: env['POSTGRES_USERNAME'] ?? 'postgres',
      password: env['POSTGRES_PASSWORD'] ?? 'password'),
    settings: const ConnectionSettings(sslMode: SslMode.disable,
      queryTimeout: Duration(seconds: 1)),
  );
  try {
    final rows = await connection.execute(Sql.named("""
SELECT EXISTS (
  SELECT 1 FROM pg_locks
  WHERE pid = @pid AND NOT granted AND locktype = 'advisory'
    AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND classid::bigint =
      ((hashtext('tentura_disposable_pg_lifecycle')::bigint >> 32) & 4294967295)
    AND objid::bigint =
      (hashtext('tentura_disposable_pg_lifecycle')::bigint & 4294967295)
    AND objsubid = 1
)
"""), parameters: {'pid': int.parse(args.single)});
    print('WAIT_SNAPSHOT:${rows.first[0]}');
  } finally {
    await connection.close();
  }
}
''';

// Mutate temporary copies only. All resolver, repository and Postgres code
// remains real; the negative case moves the original provisioning statement
// into the original test callback without adding an assertion on its behalf.
String _observedFixture(Directory directory, String variant, String snapshot) {
  final support = _instrumentedSupport(directory);
  final original = File(
    'test/data/repository/constellation_received_request_provenance_pg_test.dart',
  );
  var source = original.readAsStringSync();
  final registrations = _Registrations();
  parseString(content: source).unit.accept(registrations);
  final setup = registrations.calls.singleWhere(
    (call) => call.methodName.name == 'setUpAll',
  );
  final test = registrations.calls.firstWhere(
    (call) => call.methodName.name == 'test',
  );
  final body =
      (test.argumentList.arguments[1] as FunctionExpression).body
          as BlockFunctionBody;
  if (variant == 'body') {
    final setupBody =
        (setup.argumentList.arguments.single as FunctionExpression).body
            as BlockFunctionBody;
    final statements = setupBody.block.statements
        .map((s) => s.toSource())
        .join('\n');
    expect(statements, contains('setUpForwardedRequestField('));
    // The body comes after setUpAll, so edits in descending offset order keep
    // the AST offsets valid.
    source = source.replaceRange(
      body.block.leftBracket.end,
      body.block.leftBracket.end,
      '\n$statements\n',
    );
    final statement = setup.parent! as ExpressionStatement;
    source = source.replaceRange(statement.offset, statement.end, '');
  } else if (variant == 'absent') {
    source = source.replaceRange(body.block.offset, body.block.end, '{}');
    final statement = setup.parent! as ExpressionStatement;
    source = source.replaceRange(statement.offset, statement.end, '');
  } else if (variant == 'assertion') {
    source = source.replaceRange(
      body.block.offset,
      body.block.end,
      "{ fail('injected provenance assertion failure'); }",
    );
  }
  // Trace callback entry, rather than testStart: the runner may announce a
  // test before its setup has finished. Printing preserves worker event order.
  final traced = _Registrations();
  parseString(content: source).unit.accept(traced);
  final bodies =
      traced.calls
          .where((call) => call.methodName.name == 'test')
          .map(
            (call) =>
                (call.argumentList.arguments[1] as FunctionExpression).body
                    as BlockFunctionBody,
          )
          .toList()
        ..sort((a, b) => b.offset.compareTo(a.offset));
  for (final body in bodies) {
    source = source.replaceRange(
      body.block.leftBracket.end,
      body.block.leftBracket.end,
      "print('PROVENANCE_BODY_ENTERED');",
    );
  }
  var provenanceSource = _absoluteImports(source, original);
  for (final entry in support.entries) {
    provenanceSource = provenanceSource.replaceAll(
      "'${entry.key}'",
      "'${entry.value}'",
    );
  }
  final provenance = File('${directory.path}/provenance.dart')
    ..writeAsStringSync(provenanceSource);
  final contention = File(_suite);
  final child = File('${directory.path}/contention.dart');
  var contender = contention.readAsStringSync();
  expect(
    contender,
    contains('final release = Completer<void>();'),
    reason: 'The fixture observes the existing release completer.',
  );
  contender = contender.replaceFirst(
    'final release = Completer<void>();',
    'final release = _ObservedReleaseCompleter();',
  );
  if (variant == 'connection') {
    const observing = '    try {\n      while (!stop.isCompleted) {';
    expect(
      observing.allMatches(contender),
      hasLength(1),
      reason:
          'Inject the failure in the real lock observer, after connection opens.',
    );
    contender = contender.replaceFirst(observing, '''
    try {
      print('INJECTING_OBSERVER_CONNECTION_FAILURE');
      await observer.execute('SELECT pg_terminate_backend(pg_backend_pid())');
      while (!stop.isCompleted) {''');
  }
  var contenderSource = _absoluteImports(
    contender.replaceFirst(
      "'constellation_received_request_provenance_pg_test.dart' as provenance",
      "'${provenance.absolute.uri}' as provenance",
    ),
    contention,
  );
  for (final entry in support.entries) {
    contenderSource = contenderSource.replaceAll(
      "'${entry.key}'",
      "'${entry.value}'",
    );
  }
  child.writeAsStringSync(
    "${contenderSource.replaceFirst("import 'dart:async';", "import 'dart:async';\nimport 'dart:io';")}\n"
    'const _snapshotKernel = ${jsonEncode(snapshot)};\n'
    r'''


// Observe before delegating; the worker cannot advance during the snapshot.
class _ObservedReleaseCompleter implements Completer<void> {
  final _delegate = Completer<void>();
  @override
  Future<void> get future => _delegate.future;
  @override
  bool get isCompleted => _delegate.isCompleted;
  @override
  void complete([FutureOr<void>? value]) {
    final pid = observedProvenanceProvisioningPid;
    if (pid != null) {
      final result = Process.runSync('timeout', [
        '3s', Platform.resolvedExecutable, _snapshotKernel, '$pid',
      ]);
      if (result.exitCode != 0) {
        throw StateError('Release snapshot failed: ${result.stderr}');
      }
      print('LIFECYCLE_RELEASE_SNAPSHOT:$pid:${result.stdout.toString().trim()}');
    } else {
      print('LIFECYCLE_RELEASE_SNAPSHOT:no-provisioning-pid');
    }
    print('LIFECYCLE_RELEASE_REQUESTED');
    _delegate.complete(value);
  }
  @override
  void completeError(Object error, [StackTrace? stackTrace]) {
    _delegate.completeError(error, stackTrace);
  }
}
''',
  );
  return child.path;
}

// Query only this run's private admin database: advisory locks in another
// database must never satisfy either the contention or the cleanup assertion.
Future<List<ResultRow>> _lifecycleLocks(Connection admin) => admin.execute('''
SELECT pid, granted FROM pg_locks
WHERE locktype = 'advisory'
  AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND classid::bigint =
      ((hashtext('tentura_disposable_pg_lifecycle')::bigint >> 32) & 4294967295)
  AND objid::bigint =
      (hashtext('tentura_disposable_pg_lifecycle')::bigint & 4294967295)
  AND objsubid = 1
''');

void main() {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PROVENANCE_LOCK_LIFETIME_DB',
    defaultNamePrefix: 'tentura_test_provenance_lock',
  );
  final adminName = target.databaseName;
  final fieldName = '${adminName}_field';
  Connection? cluster;
  Connection? observer;
  final probeDirectory = Directory.systemTemp.createTempSync(
    'provenance_snapshot_',
  );
  final snapshot = File('${probeDirectory.path}/snapshot.dill').absolute.path;

  setUpAll(() async {
    final probeSource = File('${probeDirectory.path}/snapshot.dart')
      ..writeAsStringSync(_snapshotSource);
    final compiled = await Process.run('timeout', [
      '45s',
      Platform.resolvedExecutable,
      'compile',
      'kernel',
      '--packages=${File('../../.dart_tool/package_config.json').absolute.path}',
      probeSource.path,
      '-o',
      snapshot,
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}\n${compiled.stderr}',
    );
    // An isolated admin database gives the child the real lifecycle lock
    // without letting unrelated suites count as its holder or waiter.
    cluster = await Connection.open(
      target.adminEnv.pgEndpoint,
      settings: target.adminEnv.pgEndpointSettings,
    );
    await cluster!.execute('CREATE DATABASE "$adminName"');
    observer = await Connection.open(
      Endpoint(
        host: target.adminEnv.pgEndpoint.host,
        port: target.adminEnv.pgEndpoint.port,
        database: adminName,
        username: target.adminEnv.pgEndpoint.username,
        password: target.adminEnv.pgEndpoint.password,
      ),
      settings: ConnectionSettings(
        sslMode: target.adminEnv.pgEndpointSettings.sslMode,
        queryTimeout: const Duration(seconds: 2),
      ),
    );
  });

  tearDownAll(() async {
    probeDirectory.deleteSync(recursive: true);
    await observer?.close();
    final connection = cluster;
    if (connection != null) {
      try {
        // Also clean up a child interrupted by the six-second watchdog.
        await connection.execute(
          'DROP DATABASE IF EXISTS "$fieldName" WITH (FORCE)',
        );
        await connection.execute(
          'DROP DATABASE IF EXISTS "$adminName" WITH (FORCE)',
        );
      } finally {
        await connection.close();
      }
    }
  });

  for (final variant in [
    'normal',
    'body',
    'assertion',
    'absent',
    'connection',
  ]) {
    test(
      switch (variant) {
        'normal' =>
          'provenance assertions complete with a lifecycle lock hold below five seconds',
        'body' =>
          'provisioning moved into a test body is rejected before its thirty second budget',
        'connection' =>
          'a terminated observer connection fails promptly without lifecycle lock holders or waiters',
        'absent' =>
          'a suite with no provisioning contention is rejected without leaking a lifecycle lock',
        _ =>
          'a failed provenance assertion leaves no lifecycle lock holder or waiter',
      },
      () async {
        final admin = observer!;
        final fixture = Directory.systemTemp.createTempSync(
          'provenance_contract_',
        );
        addTearDown(() => fixture.deleteSync(recursive: true));
        final suite = _observedFixture(fixture, variant, snapshot);
        // Verify the independent snapshot helper before any timed work begins.
        final probeCheck = await Process.run(
          'timeout',
          [
            '3s',
            Platform.resolvedExecutable,
            snapshot,
            '0',
          ],
          environment: {
            ...Platform.environment,
            'POSTGRES_ADMIN_DBNAME': adminName,
          },
        );
        expect(
          probeCheck.exitCode,
          0,
          reason: '${probeCheck.stdout}\n${probeCheck.stderr}',
        );
        expect(probeCheck.stdout.toString(), contains('WAIT_SNAPSHOT:false'));
        // Queue the child behind a shared lock before letting it acquire its
        // exclusive hold. This handshake works even if the repaired hold is too
        // short to catch by polling: its queued backend is already identified.
        // This identifies the holder, not a provenance provisioning waiter.
        // The absent-provisioning mutation separately rejects vacuous success.
        await admin.execute(
          "SELECT pg_advisory_lock_shared(hashtext('tentura_disposable_pg_lifecycle'))",
        );
        final child = await Process.start(
          'setsid',
          [
            Platform.resolvedExecutable,
            'test',
            '--reporter=json',
            suite,
          ],
          environment: {
            ...Platform.environment,
            'POSTGRES_ADMIN_DBNAME': adminName,
            'TENTURA_FORWARDED_REQUEST_FIELD_TEST_DB': fieldName,
            'TENTURA_PG_TESTS_REQUIRED': '1',
          },
        );
        final output = StringBuffer();
        final errors = StringBuffer();
        final events = <Map<String, dynamic>>[];
        final stdoutDone = child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) {
              output.writeln(line);
              if (line.startsWith('{')) {
                events.add(jsonDecode(line) as Map<String, dynamic>);
              }
            });
        final stderrDone = child.stderr
            .transform(utf8.decoder)
            .forEach(errors.write);
        int? exitCode;
        final exited = child.exitCode.then((code) => exitCode = code);
        final startup = Stopwatch()..start();
        Stopwatch? held;
        Stopwatch? mutationBudget;
        int? holderPid;
        var released = false;
        try {
          while (exitCode == null) {
            final locks = await _lifecycleLocks(admin);
            if (holderPid == null) {
              final waiters = locks.where((row) => row[1] == false);
              if (waiters.isNotEmpty) {
                holderPid = waiters.single[0]! as int;
                held = Stopwatch()..start();
                mutationBudget = Stopwatch()..start();
                await admin.execute(
                  "SELECT pg_advisory_unlock_shared(hashtext('tentura_disposable_pg_lifecycle'))",
                );
              }
            } else if (!released) {
              if (!locks.any((row) => row[0] == holderPid)) {
                held!.stop();
                released = true;
              }
              // This is an upper bound: it includes scheduling between the
              // parent's unlock and the child's acquisition, plus one poll.
              // The extra second stops the work when the old timer is present.
              if (!released &&
                  held!.elapsed >
                      Duration(seconds: variant == 'body' ? 24 : 6)) {
                final identities = events.where(
                  (event) =>
                      event['type'] == 'print' &&
                      event['message'].toString().startsWith(
                        'PROVENANCE_PROVISIONING_PID:',
                      ),
                );
                if (variant != 'absent') {
                  expect(
                    identities,
                    isNotEmpty,
                    reason:
                        'The real provisioning connection must identify itself.',
                  );
                  final pid = int.parse(
                    identities.first['message'].toString().split(':').last,
                  );
                  expect(
                    locks.any((row) => row[0] == pid && row[1] == false),
                    isTrue,
                    reason:
                        'The identified provenance backend must actually be queued.',
                  );
                }
                fail(
                  'Lifecycle lock exceeded the ${variant == 'body' ? 24 : 6}-second watchdog. '
                  'Release must follow observed contention, not a 35-second timer.',
                );
              }
            }
            if (variant == 'body' &&
                mutationBudget != null &&
                mutationBudget.elapsed > const Duration(seconds: 24)) {
              fail(
                'In-body provisioning was not rejected within 24 seconds; '
                'stop before the default 30-second behaviour timeout.',
              );
            }
            if (variant == 'connection' &&
                mutationBudget != null &&
                mutationBudget.elapsed > const Duration(seconds: 6)) {
              fail(
                'The connection-error child did not finish within six seconds.',
              );
            }
            if (startup.elapsed > const Duration(seconds: 90)) {
              fail(
                'Contention suite did not finish within 90 seconds.\n$output\n$errors',
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await Future.wait([stdoutDone, stderrDone]);
          // A fast failing child can exit between polls. Its final database
          // state still proves release; do not require an intermediate sample.
          if (held != null &&
              !released &&
              !(await _lifecycleLocks(
                admin,
              )).any((row) => row[0] == holderPid)) {
            held.stop();
            released = true;
          }
          if (variant == 'normal') {
            expect(exitCode, 0, reason: '$output\n$errors');
          } else {
            expect(
              exitCode,
              isNot(0),
              reason:
                  'The contention suite must reject $variant.\n$output\n$errors',
            );
            expect(
              '$output\n$errors',
              isNot(contains('TimeoutException')),
              reason:
                  'Reject bad ordering explicitly instead of spending the test budget.',
            );
            if (variant == 'connection') {
              expect(
                '$output\n$errors',
                contains('INJECTING_OBSERVER_CONNECTION_FAILURE'),
              );
              expect(
                '$output\n$errors',
                contains('57P01'),
                reason:
                    'The child must report the actual PostgreSQL connection termination.',
              );
            }
            if (variant == 'assertion') {
              expect(
                '$output\n$errors',
                contains('injected provenance assertion failure'),
              );
            }
          }
          expect(
            holderPid,
            isNotNull,
            reason: 'The child must request the real lifecycle lock.',
          );
          expect(released, isTrue);
          if (variant == 'body') {
            expect(
              mutationBudget!.elapsed,
              lessThan(const Duration(seconds: 24)),
              reason:
                  'The mutated suite must finish before its default 30-second timeout.',
            );
          }
          if (variant == 'connection') {
            expect(
              mutationBudget!.elapsed,
              lessThan(const Duration(seconds: 5)),
              reason:
                  'Connection failure must finish promptly, including teardown.',
            );
          }
          expect(
            held!.elapsed,
            lessThan(Duration(seconds: variant == 'body' ? 24 : 5)),
          );
          if (variant == 'normal' || variant == 'assertion') {
            final identity = events.where(
              (event) =>
                  event['type'] == 'print' &&
                  event['message'].toString().startsWith(
                    'PROVENANCE_PROVISIONING_PID:',
                  ),
            );
            expect(identity, isNotEmpty, reason: '$output');
            final provisioningPid = identity.first['message']
                .toString()
                .split(':')
                .last;
            expect(
              int.parse(provisioningPid),
              isNot(holderPid),
              reason:
                  'The provisioning backend must differ from the contention holder.',
            );
            final snapshots = events.where(
              (event) =>
                  event['type'] == 'print' &&
                  event['message'].toString().startsWith(
                    'LIFECYCLE_RELEASE_SNAPSHOT:',
                  ),
            );
            expect(snapshots, isNotEmpty, reason: '$output');
            expect(
              snapshots.first['message'],
              'LIFECYCLE_RELEASE_SNAPSHOT:$provisioningPid:WAIT_SNAPSHOT:true',
              reason:
                  'That exact provenance provisioning PID must be waiting '
                  'on this database and lifecycle key when release is requested.',
            );
          }
          if (variant == 'normal') {
            final releaseEvent = events.indexWhere(
              (event) =>
                  event['type'] == 'print' &&
                  event['message'] == 'LIFECYCLE_RELEASE_REQUESTED',
            );
            final bodyEntries = <int>[
              for (var i = 0; i < events.length; i++)
                if (events[i]['type'] == 'print' &&
                    events[i]['message'] == 'PROVENANCE_BODY_ENTERED')
                  i,
            ];
            expect(releaseEvent, greaterThanOrEqualTo(0), reason: '$output');
            expect(bodyEntries, isNotEmpty, reason: '$output');
            expect(
              bodyEntries,
              everyElement(greaterThan(releaseEvent)),
              reason: 'Every actual provenance body must enter after release.',
            );
          }
          final provenanceTests = events
              .where((event) => event['type'] == 'testStart')
              .map((event) => event['test'] as Map<String, dynamic>)
              .where(
                (test) => (test['name']! as String).startsWith(
                  '$_group the Field response',
                ),
              )
              .toList();
          if (variant == 'normal' || variant == 'assertion') {
            expect(provenanceTests, hasLength(1), reason: '$output');
          }
          if (variant == 'normal') {
            for (final test in provenanceTests) {
              expect(
                events,
                contains(
                  allOf([
                    containsPair('type', 'testDone'),
                    containsPair('testID', test['id']),
                    containsPair('result', 'success'),
                    containsPair('skipped', false),
                  ]),
                ),
                reason:
                    'The real provenance assertion must run and pass.\n$output',
              );
            }
          }
          expect(await _lifecycleLocks(admin), isEmpty);
        } finally {
          await admin.execute(
            'SELECT pg_advisory_unlock_all()',
          );
          if (exitCode == null) {
            // Kill the complete process group, including the test worker, so
            // the watchdog cannot strand an advisory lock or a Dart process.
            await Process.run('kill', ['-KILL', '--', '-${child.pid}']);
          }
          await exited.timeout(const Duration(seconds: 5));
          await Future.wait([
            stdoutDone,
            stderrDone,
          ]).timeout(const Duration(seconds: 5));
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
