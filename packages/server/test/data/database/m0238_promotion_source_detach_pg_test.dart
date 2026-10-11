@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_user_block_repository.dart';

/// m0238: a published promotion may outlive its source message (Arch §10.3).
///
/// Deleting the source sets `beacon_promotions.source_message_id` to NULL via
/// the existing `ON DELETE SET NULL` FK; the published row and the child's
/// parent link survive. A draft whose source is gone still cannot publish.
Future<void> main() async {
  group('m0238 upgrade path', () {
    final target = DisposablePgTarget.fromNamedEnvironment(
      envVarName: 'TENTURA_M0238_PROMOTION_SOURCE_PG_TEST_DB',
      defaultNamePrefix: 'tentura_test_m0238_promo',
    );
    late DisposablePgWriterSession session;
    String? pgSkip;

    Future<int> sourceCheckCount() async =>
        (await session.writer.execute('''
SELECT count(*)::int FROM pg_constraint
WHERE conrelid = 'public.beacon_promotions'::regclass
  AND conname = 'beacon_promotions_source_general_ck'
''')).single.single!
            as int;

    setUpAll(() async {
      pgSkip = await pgSkipReason(target);
      if (pgSkip != null) return;
      session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: '0237',
      );
    });

    tearDownAll(() async {
      if (pgSkip != null) return;
      await tearDownDisposablePgWriter(session: session);
    });

    test('migrating from 0237 drops the published-source check', () async {
      if (pgSkip != null) {
        markTestSkipped(pgSkip!);
        return;
      }
      expect(await sourceCheckCount(), 1);
      await migrateDbSchema(session.writer);
      expect(await sourceCheckCount(), 0);
    });
  });

  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for m0238 promotion PG test';

  group('promotion source detach — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconChildCreateCase case_;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment(
        databaseNameOverride:
            'tentura_test_m0238_case_${DateTime.timestamp().microsecondsSinceEpoch}',
      );
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      final room = BeaconRoomRepository(session.db);
      final context = BeaconRoomNotificationContextRepository(
        room,
        session.db,
        HelpOfferRepository(session.db),
        CommitmentRepository(session.db),
      );
      case_ = BeaconChildCreateCase(
        BeaconRepository(session.db),
        BeaconHierarchyRepository(session.db),
        BeaconHierarchyCommandRepository(session.db),
        BeaconAccessRepository(session.db),
        context,
        attentionIntents: AttentionIntentCase(
          context,
          UserRepository(
            Env(environment: Environment.test),
            session.db,
            _NoopInviteGenealogyRepository(),
            InviteSeedPromptRepositoryMock(),
          ),
          BeaconAccessRepository(session.db),
          FakeUserBlockRepository(),
        ),
        attention: TransactionalAttentionCase(
          MutatingUnitOfWork(session.db),
          AttentionDispatchRepository(session.db, Logger('m0238_pg')),
        ),
        env: Env(environment: Environment.test),
        logger: Logger('m0238_pg'),
      );
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      for (final table in [
        'attention_channel_delivery',
        'notification_outbox',
        'attention_occurrence_recipient',
      ]) {
        await writer.execute('''
DELETE FROM public.$table
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence
  WHERE source_event_key LIKE 'child_created%'
)''');
      }
      await writer.execute(
        "DELETE FROM public.attention_occurrence WHERE source_event_key LIKE 'child_created%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_promotions WHERE parent_beacon_id LIKE 'Bhier%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_child_commands WHERE client_command_id LIKE 'cmd-%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_room_message WHERE hierarchy_notice_identity LIKE 'child_created:%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE parent_beacon_id LIKE 'Bhier%'",
      );
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    Future<void> deleteSource() => writer.execute(
      Sql.named('DELETE FROM public.beacon_room_message WHERE id = @id'),
      parameters: {'id': BeaconHierarchyTopology.generalMessageOnA},
    );

    test(
      'deleting the source of a published child detaches the promotion',
      () async {
        await fixture.seedFullTopology();
        final draft = await case_.createChild(
          actorUserId: BeaconHierarchyTopology.aliceId,
          parentBeaconId: BeaconHierarchyTopology.beaconA,
          sourceMessageId: BeaconHierarchyTopology.generalMessageOnA,
          clientCommandId: 'cmd-m0238-published-01',
          title: 'Promoted child',
          description: '',
          draft: true,
        );
        await case_.publishDraft(
          actorUserId: BeaconHierarchyTopology.aliceId,
          childBeaconId: draft.beaconId!,
        );

        await deleteSource();

        final promotion = await writer.execute(
          Sql.named('''
SELECT source_message_id, published_at
FROM public.beacon_promotions WHERE child_beacon_id = @child'''),
          parameters: {'child': draft.beaconId},
        );
        expect(promotion.single[0], isNull);
        expect(promotion.single[1], isNotNull);

        final parent = await writer.execute(
          Sql.named(
            'SELECT parent_beacon_id FROM public.beacon WHERE id = @id',
          ),
          parameters: {'id': draft.beaconId},
        );
        expect(parent.single.single, BeaconHierarchyTopology.beaconA);
      },
      skip: skipReason,
    );

    test(
      'a draft whose source was deleted still cannot publish',
      () async {
        await fixture.seedFullTopology();
        final draft = await case_.createChild(
          actorUserId: BeaconHierarchyTopology.aliceId,
          parentBeaconId: BeaconHierarchyTopology.beaconA,
          sourceMessageId: BeaconHierarchyTopology.generalMessageOnA,
          clientCommandId: 'cmd-m0238-draft-01',
          title: 'Draft child',
          description: '',
          draft: true,
        );

        await deleteSource();

        final source = await writer.execute(
          Sql.named(
            'SELECT source_message_id FROM public.beacon_promotions '
            'WHERE child_beacon_id = @child',
          ),
          parameters: {'child': draft.beaconId},
        );
        expect(source.single.single, isNull);

        await expectLater(
          case_.publishDraft(
            actorUserId: BeaconHierarchyTopology.aliceId,
            childBeaconId: draft.beaconId!,
          ),
          throwsA(isA<BeaconPromotionSourceInvalidException>()),
        );
      },
      skip: skipReason,
    );
  });
}

final class _NoopInviteGenealogyRepository
    implements InviteGenealogyRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
