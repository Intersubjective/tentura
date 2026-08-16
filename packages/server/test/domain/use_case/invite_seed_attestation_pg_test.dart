@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/domain/use_case/invite_seed_attestation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_user_block_repository.dart';

const _inviterId = 'Ucapc4inv01';
const _inviteeId = 'Ucapc4inv02';
const _otherId = 'Ucapc4oth01';
const _invitationId = 'Icapc4inv001';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('InviteSeedAttestationCase (C4)', () {
    late Connection writer;
    late TenturaDb database;
    late InviteSeedAttestationCase case_;
    late Env env;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      env = target.databaseEnv;
      database = TenturaDb(env);
      final genealogyRepo = InviteGenealogyRepository(
        env,
        database,
        UserBlockRepository(env, database),
      );
      final promptRepo = InviteSeedPromptRepository(database);
      case_ = InviteSeedAttestationCase(
        promptRepo,
        genealogyRepo,
        CapabilityEvidenceRepository(database),
        FakeUserBlockRepository(),
        MutatingUnitOfWork(database),
        env: env,
        logger: Logger('InviteSeedAttestationPgTest'),
      );
    });

    setUp(() async {
      await writer.execute(r'''
DELETE FROM public.person_capability_event
WHERE observer_user_id LIKE 'Ucapc4%'
   OR subject_user_id LIKE 'Ucapc4%'
''');
      await writer.execute(r'''
DELETE FROM public.capability_evidence_edge
WHERE observer_user_id LIKE 'Ucapc4%'
   OR subject_user_id LIKE 'Ucapc4%'
''');
      await writer.execute(r'''
DELETE FROM public.capability_evidence_generation
WHERE observer_user_id LIKE 'Ucapc4%'
   OR subject_user_id LIKE 'Ucapc4%'
''');
      await writer.execute(r'''
DELETE FROM public.invite_seed_prompt_state
WHERE inviter_user_id LIKE 'Ucapc4%'
   OR invitee_user_id LIKE 'Ucapc4%'
''');
      await writer.execute(r'''
DELETE FROM public.invite_genealogy
WHERE invitation_id = 'Icapc4inv001'
''');
      await writer.execute(r'''
DELETE FROM public.invitation
WHERE id = 'Icapc4inv001'
''');
      await writer.execute(r'''
DELETE FROM public."user"
WHERE id LIKE 'Ucapc4%'
''');
      await _seedFixture(writer, env);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test('rejects a non-inviter', () async {
      await expectLater(
        case_.answer(
          actorId: _otherId,
          subjectId: _inviteeId,
          slugs: const ['transport'],
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    }, skip: skipReason);

    test('rejects invitee seeding inviter (directionality)', () async {
      await expectLater(
        case_.answer(
          actorId: _inviteeId,
          subjectId: _inviterId,
          slugs: const ['transport'],
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    }, skip: skipReason);

    test('re-answer replaces the prior attestation set', () async {
      await case_.answer(
        actorId: _inviterId,
        subjectId: _inviteeId,
        slugs: const ['transport'],
      );
      await case_.answer(
        actorId: _inviterId,
        subjectId: _inviteeId,
        slugs: const ['pets'],
      );

      final rows = await writer.execute(r'''
SELECT tag_slug
FROM public.person_capability_event
WHERE observer_user_id = 'Ucapc4inv01'
  AND subject_user_id = 'Ucapc4inv02'
  AND source_type = 4
  AND deleted_at IS NULL
ORDER BY tag_slug
''');
      expect(rows.map((r) => r[0]), ['pets']);

      final state = await writer.execute(r'''
SELECT state
FROM public.invite_seed_prompt_state
WHERE invitee_user_id = 'Ucapc4inv02'
''');
      expect(state.single[0], 1);
    }, skip: skipReason);

    test('skip records state 2 and writes no seed attestation', () async {
      await case_.skip(actorId: _inviterId, subjectId: _inviteeId);

      final state = await writer.execute(r'''
SELECT state
FROM public.invite_seed_prompt_state
WHERE invitee_user_id = 'Ucapc4inv02'
''');
      expect(state.single[0], 2);

      final ledger = await writer.execute(r'''
SELECT 1
FROM public.person_capability_event
WHERE observer_user_id = 'Ucapc4inv01'
  AND subject_user_id = 'Ucapc4inv02'
  AND source_type = 4
  AND deleted_at IS NULL
''');
      expect(ledger, isEmpty);
    }, skip: skipReason);

    test('answered with zero tags still marks answered and clears ledger',
        () async {
      await case_.answer(
        actorId: _inviterId,
        subjectId: _inviteeId,
        slugs: const ['transport'],
      );
      await case_.answer(
        actorId: _inviterId,
        subjectId: _inviteeId,
        slugs: const [],
      );

      final rows = await writer.execute(r'''
SELECT tag_slug
FROM public.person_capability_event
WHERE observer_user_id = 'Ucapc4inv01'
  AND subject_user_id = 'Ucapc4inv02'
  AND source_type = 4
  AND deleted_at IS NULL
''');
      expect(rows, isEmpty);

      final prompt = await case_.promptStateFor(
        actorId: _inviterId,
        subjectId: _inviteeId,
      );
      expect(prompt.state, PromptStateValue.answered);
      expect(prompt.slugs, isEmpty);
    }, skip: skipReason);

    test('promptStateFor round-trips ledger slugs after answer', () async {
      await case_.answer(
        actorId: _inviterId,
        subjectId: _inviteeId,
        slugs: const ['transport'],
      );

      final prompt = await case_.promptStateFor(
        actorId: _inviterId,
        subjectId: _inviteeId,
      );
      expect(prompt.state, PromptStateValue.answered);
      expect(prompt.slugs, ['transport']);
    }, skip: skipReason);
  });
}

Future<void> _seedFixture(Connection writer, Env env) async {
  final inviterCreated = DateTime.utc(2026, 1, 1);
  final inviteeCreated = DateTime.utc(2026, 1, 2);
  for (final row in [
    (_inviterId, 'Inviter', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', inviterCreated),
    (_inviteeId, 'Invitee', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', inviteeCreated),
    (_otherId, 'Other', 'cccccccccccccccccccccccccccccccccccccccccccc', inviteeCreated),
  ]) {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @name, @pk, @at, @at)
ON CONFLICT (id) DO NOTHING
'''),
      parameters: {
        'id': row.$1,
        'name': row.$2,
        'pk': row.$3,
        'at': row.$4,
      },
    );
  }

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.invitation (id, user_id, addressee_name, created_at)
VALUES (@id, @userId, 'Invitee', @at)
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'id': _invitationId,
      'userId': _inviterId,
      'at': inviterCreated,
    },
  );

  final inviterKey = InviteGenealogyNodeKey.derive(userId: _inviterId, env: env);
  final inviteeKey = InviteGenealogyNodeKey.derive(userId: _inviteeId, env: env);
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.invite_genealogy (
  descendant_node_key,
  ancestor_node_key,
  descendant_user_id,
  ancestor_user_id,
  invitation_id,
  ancestor_user_created_at,
  descendant_user_created_at,
  created_at
) VALUES (
  @descKey,
  @ancKey,
  @descUser,
  @ancUser,
  @invitationId,
  @ancCreated,
  @descCreated,
  @descCreated
)
ON CONFLICT (descendant_node_key) DO NOTHING
'''),
    parameters: {
      'descKey': inviteeKey,
      'ancKey': inviterKey,
      'descUser': _inviteeId,
      'ancUser': _inviterId,
      'invitationId': _invitationId,
      'ancCreated': inviterCreated,
      'descCreated': inviteeCreated,
    },
  );

  await writer.execute(
    Sql.named(r'''
INSERT INTO public.invite_seed_prompt_state (
  inviter_user_id,
  invitee_user_id,
  state,
  updated_at
) VALUES (@inviter, @invitee, 0, @at)
ON CONFLICT (invitee_user_id) DO NOTHING
'''),
    parameters: {
      'inviter': _inviterId,
      'invitee': _inviteeId,
      'at': inviteeCreated,
    },
  );
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port = int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final databaseName = 'tentura_c4_${suffix}_test';
    final adminEnv = Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );
    final databaseEnv = Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgPassword: password,
      pgDatabase: databaseName,
      printEnv: false,
      isDebugModeOn: false,
    );
    return _DisposablePgTarget(
      adminEnv: adminEnv,
      databaseEnv: databaseEnv,
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
      await connection.execute('DROP DATABASE IF EXISTS $databaseName');
      await connection.execute('CREATE DATABASE $databaseName');
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
        '''
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$databaseName' AND pid <> pg_backend_pid()
''',
      );
      await connection.execute('DROP DATABASE IF EXISTS $databaseName');
    } finally {
      await connection.close();
    }
  }
}
