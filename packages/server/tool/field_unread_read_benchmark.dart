// Run against tentura_perfsynth using the parent or working-tree package config.
// Usage: dart --packages=<config> tool/field_unread_read_benchmark.dart
//        <label> <report.json> [parent-report.json]
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field_requests.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_requests_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/domain/use_case/constellation_field_requests_case.dart';
import 'package:tentura_server/env.dart';

import '../test/support/query_counter.dart';

const _database = 'tentura_perfsynth';
const _viewer = 'U66728b9dba8d';
const _warmups = 20;
const _samples = 200;
const _auth = {kGlobalInputQueryJwt: JwtEntity(sub: _viewer)};

Future<void> main(List<String> args) async {
  if (args.length < 2 || args.length > 3) {
    throw ArgumentError(
      'Expected label, report path, and optional parent report',
    );
  }
  final counter = QueryCounter();
  final env = Env(
    environment: Environment.test,
    pgHost: '127.0.0.1',
    pgPort: 5432,
    pgDatabase: _database,
    pgUsername: 'postgres',
    pgPassword: 'password',
    printEnv: false,
    isDebugModeOn: false,
  );
  final db = TenturaDb(env, scopeInterceptor: () => counter);
  try {
    // Fail on an unavailable/wrong database, without substituting a fixture.
    final database = await db
        .customSelect('SELECT current_database() AS name')
        .getSingle();
    if (database.read<String>('name') != _database) {
      throw StateError('Not connected to $_database');
    }
    final logger = Logger('FieldReadBenchmark');
    final full = QueryConstellationField(
      constellationFieldCase: ConstellationFieldCase(
        ConstellationFieldRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
        ),
        env: env,
        logger: logger,
      ),
    ).constellationField.resolve;
    final refresh = QueryConstellationFieldRequests(
      case_: ConstellationFieldRequestsCase(
        ConstellationFieldRequestsRepository(db),
        env: env,
        logger: logger,
      ),
    ).constellationFieldRequests.resolve;
    if (full == null || refresh == null) {
      throw StateError('Missing Field resolver');
    }
    Future<Object?> readFull() => Future<Object?>.value(
      full(null, {
        ..._auth,
        'projection': 'FULL',
        'showClosed': false,
        'participatedOnly': false,
      }),
    );
    final initial = await readFull();
    if (initial is! Map<String, dynamic>) {
      throw StateError('Missing FULL response');
    }
    final requests = List<Map<String, dynamic>>.from(
      initial['requests'] as List,
    );
    final List<String> ids;
    if (args.length == 3) {
      final parent =
          jsonDecode(File(args[2]).readAsStringSync()) as Map<String, dynamic>;
      ids = List<String>.from(parent['refresh_ids'] as List);
    } else {
      ids = [
        for (final row in requests)
          if (row['isMine'] == false && row['kind'] == 0) row['id'] as String,
      ]..sort();
      if (ids.length < 20) {
        throw StateError('Expected at least 20 real Requests');
      }
      ids.removeRange(20, ids.length);
    }
    if (ids.length != 20 || ids.toSet().length != 20) {
      throw StateError('Refresh requires the same 20 distinct Request IDs');
    }
    Future<Object?> readRefresh() => Future<Object?>.value(
      refresh(null, {
        ..._auth,
        'ids': ids,
        'showClosed': false,
        'participatedOnly': false,
      }),
    );
    final refreshed = await readRefresh();
    if (refreshed is! List || refreshed.length != ids.length) {
      throw StateError('Refresh did not return all 20 real Requests');
    }
    final refreshedIds = [
      for (final row in refreshed.cast<Map<String, dynamic>>())
        row['id'] as String,
    ]..sort();
    if (jsonEncode(refreshedIds) != jsonEncode(ids)) {
      throw StateError('Refresh returned different Request IDs');
    }
    final report = {
      'label': args[0],
      'measured_at_utc': DateTime.now().toUtc().toIso8601String(),
      'database': _database,
      'viewer': _viewer,
      'server_library': (await Isolate.resolvePackageUri(
        Uri.parse(
          'package:tentura_server/data/repository/constellation_field_repository.dart',
        ),
      ))?.toString(),
      'warmup_reads_per_operation': _warmups,
      'samples_per_operation': _samples,
      'shape': {
        'peers': (initial['peers'] as List).length,
        'requests': requests.length,
        'posts': (initial['posts'] as List).length,
        'request_ids': [for (final row in requests) row['id']],
      },
      'refresh_ids': ids,
      'full': await _measure(readFull, counter),
      'requests_refresh': await _measure(readRefresh, counter),
    };
    File(args[1]).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    stdout.writeln('Report: ${args[1]}');
  } finally {
    await db.close();
  }
}

Future<Map<String, Object>> _measure(
  Future<Object?> Function() read,
  QueryCounter counter,
) async {
  for (var i = 0; i < _warmups; i++) {
    _encode(await read());
  }
  final times = <double>[];
  final statements = <int>{};
  final payloadSizes = <int>{};
  for (var i = 0; i < _samples; i++) {
    counter.reset();
    final timer = Stopwatch()..start();
    final payload = _encode(await read());
    timer.stop();
    times.add(timer.elapsedMicroseconds / 1000);
    statements.add(counter.count);
    payloadSizes.add(utf8.encode(payload).length);
  }
  final sorted = List<double>.from(times)..sort();
  return {
    'mean_ms': times.reduce((a, b) => a + b) / times.length,
    'p50_ms': (sorted[99] + sorted[100]) / 2,
    'p95_ms': sorted[189],
    'sql_statements': statements.toList()..sort(),
    'payload_bytes': payloadSizes.toList()..sort(),
    'samples_ms': times,
  };
}

String _encode(Object? value) => jsonEncode(
  value,
  toEncodable: (value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    throw StateError('Unexpected wire value: ${value.runtimeType}');
  },
);
