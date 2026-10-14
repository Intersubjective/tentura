import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';

import 'disposable_pg_target.dart';

const _actor = 'Usingleconnprobe';
const _stateSql = '''
SELECT pg_backend_pid()::text || ':' || txid_current()::text AS identity
''';
const _deadline = Duration(seconds: 8);

Future<String> _identity(TenturaDb db) async =>
    (await db.customSelect(_stateSql).getSingle()).read<String>('identity');

/// Opens a disposable database, builds the main pool from the target's own
/// Env (so any test pool override applies), and reports how two database
/// handles over that pool behave inside one unit of work:
///
/// * `sameLease`: a nested handle reuses the outer transaction's connection.
/// * `escapedHandle`: a handle that runs outside the outer scope's zone, so it
///   cannot see the held lease, asks for a connection of its own.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SINGLE_CONNECTION_PROBE_TEST_DB',
    defaultNamePrefix: 'tentura_test_single_conn_probe',
  );
  final session = await setUpDisposablePgWriter(target: target);
  final pool = MainDbPool(target.databaseEnv);
  final outerDb = TenturaDb.scoped(pool);
  final repositoryDb = TenturaDb.scoped(pool);
  var sameLease = 'hung';
  var escapedHandle = 'hung';
  var secondAdmission = 'hung';
  try {
    final identities = <String>[];
    try {
      await MutatingUnitOfWork(outerDb)
          .run<void>(
            actorUserId: _actor,
            action: () async {
              identities.add(await _identity(outerDb));
              await repositoryDb.withMutatingUser(_actor, () async {
                identities.add(await _identity(repositoryDb));
                await repositoryDb.transaction(() async {
                  identities.add(await _identity(repositoryDb));
                });
              });
              identities.add(await _identity(outerDb));
            },
          )
          .timeout(_deadline);
      sameLease = identities.toSet().length == 1 ? 'reused' : 'split';
    } on TimeoutException {
      sameLease = 'hung';
    } on Object {
      sameLease = 'failed';
    }

    try {
      await MutatingUnitOfWork(outerDb)
          .run<void>(
            actorUserId: _actor,
            action: () async {
              await _identity(outerDb);
              try {
                await Zone.root
                    .run(() => _identity(repositoryDb))
                    .timeout(_deadline);
                escapedHandle = 'acquired';
              } on TimeoutException {
                escapedHandle = 'hung';
              } on Object {
                escapedHandle = 'refused';
              }
            },
          )
          .timeout(_deadline * 2);
    } on Object {
      // The verdict was recorded inside the action.
    }
    try {
      await pool.admission.run<void>(() async {
        try {
          await Zone.root
              .run(() => pool.admission.run<void>(() async {}))
              .timeout(_deadline);
          secondAdmission = 'admitted';
        } on TimeoutException {
          secondAdmission = 'hung';
        } on Object {
          secondAdmission = 'refused';
        }
      });
    } on Object {
      // Verdict recorded inside the body.
    }
  } finally {
    stdout.writeln(
      jsonEncode({
        'poolCapacity': target.databaseEnv.pgPoolSettings.maxConnectionCount,
        'admissionSlots': pool.admission.maxConcurrent,
        'sameLease': sameLease,
        'escapedHandle': escapedHandle,
        'secondAdmission': secondAdmission,
      }),
    );
    await stdout.flush();
    try {
      await (() async {
        await outerDb.close();
        await repositoryDb.close();
        await pool.close();
        await tearDownDisposablePgWriter(session: session);
      })().timeout(const Duration(seconds: 20));
    } on Object {
      // Best effort: the verdict is already printed.
    }
    exit(0);
  }
}
