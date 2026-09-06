@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_beacon_hierarchy.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_hierarchy.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../support/beacon_hierarchy_fixture.dart';
import '../support/fake_user_block_repository.dart';
import '../data/repository/beacon_hierarchy_pg_helpers.dart';

final class _NoopTrustEvidenceRepository implements TrustEvidenceRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _NoopInviteGenealogyRepository
    implements InviteGenealogyRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// GraphQL resolver-level contract test for the V2 hierarchy surface (plan
/// §3.5, Task 10). Invokes the real `QueryBeaconHierarchy`/
/// `MutationBeaconHierarchy` resolvers directly (same construction as their
/// registration in `_queries_all.dart`/`_mutations_all.dart`) against real
/// ports backed by a disposable Postgres database — real V2, real auth
/// (`kGlobalInputQueryJwt`), no Hasura involved, matching the acceptance
/// criterion "execute each operation over direct V2 with user auth".
Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon hierarchy contract test';

  group('beacon hierarchy GraphQL contract — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late QueryBeaconHierarchy query;
    late MutationBeaconHierarchy mutation;

    Map<String, dynamic> authAs(String userId) => {
      kGlobalInputQueryJwt: JwtEntity(sub: userId),
    };

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);

      final beacons = BeaconRepository(session.db);
      final commands = BeaconHierarchyCommandRepository(session.db);
      final hierarchy = BeaconHierarchyRepository(session.db);
      final room = BeaconRoomRepository(session.db);
      final dispatchRepo = AttentionDispatchRepository(
        session.db,
        Logger('beacon_hierarchy_contract_test'),
      );
      final unitOfWork = MutatingUnitOfWork(session.db);
      final attentionIntents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          session.db,
          HelpOfferRepository(session.db),
          CommitmentRepository(session.db),
        ),
        UserRepository(
          Env(environment: Environment.test),
          session.db,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(session.db),
        FakeUserBlockRepository(),
      );
      final childCreateCase = BeaconChildCreateCase(
        beacons,
        hierarchy,
        commands,
        BeaconAccessRepository(session.db),
        BeaconRoomNotificationContextRepository(
          room,
          session.db,
          HelpOfferRepository(session.db),
          CommitmentRepository(session.db),
        ),
        attentionIntents: attentionIntents,
        attention: TransactionalAttentionCase(unitOfWork, dispatchRepo),
        env: Env(environment: Environment.test),
        logger: Logger('beacon_hierarchy_contract_test'),
      );

      query = QueryBeaconHierarchy(hierarchyRepository: hierarchy);
      mutation = MutationBeaconHierarchy(childCreatePort: childCreateCase);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.attention_channel_delivery WHERE occurrence_id IN "
        "(SELECT id FROM public.attention_occurrence WHERE source_event_key LIKE 'child_created%')",
      );
      await writer.execute(
        "DELETE FROM public.notification_outbox WHERE occurrence_id IN "
        "(SELECT id FROM public.attention_occurrence WHERE source_event_key LIKE 'child_created%')",
      );
      await writer.execute(
        "DELETE FROM public.attention_occurrence_recipient WHERE occurrence_id IN "
        "(SELECT id FROM public.attention_occurrence WHERE source_event_key LIKE 'child_created%')",
      );
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
      // Remove any child beacon these tests created dynamically under the
      // fixture's own topology beacons, before fixture.tearDown() deletes
      // the topology itself (their beacon.parent_beacon_id FK would
      // otherwise block it).
      await writer.execute(
        Sql.named('''
DELETE FROM public.beacon
WHERE parent_beacon_id = ANY(@topologyIds)
  AND NOT (id = ANY(@topologyIds))
'''),
        parameters: {'topologyIds': BeaconHierarchyTopology.allBeaconIds},
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

    test('beaconHierarchyCapabilities: admitted viewer can list and create', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final field = query.all.singleWhere(
        (f) => f.name == 'beaconHierarchyCapabilities',
      );
      final result = await field.resolve!(null, {
        ...authAs(BeaconHierarchyTopology.aliceId),
        'beaconId': BeaconHierarchyTopology.beaconA,
      }) as Map<String, dynamic>;

      expect(result['canListChildren'], isTrue);
      expect(result['canCreateChild'], isTrue);
      expect(result['denialCode'], isNull);
    }, skip: skipReason);

    test(
      'beaconHierarchyCapabilities: non-admitted viewer is denied with notAdmitted',
      () async {
        await fixture.seedFullTopology();
        await seedPublishedHierarchyTree(writer);

        final field = query.all.singleWhere(
          (f) => f.name == 'beaconHierarchyCapabilities',
        );
        final result = await field.resolve!(null, {
          ...authAs(BeaconHierarchyTopology.eveId),
          'beaconId': BeaconHierarchyTopology.beaconA,
        }) as Map<String, dynamic>;

        expect(result['canListChildren'], isFalse);
        expect(result['canCreateChild'], isFalse);
        expect(result['denialCode'], 'notAdmitted');
      },
      skip: skipReason,
    );

    test('beaconChildren: paginates across a page boundary within a group', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final field = query.all.singleWhere((f) => f.name == 'beaconChildren');
      final firstPage = await field.resolve!(null, {
        ...authAs(BeaconHierarchyTopology.aliceId),
        'parentBeaconId': BeaconHierarchyTopology.beaconA,
        'group': 'active',
        'first': 1,
      }) as Map<String, dynamic>;

      final firstSummaries = firstPage['summaries'] as List;
      expect(firstSummaries, hasLength(1));
      final cursor = firstPage['nextCursor'] as String?;
      expect(cursor, isNotNull);

      final secondPage = await field.resolve!(null, {
        ...authAs(BeaconHierarchyTopology.aliceId),
        'parentBeaconId': BeaconHierarchyTopology.beaconA,
        'group': 'active',
        'first': 1,
        'after': cursor,
      }) as Map<String, dynamic>;
      final secondSummaries = secondPage['summaries'] as List;
      expect(secondSummaries, hasLength(1));
      expect(
        (secondSummaries.first as Map)['beaconId'],
        isNot((firstSummaries.first as Map)['beaconId']),
      );
    }, skip: skipReason);

    test('beaconChildren: a tampered cursor is rejected', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final field = query.all.singleWhere((f) => f.name == 'beaconChildren');
      await expectLater(
        field.resolve!(null, {
          ...authAs(BeaconHierarchyTopology.aliceId),
          'parentBeaconId': BeaconHierarchyTopology.beaconA,
          'group': 'active',
          'first': 20,
          'after': 'not-a-real-cursor',
        }),
        throwsA(isA<BeaconHierarchyCursorInvalidException>()),
      );
    }, skip: skipReason);

    test('beaconParentReference: unauthorized viewer gets an unavailable reference', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final field = query.all.singleWhere(
        (f) => f.name == 'beaconParentReference',
      );
      final result = await field.resolve!(null, {
        ...authAs(BeaconHierarchyTopology.eveId),
        'beaconId': BeaconHierarchyTopology.beaconB,
      }) as Map<String, dynamic>;

      expect(result['state'], 'unavailable');
      expect(result['beaconId'], isNull);
    }, skip: skipReason);

    test('beaconParentReference: admitted viewer sees the parent link', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      // Alice is admitted to beaconA; the one-edge grant requires admission
      // to the PARENT (A), not the child (B) whose reference is requested.
      final field = query.all.singleWhere(
        (f) => f.name == 'beaconParentReference',
      );
      final result = await field.resolve!(null, {
        ...authAs(BeaconHierarchyTopology.aliceId),
        'beaconId': BeaconHierarchyTopology.beaconB,
      }) as Map<String, dynamic>;

      expect(result['state'], 'available');
      expect(result['beaconId'], BeaconHierarchyTopology.beaconA);
    }, skip: skipReason);

    test('beaconPromotionSource: an unknown source message is rejected', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final field = query.all.singleWhere(
        (f) => f.name == 'beaconPromotionSource',
      );
      await expectLater(
        field.resolve!(null, {
          ...authAs(BeaconHierarchyTopology.aliceId),
          'parentBeaconId': BeaconHierarchyTopology.beaconA,
          'sourceMessageId': 'Rdoesnotexist',
        }),
        throwsA(isA<IdNotFoundException>()),
      );
    }, skip: skipReason);

    test('beaconChildCreate: happy path creates a child of an admitted parent', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final field = mutation.all.singleWhere(
        (f) => f.name == 'beaconChildCreate',
      );
      final result = await field.resolve!(null, {
        ...authAs(BeaconHierarchyTopology.aliceId),
        'parentBeaconId': BeaconHierarchyTopology.beaconA,
        'clientCommandId': 'cmd-happy-path-1',
        'title': 'Need a ladder',
        'description': 'Looking for a tall ladder to reach the gutter.',
      }) as Map<String, dynamic>;

      expect(result['outcome'], 'created');
      expect(result['beaconId'], isNotNull);
      expect((result['beacon'] as Map?)?['id'], result['beaconId']);
    }, skip: skipReason);

    test(
      'beaconChildCreate: a non-admitted actor is rejected with BEACON_CHILD_CREATE_FORBIDDEN',
      () async {
        await fixture.seedFullTopology();
        await seedPublishedHierarchyTree(writer);

        final field = mutation.all.singleWhere(
          (f) => f.name == 'beaconChildCreate',
        );
        await expectLater(
          field.resolve!(null, {
            ...authAs(BeaconHierarchyTopology.eveId),
            'parentBeaconId': BeaconHierarchyTopology.beaconA,
            'clientCommandId': 'cmd-forbidden-1',
            'title': 'Should not be created',
            'description': 'Should not be created either.',
          }),
          throwsA(isA<BeaconChildCreateForbiddenException>()),
        );
      },
      skip: skipReason,
    );

    test(
      'beaconChildCreate: a terminal parent is rejected with BEACON_PARENT_NOT_COORDINATABLE',
      () async {
        await fixture.seedFullTopology();
        await seedPublishedHierarchyTree(writer);
        await writer.execute(
          Sql.named(
            'UPDATE public.beacon SET status = @status WHERE id = @id',
          ),
          parameters: {
            'status': BeaconStatus.closed.smallintValue,
            'id': BeaconHierarchyTopology.beaconA,
          },
        );

        final field = mutation.all.singleWhere(
          (f) => f.name == 'beaconChildCreate',
        );
        await expectLater(
          field.resolve!(null, {
            ...authAs(BeaconHierarchyTopology.aliceId),
            'parentBeaconId': BeaconHierarchyTopology.beaconA,
            'clientCommandId': 'cmd-terminal-1',
            'title': 'Should not be created',
            'description': 'Should not be created either.',
          }),
          throwsA(isA<BeaconParentNotCoordinatableException>()),
        );
      },
      skip: skipReason,
    );

    test(
      'beaconChildCreate: reusing a clientCommandId with different input conflicts',
      () async {
        await fixture.seedFullTopology();
        await seedPublishedHierarchyTree(writer);

        final field = mutation.all.singleWhere(
          (f) => f.name == 'beaconChildCreate',
        );
        await field.resolve!(null, {
          ...authAs(BeaconHierarchyTopology.aliceId),
          'parentBeaconId': BeaconHierarchyTopology.beaconA,
          'clientCommandId': 'cmd-conflict-1',
          'title': 'First title',
          'description': 'First description.',
        });
        await expectLater(
          field.resolve!(null, {
            ...authAs(BeaconHierarchyTopology.aliceId),
            'parentBeaconId': BeaconHierarchyTopology.beaconA,
            'clientCommandId': 'cmd-conflict-1',
            'title': 'A different title',
            'description': 'First description.',
          }),
          throwsA(isA<BeaconChildCommandConflictException>()),
        );
      },
      skip: skipReason,
    );
  });
}
