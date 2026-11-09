@Tags(['pg'])
library;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/mockito.dart' show Fake;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_lobby.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_lobby_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/fake_beacon_hierarchy_repository.dart';
import '../../../support/fake_user_block_repository.dart';

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakeImages extends Fake implements ImageRepositoryPort {}

class _FakeTasks extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakePolling extends Fake implements PollingRepositoryPort {}

class _FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {}

/// `BeaconLobbyAccess` end to end: the real GraphQL field, the real
/// [BeaconRoomCase] and a real Postgres policy (`questions_access_levels`),
/// for someone who sees a Request only through discoverability.
///
/// The viewer is mutually visible with the author (reciprocal trust) and the
/// Request is discoverable, published and open, but nobody sent it to them:
/// no forward edge, help offer or participant row. They may ask the author in
/// Questions like a recipient; once the Request is private they may not.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_LOBBY_DISCOVERABLE_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_lobby_discoverable_gql',
  );
  final skipReason = await pgSkipReason(target);

  const requestId = 'Blgqdisc0001';
  const author = 'Ulgqdauthor1';
  const viewer = 'Ulgqdviewer1';

  group('BeaconLobbyAccess for a discoverable viewer of a Request', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late GraphQL graphQL;

    Future<Map<String, dynamic>> access(String viewer) async {
      final data =
          await graphQL.parseAndExecute(
                'query { BeaconLobbyAccess(beaconId: "$requestId") '
                '{ beaconId canRead canPost readOnlyReason } }',
                globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
              )
              as Map<String, dynamic>;
      return data['BeaconLobbyAccess'] as Map<String, dynamic>;
    }

    Future<bool> canReadContent() async =>
        (await writer.execute(
              "SELECT public.beacon_can_read_content('$requestId', '$viewer')",
            )).single.single!
            as bool;

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = TenturaDb(target.databaseEnv);
      final rooms = BeaconRoomCase(
        BeaconRoomRepository(db),
        CoordinationItemRepository(db),
        _FakeFactCards(),
        _FakeImages(),
        _FakeTasks(),
        _FakeRemoteStorage(),
        _FakePolling(),
        _FakeUploadQuota(),
        FakeUserBlockRepository(),
        PassThroughMutatingUnitOfWork(),
        FakeBeaconHierarchyRepository(),
        const ProductionDiscussionProductPolicy(),
        lobby: BeaconLobbyRepository(db),
        env: Env(environment: Environment.test),
        logger: Logger('beacon_lobby_access_discoverable_viewer_pg_test'),
      );
      graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', 'Query root')
            ..fields.addAll(QueryBeaconLobby(beaconRoomCase: rooms).all),
        ),
      );
      await writer.execute(
        'INSERT INTO public."user" (id, display_name, handle, public_key) '
        'VALUES ${[
          for (final u in [author, viewer]) "('$u', '${u.substring(2, 8)}', '${u.substring(2, 8)}', 'k$u')",
        ].join(', ')}',
      );
      await writer.execute(
        'INSERT INTO public.vote_user (subject, object, amount) VALUES '
        "('$viewer', '$author', 1), ('$author', '$viewer', 1)",
      );
      await writer.execute(
        'INSERT INTO public.beacon (id, user_id, title, description, status, '
        'kind, is_discoverable, published_at, created_at, updated_at) VALUES '
        "('$requestId', '$author', 'Moving day', 'desc', 0, 0, true, "
        "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != null) return;
      await writer.execute(
        'UPDATE public.beacon SET is_discoverable = true, status = 0 '
        "WHERE id = '$requestId'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_help_offer WHERE beacon_id = '$requestId'",
      );
    });

    test(
      'may read and post in Questions of an open discoverable Request',
      () async {
        expect(await canReadContent(), isTrue, reason: 'fixture: discoverable');
        final probe = await access(viewer);
        expect(probe['beaconId'], requestId);
        expect(probe['canRead'], isTrue);
        expect(probe['canPost'], isTrue);
        expect(probe['readOnlyReason'], isNull);
      },
    );

    test('has no Questions once the Request is private and nobody sent it '
        'to them', () async {
      expect((await access(viewer))['canRead'], isTrue, reason: 'discoverable');
      await writer.execute(
        "UPDATE public.beacon SET is_discoverable = false WHERE id = '$requestId'",
      );
      expect(await canReadContent(), isFalse, reason: 'fixture: private');
      final probe = await access(viewer);
      expect(probe['canRead'], isFalse);
      expect(probe['canPost'], isFalse);
    });

    test('has no Questions once the Request is closed and the content wall '
        'hides it from them', () async {
      expect((await access(viewer))['canPost'], isTrue, reason: 'open');
      await writer.execute(
        "UPDATE public.beacon SET status = 6 WHERE id = '$requestId'",
      );
      expect(await canReadContent(), isFalse, reason: 'fixture: closed');
      final probe = await access(viewer);
      expect(probe['canRead'], isFalse);
      expect(probe['canPost'], isFalse);
    });

    test('reads but no longer posts after withdrawing a help offer', () async {
      expect((await access(viewer))['canPost'], isTrue, reason: 'no offer');
      await writer.execute(
        'INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, '
        "status, withdraw_reason) VALUES ('$requestId', '$viewer', "
        "'I can help', 1, 'busy')",
      );
      final probe = await access(viewer);
      expect(probe['canRead'], isTrue);
      expect(probe['canPost'], isFalse);
      expect(probe['readOnlyReason'], 'withdrew');
    });

    test('reads but no longer posts after the author declines their offer, '
        'and posts again after offering anew', () async {
      expect((await access(viewer))['canPost'], isTrue, reason: 'no offer');
      // Declined by the author: no withdraw reason of the viewer's own.
      await writer.execute(
        'INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, '
        "status) VALUES ('$requestId', '$viewer', 'I can help', 1)",
      );
      final declined = await access(viewer);
      expect(declined['canRead'], isTrue);
      expect(declined['canPost'], isFalse);
      expect(declined['readOnlyReason'], 'declined');
      await writer.execute(
        'UPDATE public.beacon_help_offer SET status = 0 '
        "WHERE beacon_id = '$requestId' AND user_id = '$viewer'",
      );
      final again = await access(viewer);
      expect(again['canPost'], isTrue);
      expect(again['readOnlyReason'], isNull);
    });
  }, skip: skipReason ?? false);
}
