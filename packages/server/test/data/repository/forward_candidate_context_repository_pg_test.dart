@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_candidate_context_repository.dart';
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

const _viewer = 'Ufctx_viewer';
const _candidate = 'Ufctx_candidate';
const _middle = 'Ufctx_middle';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late ForwardCandidateContextRepository repository;
  late MeritrankRepository meritRank;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      repository = ForwardCandidateContextRepository(database);
      meritRank = MeritrankRepository(database);
    });

    setUp(() async {
      await meritRank.reset();
      await database.customStatement('DELETE FROM public.user_block');
      await database.customStatement('DELETE FROM public.vote_user');
      await database.customStatement('DELETE FROM public.image');
      await database.customStatement('DELETE FROM public."user"');
      await _insertUser(database, _viewer, 1);
      await _insertUser(database, _candidate, 2);
      await _insertUser(database, _middle, 3);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  group('ForwardCandidateContextRepository', () {
    test(
      'valid candidate returns authorized adjacent edges and projections',
      () async {
        await _makeCandidateEligible(database);
        await _putPath(meritRank, context: 'personal');

        final snapshot = await repository.loadSnapshot(
          viewerId: _viewer,
          candidateId: _candidate,
          context: 'personal',
        );

        expect(snapshot.candidateEligible, isTrue);
        expect(snapshot.edges, isNotEmpty);
        expect(
          snapshot.edges.any(
            (edge) => {edge.a, edge.b}.containsAll([_viewer, _middle]),
          ),
          isTrue,
        );
        expect(snapshot.people[_viewer]?.displayName, 'Viewer');
        expect(snapshot.people[_candidate]?.displayName, 'Candidate');
      },
      skip: skipReason,
    );

    test('missing candidate is generic unavailable', () async {
      final snapshot = await repository.loadSnapshot(
        viewerId: _viewer,
        candidateId: 'Ufctx_missing',
        context: 'personal',
      );

      expect(snapshot.candidateEligible, isFalse);
      expect(snapshot.edges, isEmpty);
      expect(snapshot.people, isEmpty);
    }, skip: skipReason);

    test('direct candidate block is generic unavailable', () async {
      await _makeCandidateEligible(database);
      await database.customStatement('''
        INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
        VALUES ('$_viewer', '$_candidate', '$_candidate')
      ''');

      final snapshot = await repository.loadSnapshot(
        viewerId: _viewer,
        candidateId: _candidate,
        context: 'personal',
      );

      expect(snapshot.candidateEligible, isFalse);
      expect(snapshot.edges, isEmpty);
      expect(snapshot.people, isEmpty);
    }, skip: skipReason);

    test('inherited candidate block is generic unavailable', () async {
      await _makeCandidateEligible(database);
      await database.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_viewer', '$_candidate', '$_middle')
''');

      final snapshot = await repository.loadSnapshot(
        viewerId: _viewer,
        candidateId: _candidate,
        context: 'personal',
      );

      expect(snapshot.candidateEligible, isFalse);
      expect(snapshot.edges, isEmpty);
      expect(snapshot.people, isEmpty);
    }, skip: skipReason);

    test('blocked intermediary edges are removed before traversal', () async {
      await _makeCandidateEligible(database);
      await _putPath(meritRank, context: 'personal');
      await database.customStatement('''
        INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
        VALUES ('$_viewer', '$_middle', '$_middle')
      ''');

      final snapshot = await repository.loadSnapshot(
        viewerId: _viewer,
        candidateId: _candidate,
        context: 'personal',
      );

      expect(snapshot.candidateEligible, isTrue);
      expect(
        snapshot.edges.any(
          (edge) => edge.a == _middle || edge.b == _middle,
        ),
        isFalse,
      );
      expect(snapshot.people.containsKey(_middle), isFalse);
    }, skip: skipReason);

    test(
      'deleted intermediary remains unhydrated without losing edge',
      () async {
        await _makeCandidateEligible(database);
        await _putPath(meritRank, context: 'personal');
        await database.customStatement(
          'DELETE FROM public."user" WHERE id = \'$_middle\'',
        );

        final snapshot = await repository.loadSnapshot(
          viewerId: _viewer,
          candidateId: _candidate,
          context: 'personal',
        );

        expect(snapshot.candidateEligible, isTrue);
        expect(
          snapshot.edges.any(
            (edge) => edge.a == _middle || edge.b == _middle,
          ),
          isTrue,
        );
        expect(snapshot.people.containsKey(_middle), isFalse);
      },
      skip: skipReason,
    );

    test('context is normalized before visibility and graph reads', () async {
      await _makeCandidateEligible(database);
      await _putPath(meritRank, context: 'personal');

      final snapshot = await repository.loadSnapshot(
        viewerId: _viewer,
        candidateId: _candidate,
        context: ' personal ',
      );

      expect(snapshot.candidateEligible, isTrue);
      expect(snapshot.edges, isNotEmpty);
    }, skip: skipReason);

    test('graph result respects the 100-row request cap', () async {
      await _makeCandidateEligible(database);
      for (var index = 0; index < 110; index++) {
        final id = 'Ufctx_node_${index.toString().padLeft(3, '0')}';
        await meritRank.putEdge(
          nodeA: _viewer,
          nodeB: id,
          context: 'personal',
        );
        await meritRank.putEdge(
          nodeA: id,
          nodeB: _candidate,
          context: 'personal',
        );
      }
      await meritRank.calculate();

      final snapshot = await repository.loadSnapshot(
        viewerId: _viewer,
        candidateId: _candidate,
        context: 'personal',
      );

      expect(snapshot.candidateEligible, isTrue);
      expect(snapshot.edges, isNotEmpty);
      expect(snapshot.edges.length, lessThanOrEqualTo(100));
    }, skip: skipReason);
  });
}

Future<void> _makeCandidateEligible(TenturaDb database) =>
    database.customStatement('''
      INSERT INTO public.vote_user (subject, object, amount)
      VALUES
        ('$_viewer', '$_candidate', 1),
        ('$_candidate', '$_viewer', 1)
      ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
    ''');

Future<void> _putPath(
  MeritrankRepository meritRank, {
  required String context,
}) async {
  await meritRank.putEdge(
    nodeA: _viewer,
    nodeB: _middle,
    context: context,
  );
  await meritRank.putEdge(
    nodeA: _middle,
    nodeB: _candidate,
    context: context,
  );
  await meritRank.calculate();
}

Future<void> _insertUser(
  TenturaDb database,
  String id,
  int keyIndex,
) => database.customStatement('''
  INSERT INTO public."user" (
    id, display_name, description, public_key, created_at, updated_at
  ) VALUES (
    '$id',
    '${id == _viewer
    ? 'Viewer'
    : id == _candidate
    ? 'Candidate'
    : 'Middle'}',
    '',
    '${pgTestPublicKey('fctx', keyIndex)}',
    '2026-01-01T00:00:00Z',
    '2026-01-01T00:00:00Z'
  )
''');

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } catch (_) {
    return false;
  }
}

final class _DisposablePgTarget {
  _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? 'localhost';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_FORWARD_CONTEXT_TEST_DB'] ??
        'tentura_test_forward_context_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_FORWARD_CONTEXT_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }
    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );
    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
