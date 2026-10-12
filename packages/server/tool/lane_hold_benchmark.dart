// Run through scripts/perf/measure_lane_hold.py; no git writes are needed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
// SQL text is exposed only by postgres's implementation type.
import 'package:postgres/src/v3/query_description.dart' show SqlImpl;
import 'package:test/test.dart' show TestFailure;
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';
import 'package:uuid/uuid.dart';

import '../test/support/disposable_pg_target.dart';
import '../test/support/lane_hold_perf_workloads.dart';
import '../test/support/transaction_statement_recorder.dart';

const _workloads = {
  'trust_publish_ack': 200,
  'attention_capture': 1201,
  'attention_apply': 200,
  'attention_undo': 1201,
  'user_erasure_published': 1201,
  'user_erasure_drafts': 1201,
  'contact_resolution': 200,
};

/// PostgreSQL clocks bracket the actual BEGIN and awaited COMMIT. Instrumentation
/// queries use the same connection, outside the measured production SQL. Both
/// source snapshots pay the same two clock-query round trips per transaction.
final class _ClockConnection implements Connection {
  _ClockConnection(this.delegate);

  final Connection delegate;
  final samples = <RecordedTransaction, (DateTime, DateTime)>{};
  RecordedTransaction Function()? currentTransaction;
  RecordedTransaction? _transaction;
  DateTime? _acquired;

  Future<DateTime> _clock() async =>
      (await delegate.execute('SELECT clock_timestamp()')).single.single!
          as DateTime;

  @override
  Future<Result> execute(
    Object query, {
    Object? parameters,
    bool ignoreRows = false,
    QueryMode? queryMode,
    Duration? timeout,
  }) async {
    final sql = (query is SqlImpl ? query.sql : query.toString()).trim();
    if (sql == 'BEGIN TRANSACTION') {
      _transaction = currentTransaction!();
      _acquired = await _clock();
    }
    final result = await delegate.execute(
      query,
      parameters: parameters,
      ignoreRows: ignoreRows,
      queryMode: queryMode,
      timeout: timeout,
    );
    if (sql == 'COMMIT TRANSACTION') {
      samples[_transaction!] = (_acquired!, await _clock());
      _transaction = null;
      _acquired = null;
    } else if (sql == 'ROLLBACK TRANSACTION') {
      throw StateError('A rolled-back workload is not performance evidence');
    }
    return result;
  }

  @override
  bool get isOpen => delegate.isOpen;
  @override
  Future<void> get closed => delegate.closed;
  @override
  ConnectionInfo get info => delegate.info;
  @override
  Channels get channels => delegate.channels;
  @override
  Future<Statement> prepare(Object query) => delegate.prepare(query);
  @override
  Future<R> run<R>(
    Future<R> Function(Session) fn, {
    SessionSettings? settings,
  }) => delegate.run(fn, settings: settings);
  @override
  Future<R> runTx<R>(
    Future<R> Function(TxSession) fn, {
    TransactionSettings? settings,
  }) => delegate.runTx(fn, settings: settings);
  @override
  Future<void> close({bool force = false}) => delegate.close(force: force);
}

Future<void> main(List<String> args) async {
  Logger.root.onRecord.listen(
    (r) => stderr.writeln(
      '${r.level} ${r.loggerName}: ${r.message} ${r.error ?? ''}',
    ),
  );
  final databaseName = Platform.environment['TENTURA_LANE_HOLD_PERF_DB'];
  if (databaseName == null || args.isEmpty) {
    throw ArgumentError(
      'Set TENTURA_LANE_HOLD_PERF_DB and use prepare, '
      'or before|after SOURCE_ROOT OUTPUT_JSON',
    );
  }
  // Only a dedicated test/perf database may be created or seeded by this tool.
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_LANE_HOLD_PERF_DB',
    defaultNamePrefix: 'tentura_test_lane_hold_perf',
  );
  if (args.singleOrNull == 'prepare') {
    final admin = await Connection.open(
      target.adminEnv.pgEndpoint,
      settings: target.adminEnv.pgEndpointSettings,
    );
    try {
      final existing = await admin.execute(
        Sql.named('SELECT 1 FROM pg_database WHERE datname = @name'),
        parameters: {'name': databaseName},
      );
      if (existing.isEmpty) {
        throw StateError(
          'Clone tentura_devcopy or perfsynth to $databaseName before '
          'running the benchmark',
        );
      } else {
        final writer = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        try {
          await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
          await migrateDbSchema(writer);
        } finally {
          await writer.close();
        }
      }
    } finally {
      await admin.close();
    }
    return;
  }
  if (args.length != 3 || !['before', 'after'].contains(args[0])) {
    throw ArgumentError('Use before|after SOURCE_ROOT OUTPUT_JSON');
  }
  final phase = args[0];
  final source = Directory('${args[1]}/lib');
  final files = source.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final bytes = BytesBuilder(copy: false);
  for (final file in files) {
    bytes
      ..add(utf8.encode('${file.path.substring(source.path.length)}\u0000'))
      ..add(file.readAsBytesSync())
      ..add([0]);
  }
  final revision = sha1.convert(bytes.takeBytes()).toString();
  final connection = await Connection.open(
    target.databaseEnv.pgEndpoint,
    settings: const ConnectionSettings(
      sslMode: SslMode.disable,
      connectTimeout: Duration(seconds: 5),
      queryTimeout: Duration(minutes: 2),
    ),
  );
  try {
    await connection.execute('CREATE SCHEMA IF NOT EXISTS tentura_perf');
    await connection.execute('''
      CREATE TABLE IF NOT EXISTS tentura_perf.lane_hold_samples (
        run_id uuid NOT NULL, sample_ordinal integer NOT NULL,
        source_revision text NOT NULL, workload text NOT NULL,
        workload_rows integer NOT NULL,
        lane_acquired_at timestamptz NOT NULL,
        lane_released_at timestamptz NOT NULL,
        PRIMARY KEY (run_id, sample_ordinal)
      )''');
    final paths = <Map<String, Object?>>[];
    for (final workload in _workloads.entries) {
      final clocks = _ClockConnection(connection);
      final fixture = LaneHoldPerfWorkloads(
        clocks,
        Env(environment: Environment.test, printEnv: false),
      );
      clocks.currentTransaction = () => fixture.recorder.transactions.last;
      final runId = const Uuid().v4();
      try {
        try {
          await fixture.run(workload.key, workload.value);
        } on TestFailure catch (_, stack) {
          // The unmodified baseline is expected to violate the new transaction
          // budget. Its row/authorization assertions must still succeed. Only
          // the final performance assertions may fail during a baseline run.
          if (phase != 'before' ||
              !stack.toString().contains(
                'transaction_statement_recorder.dart',
              ) ||
              (!stack.toString().contains('expectBoundedTransactions') &&
                  !stack.toString().contains(
                    'expectSyncOutsideTransactions',
                  ))) {
            rethrow;
          }
        }
        final transactions = fixture.recorder.transactions;
        if (transactions.isEmpty || transactions.any((t) => !t.committed)) {
          throw StateError('Missing committed ${workload.key} measurements');
        }
        for (var index = 0; index < transactions.length; index++) {
          final (acquired, released) = clocks.samples[transactions[index]]!;
          await connection.execute(
            Sql.named('''
INSERT INTO tentura_perf.lane_hold_samples VALUES (
              @run_id, @ordinal, @revision, @workload, @rows,
              @acquired, @released)'''),
            parameters: {
              'run_id': runId,
              'ordinal': index,
              'revision': revision,
              'workload': workload.key,
              'rows': workload.value,
              'acquired': acquired,
              'released': released,
            },
          );
        }
        final samples = await connection.execute(
          Sql.named('''
SELECT (extract(epoch FROM
            (lane_released_at - lane_acquired_at)) * 1000)::float8
            FROM tentura_perf.lane_hold_samples WHERE run_id = @run_id
            ORDER BY sample_ordinal'''),
          parameters: {'run_id': runId},
        );
        final durations = [for (final row in samples) row.single! as double];
        paths.add({
          'path': workload.key,
          'rows': workload.value,
          phase: {
            'runId': runId,
            'laneHoldsMs': durations,
            'worstCaseLaneHoldMs': durations.reduce((a, b) => a > b ? a : b),
          },
        });
        stdout.writeln('$phase ${workload.key}: ${durations.length} commits');
      } finally {
        await fixture.close();
      }
    }
    File(args[2]).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        '${phase}Revision': revision,
        'revisionKind': 'source_tree_sha1',
        'database': {
          'name': databaseName,
          'postgresVersion': (await connection.execute(
            'SHOW server_version',
          )).single.single,
        },
        'paths': paths,
      }),
    );
  } finally {
    await connection.close();
  }
}
