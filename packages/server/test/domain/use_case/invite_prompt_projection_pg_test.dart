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
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/domain/use_case/invite_seed_attestation_case.dart';
import 'package:tentura_server/env.dart';

const _inviterId = 'Uprj10inv01';
const _inviteeId = 'Uprj10inv02';
const _otherId = 'Uprj10oth01';
const _unknownId = 'Uprj10unk99';
const _invitationId = 'Iprj10inv001';
const _receiptId = 'Nprj10rcpt1';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('InviteSeedAttestationCase promptStatesFor', () {
    late Connection writer;
    late TenturaDb database;
    late InviteSeedAttestationCase case_;
    late AttentionRepository attention;
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
      final blockRepo = UserBlockRepository(env, database);
      final genealogyRepo = InviteGenealogyRepository(
        env,
        database,
        blockRepo,
      );
      final promptRepo = InviteSeedPromptRepository(database);
      case_ = InviteSeedAttestationCase(
        promptRepo,
        genealogyRepo,
        CapabilityEvidenceRepository(database),
        blockRepo,
        MutatingUnitOfWork(database),
        env: env,
        logger: Logger('InvitePromptProjectionPgTest'),
      );
      attention = AttentionRepository(database);
    });

    setUp(() async {
      await writer.execute(r'''
DELETE FROM public.notification_outbox
WHERE account_id LIKE 'Uprj10%'
''');
      await writer.execute(r'''
DELETE FROM public.user_block
WHERE blocker_id LIKE 'Uprj10%' OR blocked_id LIKE 'Uprj10%'
''');
      await writer.execute(r'''
DELETE FROM public.person_capability_event
WHERE observer_user_id LIKE 'Uprj10%'
   OR subject_user_id LIKE 'Uprj10%'
''');
      await writer.execute(r'''
DELETE FROM public.invite_seed_prompt_state
WHERE inviter_user_id LIKE 'Uprj10%'
   OR invitee_user_id LIKE 'Uprj10%'
''');
      await writer.execute(r'''
DELETE FROM public.invite_genealogy
WHERE invitation_id = 'Iprj10inv001'
''');
      await writer.execute(r'''
DELETE FROM public.invitation
WHERE id = 'Iprj10inv001'
''');
      await writer.execute(r'''
DELETE FROM public."user"
WHERE id LIKE 'Uprj10%'
''');
      await _seedFixture(writer, env);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test('batch returns states for authorized subjects only', () async {
      final states = await case_.promptStatesFor(
        actorId: _inviterId,
        subjectIds: [_inviteeId, _otherId, _unknownId],
      );

      expect(states.length, 1);
      expect(states.single.inviteeUserId, _inviteeId);
      expect(states.single.state, PromptStateValue.pending);
    }, skip: skipReason);

    test('unknown subject is absent, not an error', () async {
      final states = await case_.promptStatesFor(
        actorId: _inviterId,
        subjectIds: [_unknownId],
      );
      expect(states, isEmpty);
    }, skip: skipReason);

    test(
      'blocked pair yields no prompt state while profile receipt stays readable',
      () async {
        await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_inviterId', '$_inviteeId', '$_inviteeId')
ON CONFLICT DO NOTHING
''');
        await _insertProfileInviteAcceptedReceipt(writer);

        final states = await case_.promptStatesFor(
          actorId: _inviterId,
          subjectIds: [_inviteeId],
        );
        expect(states, isEmpty);

        await expectLater(
          case_.promptStateFor(actorId: _inviterId, subjectId: _inviteeId),
          throwsA(isA<UnauthorizedException>()),
        );

        final feed = await attention.attentionFeed(
          accountId: _inviterId,
          view: AttentionFeedView.all,
          limit: 50,
        );
        expect(
          feed.page.items.map((item) => item.id),
          contains(_receiptId),
        );
      },
      skip: skipReason,
    );
  });
}

Future<void> _insertProfileInviteAcceptedReceipt(Connection writer) =>
    writer.execute(
      Sql.named(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  source_event_key,
  destination_kind, target_entity_id,
  presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Invite accepted', 'Fixture body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @sourceEventKey,
  'profile', @targetEntityId,
  'invite_accepted', CAST(@payload AS jsonb),
  'standard', 'profile'
)
'''),
      parameters: {
        'id': _receiptId,
        'accountId': _inviterId,
        'dedupKey': 'dedup-$_receiptId',
        'createdAt': '2026-07-16T12:00:00Z',
        'sourceEventKey': 'source-$_receiptId',
        'targetEntityId': _inviteeId,
        'payload': '{"eventType":"fixture"}',
      },
    );

Future<void> _seedFixture(Connection writer, Env env) async {
  final inviterCreated = DateTime.utc(2026, 1, 1);
  final inviteeCreated = DateTime.utc(2026, 1, 2);
  for (final row in [
    (
      _inviterId,
      'Inviter',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      inviterCreated,
    ),
    (
      _inviteeId,
      'Invitee',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      inviteeCreated,
    ),
    (
      _otherId,
      'Other',
      'cccccccccccccccccccccccccccccccccccccccccccc',
      inviteeCreated,
    ),
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

  final inviterKey =
      InviteGenealogyNodeKey.derive(userId: _inviterId, env: env);
  final inviteeKey =
      InviteGenealogyNodeKey.derive(userId: _inviteeId, env: env);
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
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final databaseName = 'tentura_prj10_${suffix}_test';
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
