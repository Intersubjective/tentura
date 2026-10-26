@Tags(['pg'])
library;

import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../../support/disposable_pg_target.dart';

const _author = 'Ufieldttl01';
const _post = 'Bfieldttl01';

/// Post presence follows its expiry, while a personal pin keeps a closed Post
/// on the field. The snapshot must carry the lifecycle through the V2 mapper.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_POST_LIFECYCLE_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_post_ttl',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late ConstellationFieldRepository repository;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    repository = ConstellationFieldRepository(database, _Profiles());
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    await writer.execute('''
TRUNCATE public.beacon, public."user" CASCADE
''');
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_author', 'Author', 'key-$_author')
''');
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, published_at,
   last_activity_at, expires_at, is_discoverable)
VALUES ('$_post', '$_author', '', '', 1, 0, now(), now(),
        now() + interval '2 hours', false)
''');
  });

  Future<ConstellationFieldSnapshot> read() => repository.readSnapshot(
    viewerId: _author,
    context: '',
    params: (
      filters: ConstellationFieldMembershipFilters.defaults,
      projection: ConstellationProjection.full,
    ),
  );

  Future<DateTime> expiry() async =>
      (await writer.execute(
            "SELECT expires_at FROM public.beacon WHERE id = '$_post'",
          )).single.single!
          as DateTime;

  Map<String, dynamic> wirePost(ConstellationFieldSnapshot snapshot) =>
      (constellationFieldToGqlMap(snapshot)['posts'] as List).single
          as Map<String, dynamic>;

  void expectRecordLifecycle(
    ConstellationPostRecord record, {
    required DateTime expiresAt,
    required int status,
  }) {
    // Dynamic access keeps this contract test executable before the record
    // gains its lifecycle getters; the assertions must exercise the record,
    // independently of the GraphQL schema and mapper.
    final dynamic post = record;
    expect(
      // The required getter is absent before the lifecycle record is implemented.
      // ignore: avoid_dynamic_calls
      () => post.expiresAt,
      returnsNormally,
      reason: 'ConstellationPostRecord must expose expiresAt',
    );
    // Read the required getter checked by the preceding contract assertion.
    // ignore: avoid_dynamic_calls
    expect(post.expiresAt, expiresAt);
    expect(
      // The required getter is absent before the lifecycle record is implemented.
      // ignore: avoid_dynamic_calls
      () => post.status,
      returnsNormally,
      reason: 'ConstellationPostRecord must expose status',
    );
    // Read the required getter checked by the preceding contract assertion.
    // ignore: avoid_dynamic_calls
    expect(post.status, status);
  }

  group('constellation Post lifecycle', () {
    test('an open unexpired Post exposes its expiry and open status', () async {
      final expectedExpiry = await expiry();
      final snapshot = await read();
      expect(snapshot.posts.map((p) => p.id), [_post]);

      expectRecordLifecycle(
        snapshot.posts.single,
        expiresAt: expectedExpiry,
        status: 0,
      );
      final mapped = wirePost(snapshot);
      expect(mapped['expiresAt'], expectedExpiry.toUtc().toIso8601String());
      expect(mapped['status'], 0);
    });

    test('the V2 Post type exposes expiry and lifecycle status', () {
      final fields = {
        for (final field in gqlTypeConstellationPost.fields)
          field.name: field.type.toString(),
      };
      expect(fields['expiresAt'], anyOf('String', 'String!'));
      expect(fields['status'], anyOf('Int', 'Int!'));
    });

    test('an expired open Post leaves the field before closure', () async {
      expect((await read()).posts.map((p) => p.id), [_post]);
      await writer.execute('''
UPDATE public.beacon SET expires_at = now() - interval '1 minute'
WHERE id = '$_post'
''');
      expect(
        (await writer.execute(
          "SELECT status FROM public.beacon WHERE id = '$_post'",
        )).single.single,
        0,
        reason: 'expiry alone must remove the Post without a closing sweep',
      );

      final snapshot = await read();
      expect(snapshot.posts, isEmpty);
      expect(snapshot.memberWebs, isEmpty);
    });

    test(
      'a closed Post returns only when pinned and carries status 6',
      () async {
        await writer.execute('''
UPDATE public.beacon SET status = 6 WHERE id = '$_post'
''');
        expect((await read()).posts, isEmpty);

        await writer.execute('''
INSERT INTO public.beacon_pinned (user_id, beacon_id)
VALUES ('$_author', '$_post')
''');
        final snapshot = await read();
        expect(snapshot.posts.map((p) => p.id), [_post]);
        expect(snapshot.posts.single.isPinned, isTrue);
        expectRecordLifecycle(
          snapshot.posts.single,
          expiresAt: await expiry(),
          status: 6,
        );
        expect(wirePost(snapshot)['status'], 6);
        expect(
          wirePost(snapshot)['expiresAt'],
          (await expiry()).toUtc().toIso8601String(),
        );
      },
    );

    test(
      'future expiry keeps a Post whose last activity was over 72 hours ago',
      () async {
        await writer.execute('''
UPDATE public.beacon SET last_activity_at = now() - interval '100 hours'
WHERE id = '$_post'
''');

        final snapshot = await read();
        expect(snapshot.posts.map((p) => p.id), [_post]);
        expect(snapshot.posts.single.isPinned, isFalse);
      },
    );
  });
}

final class _Profiles extends Fake implements UserProfileBatchLookup {
  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) async => {
    for (final id in ids) id: ConstellationPeerRecord(id: id, displayName: id),
  };
}
