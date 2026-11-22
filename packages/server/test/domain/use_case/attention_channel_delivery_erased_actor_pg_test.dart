@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_channel_delivery_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/user_erasure_test_stack.dart';
import '../../support/mocks/invite_seed_prompt_repository_mock.dart';

/// Queued channel jobs must survive the erasure of the person who caused them:
/// the actor is scrubbed, but the job keeps its presentation identity, reaches
/// a final state and never holds up other accounts' jobs. Legacy jobs that an
/// older trigger rewrote without a presentation identity must not wedge the
/// worker either.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ERASED_ACTOR_DELIVERY_TEST_DB',
    defaultNamePrefix: 'tentura_test_erased_actor_delivery',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('channel jobs of an erased actor', () {
    late Connection writer;
    late TenturaDb database;
    late UserCase userCase;
    late AttentionDispatchRepository dispatch;
    late AttentionChannelDeliveryRepository deliveries;
    late MutatingUnitOfWork unitOfWork;
    late _RecordingChannels channels;
    late AttentionChannelDeliveryCase runner;

    setUpAll(() async {
      if (skipReason != false) return;
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      final logger = Logger('erased_actor_delivery_pg_test');
      dispatch = AttentionDispatchRepository(database, logger);
      deliveries = AttentionChannelDeliveryRepository(database);
      unitOfWork = MutatingUnitOfWork(database);
      final users = UserRepository(
        Env(environment: Environment.test),
        database,
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepositoryMock(),
      );
      final lifecycleEffects = BeaconLifecycleEffectsCase(
        BeaconHierarchyOutboxRepository(database),
        env: Env(environment: Environment.test),
        logger: logger,
      );
      final stack = buildUserErasureTestStack(
        db: database,
        userRepository: users,
        lifecycleEffects: lifecycleEffects,
        attention: TransactionalAttentionCase(unitOfWork, dispatch),
        logger: logger,
      );
      userCase = stack.userCase;
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await database.close();
      await writer.close();
      await target.drop();
    });

    setUp(() async {
      if (skipReason != false) return;
      await writer.execute('DELETE FROM public.attention_channel_throttle');
      await writer.execute('DELETE FROM public.attention_channel_delivery');
      channels = _RecordingChannels();
      runner = AttentionChannelDeliveryCase(deliveries, channels);
    });

    Future<void> user(String id, String name) => writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @name, @key) ON CONFLICT (id) DO NOTHING',
      ),
      parameters: {'id': id, 'name': name, 'key': 'key-$id'},
    );

    Future<void> relay({
      required String actorId,
      required String actorName,
      required String targetId,
      required String sourceKey,
    }) => unitOfWork.run(
      actorUserId: actorId,
      action: () => dispatch.record(
        AttentionDispatchIntent(
          eventType: AttentionEventType.relayReceived,
          sourceEventKey: sourceKey,
          actorUserId: actorId,
          priority: NotificationPriority.normal,
          kind: NotificationKind.newRelay,
          title: '$actorName forwarded a Request',
          body: '$actorName shared a private request',
          actionUrl: '/#/view?id=B$sourceKey',
          collapseKey: sourceKey,
          recipients: [
            AttentionRecipientSnapshot(
              recipientId: targetId,
              reasons: const {AttentionRecipientReason.forwardRecipient},
              role: AttentionRecipientRoleFacts(
                canReadBeaconContent: true,
                beaconId: 'B$sourceKey',
                actorUserId: actorId,
              ),
            ),
          ],
          beaconId: 'B$sourceKey',
        ),
      ),
    );

    Future<Map<String, Object?>> jobFor(String accountId) async {
      final rows = await writer.execute(
        Sql.named('''
SELECT status, dead_lettered_at IS NOT NULL, payload::text,
       payload -> 'presentationKey', payload -> 'presentationPayload',
       coalesce(last_error, '')
FROM public.attention_channel_delivery WHERE account_id = @a
'''),
        parameters: {'a': accountId},
      );
      expect(rows, hasLength(1));
      final r = rows.single;
      return {
        'status': r[0],
        'deadLettered': r[1],
        'text': r[2],
        'key': r[3],
        'facts': r[4],
        'lastError': r[5],
      };
    }

    /// Time past every lease, so due and expired-lease jobs are both claimable.
    DateTime later() => DateTime.timestamp().toUtc().add(
      const Duration(hours: 1),
    );

    /// Leases every due job, as the worker did before the actor was erased.
    Future<void> leaseAll(int expected) async {
      final claimed = await deliveries.claimDue(
        workerId: 'w-before-erasure',
        now: DateTime.timestamp().toUtc(),
        limit: 10,
      );
      expect(claimed, hasLength(expected));
    }

    void expectFinal(Map<String, Object?> job) {
      final status = job['status'];
      expect(
        status == 'delivered' ||
            (status == 'dead' && job['deadLettered'] == true),
        isTrue,
        reason: 'job must end delivered or dead-lettered, was $status',
      );
    }

    test(
      'anonymize trigger keeps presentation key and payload in its body',
      () async {
        final rows = await writer.execute(
          'SELECT pg_get_functiondef( '
          "'public.attention_anonymize_deleted_actor()'::regprocedure)",
        );
        final body = rows.single.single! as String;
        expect(body, contains('presentationKey'));
        expect(body, contains('presentationPayload'));
      },
    );

    test(
      'queued job keeps its presentation identity and loses the actor',
      () async {
        await user('Uerasea1', 'Erasable Ann');
        await user('Ztgtone', 'Target one');
        await relay(
          actorId: 'Uerasea1',
          actorName: 'Erasable Ann',
          targetId: 'Ztgtone',
          sourceKey: 'erase-keep-1',
        );
        await leaseAll(1);
        await writer.execute(
          Sql.named(
            'UPDATE public.attention_channel_delivery '
            'SET last_error = @e WHERE account_id = @a',
          ),
          parameters: {
            'e': 'Erasable Ann (Uerasea1) delivery failed',
            'a': 'Ztgtone',
          },
        );
        final before = await jobFor('Ztgtone');
        expect(before['key'], isA<String>());

        expect(await userCase.deleteById(id: 'Uerasea1'), isTrue);

        final after = await jobFor('Ztgtone');
        expect(after['key'], before['key']);
        final payload =
            jsonDecode(after['text']! as String) as Map<String, dynamic>;
        expect(payload['presentationKey'], before['key']);
        expect(payload['presentationPayload'], isA<Map<String, dynamic>>());
        for (final text in [
          after['text']! as String,
          after['lastError']! as String,
        ]) {
          expect(text, isNot(contains('Uerasea1')));
          expect(text, isNot(contains('Erasable Ann')));
        }
      },
    );

    test(
      'erased actor job ends final and does not block other accounts',
      () async {
        await user('Uerasea2', 'Erasable Bo');
        await user('Uerasea2t', 'Erasea2 target');
        await user('Uerasea2k', 'Surviving actor');
        await user('Uerasea2kt', 'Erasea2 other target');
        await relay(
          actorId: 'Uerasea2',
          actorName: 'Erasable Bo',
          targetId: 'Uerasea2t',
          sourceKey: 'erase-batch-1',
        );
        await relay(
          actorId: 'Uerasea2k',
          actorName: 'Surviving actor',
          targetId: 'Uerasea2kt',
          sourceKey: 'erase-batch-2',
        );
        // One claimDue batch holds the erased actor's job and the valid one.
        await leaseAll(2);
        expect(await userCase.deleteById(id: 'Uerasea2'), isTrue);

        await runner.runDue(workerId: 'w-erased', now: later());

        expectFinal(await jobFor('Uerasea2t'));
        expect((await jobFor('Uerasea2kt'))['status'], 'delivered');
      },
    );

    test('job rewritten without presentation identity neither throws nor '
        'blocks a valid job', () async {
      await user('Uerasea3', 'Legacy actor');
      await user('Uerasea3t', 'Erasea3 legacy target');
      await user('Uerasea3k', 'Surviving actor 3');
      await user('Uerasea3kt', 'Erasea3 valid target');
      await relay(
        actorId: 'Uerasea3',
        actorName: 'Legacy actor',
        targetId: 'Uerasea3t',
        sourceKey: 'erase-legacy-1',
      );
      await relay(
        actorId: 'Uerasea3k',
        actorName: 'Surviving actor 3',
        targetId: 'Uerasea3kt',
        sourceKey: 'erase-legacy-2',
      );
      // The shape the old trigger left behind: still pending, never leased.
      await writer.execute(
        Sql.named('''
UPDATE public.attention_channel_delivery
SET payload = (payload - 'presentationKey') - 'presentationPayload'
WHERE account_id = @a
'''),
        parameters: {'a': 'Uerasea3t'},
      );

      // The claim itself must cope with the legacy row...
      await expectLater(
        deliveries.claimDue(
          workerId: 'w-legacy-claim',
          now: later(),
          limit: 10,
        ),
        completes,
      );
      // ...and a full run must leave nothing wedged.
      await expectLater(
        runner.runDue(
          workerId: 'w-legacy',
          now: later().add(const Duration(hours: 1)),
        ),
        completes,
      );

      expect((await jobFor('Uerasea3kt'))['status'], 'delivered');
      expectFinal(await jobFor('Uerasea3t'));
    });
  }, skip: skipReason);
}

final class _RecordingChannels implements BeaconNotificationPort {
  final handedOff = <AttentionChannelDecision>[];

  @override
  Future<void> handOffChannels(List<AttentionChannelDecision> decisions) async {
    handedOff.addAll(decisions);
  }
}

class _NoopInviteGenealogyRepository implements InviteGenealogyRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
