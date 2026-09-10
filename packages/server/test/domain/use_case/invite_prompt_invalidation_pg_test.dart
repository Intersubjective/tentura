@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
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
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/domain/use_case/invite_seed_attestation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_user_block_repository.dart';

const _inviterId = 'Uinv11inv01';
const _inviteeId = 'Uinv11inv02';
const _invitationId = 'Iinv11inv001';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('InviteSeedAttestationCase prompt invalidation', () {
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    late TenturaDb database;
    late InviteSeedAttestationCase case_;
    late Env env;
    final notifications = <Map<String, dynamic>>[];

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
        logger: Logger('InvitePromptInvalidationPgTest'),
      );

      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) => notifications.add(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      );
      await _settle();
      notifications.clear();
    });

    setUp(() async {
      await writer.execute(r'''
DELETE FROM public.person_capability_event
WHERE observer_user_id LIKE 'Uinv11%'
   OR subject_user_id LIKE 'Uinv11%'
''');
      await writer.execute(r'''
DELETE FROM public.invite_seed_prompt_state
WHERE inviter_user_id LIKE 'Uinv11%'
   OR invitee_user_id LIKE 'Uinv11%'
''');
      await writer.execute(r'''
DELETE FROM public.invite_genealogy
WHERE invitation_id = 'Iinv11inv001'
''');
      await writer.execute(r'''
DELETE FROM public.invitation
WHERE id = 'Iinv11inv001'
''');
      await writer.execute(r'''
DELETE FROM public."user"
WHERE id LIKE 'Uinv11%'
''');
      await _seedFixture(writer, env);
      notifications.clear();
    });

    tearDownAll(() async {
      await notificationSubscription.cancel();
      await listener.close();
      await database.close();
      await writer.close();
      await target.drop();
    });

    test('rolled-back update leaves state and notifications unchanged', () async {
      await writer.execute('BEGIN');
      await writer.execute(
        r"SELECT set_config('tentura.mutating_user_id', 'Uinv11inv01', true)",
      );
      await writer.execute(r'''
UPDATE public.invite_seed_prompt_state
SET state = 2, updated_at = now()
WHERE invitee_user_id = 'Uinv11inv02'
''');
      await _settle();
      expect(_promptInvalidations(notifications), isEmpty);

      await writer.execute('ROLLBACK');

      final state = await writer.execute(r'''
SELECT state
FROM public.invite_seed_prompt_state
WHERE invitee_user_id = 'Uinv11inv02'
''');
      expect(state.single[0], 0);
      expect(_promptInvalidations(notifications), isEmpty);
    }, skip: skipReason);

    test('injected notification failure rolls the prompt write back', () async {
      await _injectNotificationFailure(writer);
      try {
        await expectLater(
          case_.skip(actorId: _inviterId, subjectId: _inviteeId),
          throwsA(isA<Exception>()),
        );

        final state = await writer.execute(r'''
SELECT state
FROM public.invite_seed_prompt_state
WHERE invitee_user_id = 'Uinv11inv02'
''');
        expect(state.single[0], 0);
        expect(_promptInvalidations(notifications), isEmpty);
      } finally {
        await _restoreStrictEmit(writer);
      }
    }, skip: skipReason);

    test('committed skip is observable on a second client via notification',
        () async {
      await case_.skip(actorId: _inviterId, subjectId: _inviteeId);

      await _waitUntil(() => _promptInvalidations(notifications).isNotEmpty);
      expect(_promptInvalidations(notifications), [
        {
          'event': 'update',
          'entity': 'invite_seed_prompt',
          'id': _inviteeId,
          'user_ids': [_inviterId],
          'actor_user_id': _inviterId,
        },
      ]);

      final states = await case_.promptStatesFor(
        actorId: _inviterId,
        subjectIds: [_inviteeId],
      );
      expect(states, hasLength(1));
      expect(states.single.state, PromptStateValue.skipped);
    }, skip: skipReason);

    test('committed answer is observable on a second client via notification',
        () async {
      await case_.answer(
        actorId: _inviterId,
        subjectId: _inviteeId,
        slugs: const ['transport'],
      );

      await _waitUntil(() => _promptInvalidations(notifications).isNotEmpty);
      expect(_promptInvalidations(notifications), [
        {
          'event': 'update',
          'entity': 'invite_seed_prompt',
          'id': _inviteeId,
          'user_ids': [_inviterId],
          'actor_user_id': _inviterId,
        },
      ]);

      final states = await case_.promptStatesFor(
        actorId: _inviterId,
        subjectIds: [_inviteeId],
      );
      expect(states, hasLength(1));
      expect(states.single.state, PromptStateValue.answered);
    }, skip: skipReason);
  });
}

List<Map<String, dynamic>> _promptInvalidations(
  List<Map<String, dynamic>> notifications,
) => notifications
    .where(
      (message) =>
          message['entity'] == 'invite_seed_prompt' &&
          message['event'] == 'update',
    )
    .toList();

Future<void> _injectNotificationFailure(Connection writer) async {
  await writer.execute(r'''
CREATE OR REPLACE FUNCTION public.emit_realtime_entity_change_strict(
  p_entity text,
  p_id text,
  p_event text,
  p_user_ids text[],
  p_extra jsonb DEFAULT '{}'::jsonb
) RETURNS void
  LANGUAGE plpgsql
  AS $$
BEGIN
  RAISE EXCEPTION 'injected notification failure for test';
END;
$$;
''');
}

Future<void> _restoreStrictEmit(Connection writer) async {
  await writer.execute(r'''
CREATE OR REPLACE FUNCTION public.emit_realtime_entity_change_strict(
  p_entity text,
  p_id text,
  p_event text,
  p_user_ids text[],
  p_extra jsonb DEFAULT '{}'::jsonb
) RETURNS void
  LANGUAGE plpgsql
  AS $$
DECLARE
  normalized_user_ids text[];
  actor_user_id text;
  recipient_index integer := 1;
  recipient_count integer;
  take_count integer;
  recipient_chunk text[];
  payload text;
BEGIN
  IF p_entity IS NULL OR p_entity = ''
     OR p_id IS NULL OR p_id = ''
     OR p_event NOT IN ('insert', 'update', 'delete') THEN
    RAISE EXCEPTION
      'emit_realtime_entity_change_strict: invalid envelope for kind %',
      COALESCE(p_entity, '<null>');
  END IF;

  SELECT COALESCE(array_agg(DISTINCT user_id ORDER BY user_id), ARRAY[]::text[])
  INTO normalized_user_ids
  FROM unnest(COALESCE(p_user_ids, ARRAY[]::text[])) AS user_id
  WHERE user_id IS NOT NULL AND user_id <> '';

  IF cardinality(normalized_user_ids) = 0 THEN
    RAISE EXCEPTION
      'emit_realtime_entity_change_strict: empty recipients for kind %',
      p_entity;
  END IF;

  actor_user_id := NULLIF(
    current_setting('tentura.mutating_user_id', true),
    ''
  );
  recipient_count := cardinality(normalized_user_ids);

  WHILE recipient_index <= recipient_count LOOP
    take_count := LEAST(100, recipient_count - recipient_index + 1);

    LOOP
      recipient_chunk := normalized_user_ids[
        recipient_index:recipient_index + take_count - 1
      ];
      payload := jsonb_strip_nulls(
        jsonb_build_object(
          'event', p_event,
          'entity', p_entity,
          'id', p_id,
          'user_ids', to_jsonb(recipient_chunk),
          'actor_user_id', actor_user_id
        ) || COALESCE(p_extra, '{}'::jsonb)
      )::text;

      EXIT WHEN octet_length(payload) < 7900;
      IF take_count = 1 THEN
        RAISE EXCEPTION
          'emit_realtime_entity_change_strict: payload exceeded byte budget for kind %',
          p_entity;
      END IF;
      take_count := GREATEST(1, take_count / 2);
    END LOOP;

    PERFORM pg_notify('entity_changes', payload);
    recipient_index := recipient_index + take_count;
  END LOOP;
END;
$$;
''');
}

Future<void> _seedFixture(Connection writer, Env env) async {
  final inviterCreated = DateTime.utc(2026, 3, 1);
  final inviteeCreated = DateTime.utc(2026, 3, 2);
  for (final row in [
    (_inviterId, 'Inviter 11', 'inv11-inviter-pk', inviterCreated),
    (_inviteeId, 'Invitee 11', 'inv11-invitee-pk', inviteeCreated),
  ]) {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at)
VALUES (@id, @name, @pk, @at)
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

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

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
    final databaseName = 'tentura_inv11_${suffix}_test';
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
