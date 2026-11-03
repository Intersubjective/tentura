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
/// for a Request budded from a Post.
///
/// A member of the parent Post reads the budded Request through the bud
/// snapshot (`beacon_bud_observer`) even when nobody ticked them under "Who to
/// invite"; the entry row on the Request must offer them Questions.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_LOBBY_BUDDED_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_lobby_budded_gql',
  );
  final skipReason = await pgSkipReason(target);

  const postId = 'Blgqpost0001';
  const buddedId = 'Blgqbudded01';
  const author = 'Ulgqauthor01';
  const postMember = 'Ulgqpostmem1';
  const stranger = 'Ulgqstrange01';

  group('BeaconLobbyAccess for a Request budded from a Post', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late GraphQL graphQL;

    Future<Map<String, dynamic>> access(String viewer) async {
      final data =
          await graphQL.parseAndExecute(
                'query { BeaconLobbyAccess(beaconId: "$buddedId") '
                '{ beaconId canRead canPost readOnlyReason } }',
                globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
              )
              as Map<String, dynamic>;
      return data['BeaconLobbyAccess'] as Map<String, dynamic>;
    }

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
        logger: Logger('beacon_lobby_access_budded_post_member_pg_test'),
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
          for (final u in [author, postMember, stranger]) "('$u', '${u.substring(2, 8)}', '${u.substring(2, 8)}', 'k$u')",
        ].join(', ')}',
      );
      await writer.execute(
        'INSERT INTO public.beacon (id, user_id, title, description, status, '
        'kind, is_discoverable, parent_beacon_id, published_at, created_at, '
        'updated_at) VALUES '
        "('$postId', '$author', '', '', 0, 1, false, NULL, "
        "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z'), "
        "('$buddedId', '$author', 'Budded move', 'desc', 0, 0, false, "
        "'$postId', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
      // The bud snapshot: the Post author and the Post member, who was not
      // ticked under "Who to invite" (no forward edge, offer or participant).
      await writer.execute(
        'INSERT INTO public.beacon_bud_observer (beacon_id, user_id) VALUES '
        "('$buddedId', '$author'), ('$buddedId', '$postMember')",
      );
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    test('an uninvited Post member may read and post in Questions', () async {
      final probe = await access(postMember);
      expect(probe['beaconId'], buddedId);
      expect(probe['canRead'], isTrue);
      expect(probe['canPost'], isTrue);
      expect(probe['readOnlyReason'], isNull);
    });

    test('someone outside the Post has no Questions on it', () async {
      final probe = await access(stranger);
      expect(probe['canRead'], isFalse);
      expect(probe['canPost'], isFalse);
    });
  }, skip: skipReason ?? false);
}
