@Tags(['pg'])
library;

import 'package:mockito/mockito.dart' show Fake;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_people_seen_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/port/beacon_people_seen_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';

import '../../support/disposable_pg_target.dart';

const _beaconId = 'Bcoordseen01';
const _authorId = 'Ucoordauthor01';
const _stewardId = 'Ucoordsteward1';
const _firstHelperId = 'Ucoordhelper01';
const _secondHelperId = 'Ucoordhelper02';
const _outsiderId = 'Ucoordoutside1';

final _firstCreatedAt = DateTime.utc(2026, 6, 15, 12);
final _secondCreatedAt = _firstCreatedAt.add(const Duration(minutes: 10));

Future<void> main() async {
  test('CoordinationRepository accepts the People-seen domain port', () {
    // Function.apply lets this red-phase test compile against the current
    // four-argument constructor. The required fifth port is absent today.
    final repository = Function.apply(CoordinationRepository.new, [
      _UnusedDb(),
      _StubProfiles(),
      _StubFriendship(),
      _RecordingRoom(),
      _RecordingPeopleSeenPort(_UnusedPeopleSeenPort()),
    ]);

    expect(repository, isA<CoordinationRepository>());
  });

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_COORDINATION_AUTHOR_SEEN_REPO_TEST_DB',
    defaultNamePrefix: 'tentura_test_coord_author_seen',
  );
  final reachable = await canReachPostgresAdmin(target);

  group(
    'CoordinationRepository.helpOffersWithCoordination authorSeenAt',
    () {
      late DisposablePgWriterSession session;
      late Connection writer;
      late TenturaDb db;
      late _RecordingRoom room;
      late _RecordingPeopleSeenPort peopleSeen;
      late CoordinationRepository repository;

      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        db = openDisposablePgDatabase(target);
      });

      tearDownAll(() async {
        await db.close();
        await tearDownDisposablePgWriter(session: session);
      });

      setUp(() async {
        await writer.execute('''
          TRUNCATE TABLE public.beacon_people_seen, public.beacon_steward,
            public.beacon_participant, public.beacon_help_offer,
            public.beacon, public."user" CASCADE
        ''');

        for (final id in [
          _authorId,
          _stewardId,
          _firstHelperId,
          _secondHelperId,
          _outsiderId,
        ]) {
          await writer.execute(
            Sql.named('''
              INSERT INTO public."user" (id, display_name, public_key)
              VALUES (@id, @id, @key)
            '''),
            parameters: {'id': id, 'key': '$id-key'},
          );
        }
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon (id, user_id, title, description, status)
            VALUES (@beacon, @author, 'Request', 'Needs help', 0)
          '''),
          parameters: {'beacon': _beaconId, 'author': _authorId},
        );
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon_steward (beacon_id, user_id)
            VALUES (@beacon, @steward)
          '''),
          parameters: {'beacon': _beaconId, 'steward': _stewardId},
        );
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon_help_offer
              (beacon_id, user_id, message, status, created_at, updated_at)
            VALUES
              (@beacon, @first, 'First offer', 0, @firstAt, @firstAt),
              (@beacon, @second, 'Second offer', 0, @secondAt, @secondAt)
          '''),
          parameters: {
            'beacon': _beaconId,
            'first': _firstHelperId,
            'second': _secondHelperId,
            'firstAt': _firstCreatedAt,
            'secondAt': _secondCreatedAt,
          },
        );

        room = _RecordingRoom();
        peopleSeen = _RecordingPeopleSeenPort(BeaconPeopleSeenRepository(db));
        repository =
            Function.apply(CoordinationRepository.new, [
                  db,
                  _StubProfiles(),
                  _StubFriendship(),
                  room,
                  peopleSeen,
                ])
                as CoordinationRepository;
      });

      Future<void> storeWatermark(String userId, DateTime at) async {
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon_people_seen
              (user_id, beacon_id, last_seen_at)
            VALUES (@user, @beacon, @at)
          '''),
          parameters: {'user': userId, 'beacon': _beaconId, 'at': at},
        );
      }

      Future<Map<String, HelpOfferWithCoordinationRow>> loadRows({
        List<String> expectedModeratorIds = const [_authorId, _stewardId],
      }) async {
        final rows = await repository.helpOffersWithCoordination(
          _beaconId,
          viewerId: _firstHelperId,
        );
        expect(rows, hasLength(2));
        expect(room.calls, [_beaconId]);
        expect(peopleSeen.calls, hasLength(1));
        expect(peopleSeen.calls.single.beaconId, _beaconId);
        expect(
          peopleSeen.calls.single.userIds,
          unorderedEquals(expectedModeratorIds),
        );
        return {for (final row in rows) row.userId: row};
      }

      test('no moderator watermark leaves both offers unseen', () async {
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, isNull);
        expect(rows[_secondHelperId]!.authorSeenAt, isNull);
      });

      test('author watermark before offer creation is ignored', () async {
        await storeWatermark(
          _authorId,
          _firstCreatedAt.subtract(const Duration(microseconds: 1)),
        );
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, isNull);
        expect(rows[_secondHelperId]!.authorSeenAt, isNull);
      });

      test('author watermark exactly at creation counts', () async {
        await storeWatermark(_authorId, _firstCreatedAt);
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, _firstCreatedAt);
        expect(rows[_secondHelperId]!.authorSeenAt, isNull);
      });

      test('author watermark after creation counts', () async {
        final seenAt = _secondCreatedAt.add(const Duration(minutes: 1));
        await storeWatermark(_authorId, seenAt);
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, seenAt);
        expect(rows[_secondHelperId]!.authorSeenAt, seenAt);
      });

      test('author watermark counts when the beacon has no steward', () async {
        await writer.execute(
          Sql.named('''
            DELETE FROM public.beacon_steward WHERE beacon_id = @beacon
          '''),
          parameters: {'beacon': _beaconId},
        );
        room.stewardIds = [];
        final seenAt = _secondCreatedAt.add(const Duration(minutes: 1));
        await storeWatermark(_authorId, seenAt);

        final rows = await loadRows(expectedModeratorIds: [_authorId]);
        expect(rows[_firstHelperId]!.authorSeenAt, seenAt);
        expect(rows[_secondHelperId]!.authorSeenAt, seenAt);
      });

      test('steward-only watermark counts for withdrawn offers', () async {
        await writer.execute(
          Sql.named('''
            UPDATE public.beacon_help_offer SET status = 1
            WHERE beacon_id = @beacon AND user_id = @helper
          '''),
          parameters: {'beacon': _beaconId, 'helper': _firstHelperId},
        );
        final seenAt = _secondCreatedAt.add(const Duration(minutes: 1));
        await storeWatermark(_stewardId, seenAt);
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.status, 1);
        expect(rows[_firstHelperId]!.authorSeenAt, seenAt);
        expect(rows[_secondHelperId]!.authorSeenAt, seenAt);
      });

      test('latest author or steward watermark wins', () async {
        final authorAt = _secondCreatedAt.add(const Duration(minutes: 1));
        final stewardAt = authorAt.add(const Duration(minutes: 1));
        await storeWatermark(_authorId, authorAt);
        await storeWatermark(_stewardId, stewardAt);
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, stewardAt);
        expect(rows[_secondHelperId]!.authorSeenAt, stewardAt);
      });

      test('later author watermark wins over steward watermark', () async {
        final stewardAt = _secondCreatedAt.add(const Duration(minutes: 1));
        final authorAt = stewardAt.add(const Duration(minutes: 1));
        await storeWatermark(_stewardId, stewardAt);
        await storeWatermark(_authorId, authorAt);
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, authorAt);
        expect(rows[_secondHelperId]!.authorSeenAt, authorAt);
      });

      test('uses the People-seen port result as its watermark source', () async {
        final seenAt = _secondCreatedAt.add(const Duration(minutes: 1));
        peopleSeen.overrideResult = {_authorId: seenAt};
        // The database has no moderator watermark. Inline SQL would return null.
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, seenAt);
        expect(rows[_secondHelperId]!.authorSeenAt, seenAt);
      });

      test('non-moderator watermark is ignored', () async {
        await storeWatermark(
          _outsiderId,
          _secondCreatedAt.add(const Duration(minutes: 1)),
        );
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, isNull);
        expect(rows[_secondHelperId]!.authorSeenAt, isNull);
      });

      test('one watermark applies only to offers already created', () async {
        final between = _firstCreatedAt.add(const Duration(minutes: 5));
        await storeWatermark(_stewardId, between);
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, between);
        expect(rows[_secondHelperId]!.authorSeenAt, isNull);
      });

      test('moderator ids are deduplicated before one batch lookup', () async {
        room.stewardIds = [_authorId, _stewardId];
        await storeWatermark(_authorId, _secondCreatedAt);
        final rows = await loadRows();
        expect(rows[_firstHelperId]!.authorSeenAt, _secondCreatedAt);
      });
    },
    skip: reachable ? false : 'Postgres admin database not reachable',
  );
}

final class _UnusedDb extends Fake implements TenturaDb {}

final class _StubProfiles extends Fake implements UserProfileBatchLookup {
  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => {
    for (final id in ids)
      id: UserPublicRecord(
        id: id,
        displayName: id,
        description: '',
        userAvailability: null,
      ),
  };
}

final class _StubFriendship extends Fake
    implements VoteUserFriendshipLookupPort {
  @override
  Future<({Set<String> viewerTrusts, Set<String> trustsViewer})>
  directionalPositiveTrustPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async => (viewerTrusts: <String>{}, trustsViewer: <String>{});
}

final class _RecordingRoom extends Fake implements BeaconRoomRepositoryPort {
  List<String> stewardIds = [_stewardId];
  final calls = <String>[];

  @override
  Future<List<String>> listStewardUserIds(String beaconId) async {
    calls.add(beaconId);
    return stewardIds;
  }
}

final class _UnusedPeopleSeenPort extends Fake
    implements BeaconPeopleSeenRepositoryPort {}

final class _RecordingPeopleSeenPort extends Fake
    implements BeaconPeopleSeenRepositoryPort {
  _RecordingPeopleSeenPort(this.delegate);

  final BeaconPeopleSeenRepositoryPort delegate;
  final calls = <({String beaconId, List<String> userIds})>[];
  Map<String, DateTime>? overrideResult;

  @override
  Future<Map<String, DateTime>> lastSeenByUserIds({
    required String beaconId,
    required List<String> userIds,
  }) async {
    calls.add((beaconId: beaconId, userIds: List.of(userIds)));
    final result = overrideResult;
    if (result != null) return result;
    return delegate.lastSeenByUserIds(beaconId: beaconId, userIds: userIds);
  }
}
