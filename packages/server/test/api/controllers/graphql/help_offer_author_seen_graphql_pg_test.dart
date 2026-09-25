@Tags(['pg'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';

const _beaconId = 'Bauthorseen01';
const _otherBeaconId = 'Bauthorseen02';
const _authorId = 'Uauthor000001';
const _stewardId = 'Usteward00001';
const _helperId = 'Uhelper000001';
const _otherHelperId = 'Uhelper000002';

const _markSeen = r'''
mutation MarkBeaconPeopleSeen($beaconId: String!, $readThroughAt: String) {
  MarkBeaconPeopleSeen(beaconId: $beaconId, readThroughAt: $readThroughAt) {
    beaconId
    seenAt
  }
}
''';

const _offers = r'''
query HelpOffersWithCoordination($id: String!) {
  helpOffersWithCoordination(id: $id) {
    userId
    createdAt
    authorSeenAt
  }
}
''';

/// Issue #178 part 2, end to end over the real V2 GraphQL schema (real DI,
/// disposable Postgres): `MarkBeaconPeopleSeen` persists the People-surface
/// watermark for the author/steward only, and `helpOffersWithCoordination`
/// derives `authorSeenAt` from the stored watermarks versus the offer's
/// `createdAt` (plan D2/D5), visible to the offer owner and moderators only
/// (D6).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HELP_OFFER_AUTHOR_SEEN_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_author_seen_gql',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('help offer author-seen GraphQL', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;

    // Offer created well in the past so server-now watermarks are after it.
    final offerCreatedAt = DateTime.utc(2026, 6, 15, 12);
    // The second helper offers later, so one watermark can fall between the
    // two offers (per-offer `>=` rule, D5).
    final laterOfferCreatedAt = offerCreatedAt.add(const Duration(minutes: 10));

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      // Real (dev) repositories against the disposable database; the test
      // environment registers mocks for most ports.
      final db = target.databaseEnv;
      await configureDependencies(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          publicOrigin: 'http://127.0.0.1:2080',
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      schema = graphqlSchema;
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_people_seen,
  public.beacon_steward,
  public.beacon_participant,
  public.beacon_help_offer,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_authorId, _stewardId, _helperId, _otherHelperId]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@b, @author, 'Request', 'Needs help', 0)
'''),
        parameters: {'b': _beaconId, 'author': _authorId},
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_steward (beacon_id, user_id) '
          'VALUES (@b, @s)',
        ),
        parameters: {'b': _beaconId, 's': _stewardId},
      );
      // Mirrors BeaconRoomRepository.setBeaconSteward: the steward also holds
      // a participant row carrying the steward role (role = 1), which the
      // involvement predicate requires.
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  'Pauthorseen01', @b, @s, 1, 0, 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
        parameters: {'b': _beaconId, 's': _stewardId},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, message, status, created_at, updated_at)
VALUES
  (@b, @h1, 'I can help', 0, @at, @at),
  (@b, @h2, 'Me too', 0, @later, @later)
'''),
        parameters: {
          'b': _beaconId,
          'h1': _helperId,
          'h2': _otherHelperId,
          'at': offerCreatedAt,
          'later': laterOfferCreatedAt,
        },
      );
    });

    Future<Map<String, dynamic>> run(
      String userId,
      String document,
      Map<String, dynamic> variables,
    ) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: userId)},
            )
            as Map<String, dynamic>;

    Future<Map<String, dynamic>> mark(String userId, {String? readThrough}) =>
        run(userId, _markSeen, {
          'beaconId': _beaconId,
          'readThroughAt': readThrough,
        });

    Future<DateTime?> seenAtFor({
      required String viewerId,
      String offerUserId = _helperId,
    }) async {
      final data = await run(viewerId, _offers, {'id': _beaconId});
      final row = (data['helpOffersWithCoordination'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((r) => r['userId'] == offerUserId);
      final raw = row['authorSeenAt'] as String?;
      return raw == null ? null : DateTime.parse(raw).toUtc();
    }

    Future<DateTime?> storedWatermark(String userId) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT last_seen_at FROM public.beacon_people_seen '
          'WHERE user_id = @u AND beacon_id = @b',
        ),
        parameters: {'u': userId, 'b': _beaconId},
      );
      return rows.isEmpty ? null : (rows.single[0]! as DateTime).toUtc();
    }

    group('MarkBeaconPeopleSeen', () {
      test('author persists the watermark and gets it back', () async {
        final before = DateTime.timestamp();
        final data = await mark(_authorId);
        final result = data['MarkBeaconPeopleSeen'] as Map<String, dynamic>;

        expect(result['beaconId'], _beaconId);
        final seenAt = DateTime.parse(result['seenAt'] as String).toUtc();
        expect(
          seenAt.isBefore(before.subtract(const Duration(seconds: 1))),
          isFalse,
        );
        expect(await storedWatermark(_authorId), seenAt);
      });

      test('steward persists its own watermark', () async {
        final data = await mark(_stewardId);
        final result = data['MarkBeaconPeopleSeen'] as Map<String, dynamic>;
        final seenAt = DateTime.parse(result['seenAt'] as String).toUtc();

        expect(await storedWatermark(_stewardId), seenAt);
        expect(await storedWatermark(_authorId), isNull);
      });

      test('helper is rejected and nothing is stored', () async {
        await expectLater(mark(_helperId), throwsA(anything));
        expect(await storedWatermark(_helperId), isNull);
      });

      test('future readThroughAt is clamped to server now', () async {
        final data = await mark(
          _authorId,
          readThrough: DateTime.timestamp()
              .add(const Duration(days: 3))
              .toIso8601String(),
        );
        final result = data['MarkBeaconPeopleSeen'] as Map<String, dynamic>;
        final seenAt = DateTime.parse(result['seenAt'] as String).toUtc();

        expect(
          seenAt.isAfter(DateTime.timestamp().add(const Duration(minutes: 1))),
          isFalse,
        );
      });

      test('older readThroughAt never regresses the watermark', () async {
        final first = await mark(_authorId);
        final firstSeen = DateTime.parse(
          (first['MarkBeaconPeopleSeen'] as Map)['seenAt'] as String,
        ).toUtc();

        final second = await mark(
          _authorId,
          readThrough: DateTime.utc(2026).toIso8601String(),
        );
        final secondSeen = DateTime.parse(
          (second['MarkBeaconPeopleSeen'] as Map)['seenAt'] as String,
        ).toUtc();

        expect(secondSeen, firstSeen);
        expect(await storedWatermark(_authorId), firstSeen);
      });
    });

    group('authorSeenAt on helpOffersWithCoordination', () {
      Future<void> storeWatermark(
        String userId,
        DateTime at, {
        String beaconId = _beaconId,
      }) => writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_people_seen '
          '(user_id, beacon_id, last_seen_at) VALUES (@u, @b, @at)',
        ),
        parameters: {'u': userId, 'b': beaconId, 'at': at},
      );

      test('no watermark → null', () async {
        expect(await seenAtFor(viewerId: _helperId), isNull);
      });

      test('author watermark before the offer → null', () async {
        await storeWatermark(
          _authorId,
          offerCreatedAt.subtract(const Duration(minutes: 1)),
        );
        expect(await seenAtFor(viewerId: _helperId), isNull);
      });

      test('author watermark at/after the offer → that watermark', () async {
        final seen = offerCreatedAt.add(const Duration(minutes: 5));
        await storeWatermark(_authorId, seen);
        expect(await seenAtFor(viewerId: _helperId), seen);
      });

      test(
        'author watermark exactly at the offer createdAt counts (>=)',
        () async {
          await storeWatermark(_authorId, offerCreatedAt);
          expect(await seenAtFor(viewerId: _helperId), offerCreatedAt);
        },
      );

      test('one watermark between two offers: earlier offer seen, later '
          'offer not', () async {
        final between = offerCreatedAt.add(const Duration(minutes: 5));
        await storeWatermark(_authorId, between);

        expect(await seenAtFor(viewerId: _authorId), between);
        expect(
          await seenAtFor(viewerId: _authorId, offerUserId: _otherHelperId),
          isNull,
        );
      });

      test('a watermark on another request does not count', () async {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@b, @author, 'Other request', 'Elsewhere', 0)
'''),
          parameters: {'b': _otherBeaconId, 'author': _authorId},
        );
        await storeWatermark(
          _authorId,
          offerCreatedAt.add(const Duration(minutes: 5)),
          beaconId: _otherBeaconId,
        );
        expect(await seenAtFor(viewerId: _helperId), isNull);
      });

      test('steward-only watermark counts (plan D2: steward acts for the '
          'author)', () async {
        final seen = offerCreatedAt.add(const Duration(minutes: 7));
        await storeWatermark(_stewardId, seen);
        expect(await seenAtFor(viewerId: _helperId), seen);
      });

      test('author and steward with different timestamps → the later '
          'qualifying one', () async {
        final authorSeen = offerCreatedAt.add(const Duration(minutes: 3));
        final stewardSeen = offerCreatedAt.add(const Duration(minutes: 9));
        await storeWatermark(_authorId, authorSeen);
        await storeWatermark(_stewardId, stewardSeen);
        expect(await seenAtFor(viewerId: _helperId), stewardSeen);
      });

      test('author before offer, steward after → steward watermark', () async {
        final stewardSeen = offerCreatedAt.add(const Duration(minutes: 2));
        await storeWatermark(
          _authorId,
          offerCreatedAt.subtract(const Duration(hours: 1)),
        );
        await storeWatermark(_stewardId, stewardSeen);
        expect(await seenAtFor(viewerId: _helperId), stewardSeen);
      });

      test('a helper watermark row never counts as "seen"', () async {
        await storeWatermark(
          _otherHelperId,
          offerCreatedAt.add(const Duration(minutes: 5)),
        );
        expect(await seenAtFor(viewerId: _helperId), isNull);
      });

      test('D6: owner and moderators see it, other helpers get null', () async {
        final seen = offerCreatedAt.add(const Duration(minutes: 5));
        await storeWatermark(_authorId, seen);

        expect(await seenAtFor(viewerId: _helperId), seen);
        expect(await seenAtFor(viewerId: _authorId), seen);
        expect(await seenAtFor(viewerId: _stewardId), seen);
        expect(await seenAtFor(viewerId: _otherHelperId), isNull);
      });

      test('mutation round trip: author marks, offerer then sees it', () async {
        expect(await seenAtFor(viewerId: _helperId), isNull);
        final data = await mark(_authorId);
        final seenAt = DateTime.parse(
          (data['MarkBeaconPeopleSeen'] as Map)['seenAt'] as String,
        ).toUtc();
        expect(await seenAtFor(viewerId: _helperId), seenAt);
      });
    });
  }, skip: skipReason);
}
