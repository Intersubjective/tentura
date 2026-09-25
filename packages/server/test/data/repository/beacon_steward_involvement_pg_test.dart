@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/beacon_involvement_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/help_offer_case_mocks.mocks.dart' as help_mocks;
import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/recording_commitment_repository.dart';

const _author = 'Ustwinvauthor';
const _steward = 'Ustwinvstewd';
const _appointed = 'Ustwinvappnt';
const _stranger = 'Ustwinvstrng';

/// Steward exists only in `beacon_steward` (no `beacon_participant` row).
const _stewardOnlyBeacon = 'Bstwinvonly1';

/// Steward is appointed through [BeaconRoomRepository.setBeaconSteward]
/// without any prior participant row.
const _appointedBeacon = 'Bstwinvappt1';

/// tentura-1ev: a steward recognised by `beacon_can_read_content` (via
/// `beacon_steward`) must also pass `beacon_can_read_involvement`, so
/// [CoordinationCase.helpOffersWithCoordination] does not reject them with
/// "Viewer cannot read request involvement".
Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for steward involvement PG test';

  group('steward involvement without participant row — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late TenturaDb db;
    late BeaconAccessRepository access;
    var sessionOpened = false;
    BeaconHierarchyDisposablePgTarget? createdTarget;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      createdTarget = target;
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      db = session.db;
      access = BeaconAccessRepository(db);
      sessionOpened = true;
      await _seed(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      if (sessionOpened) {
        await db.close();
        await writer.close();
      }
      await createdTarget?.drop();
    });

    Future<bool> sqlPredicate(String fn, String beaconId, String viewerId) async {
      final rows = await writer.execute(
        Sql.named('SELECT public.$fn(@b, @v) AS allowed'),
        parameters: {'b': beaconId, 'v': viewerId},
      );
      return rows.first.first! as bool;
    }

    test(
      'fixture: steward has a beacon_steward row and no participant row',
      () async {
        final stewards = await writer.execute(
          Sql.named(
            'SELECT 1 FROM public.beacon_steward '
            'WHERE beacon_id = @b AND user_id = @u',
          ),
          parameters: {'b': _stewardOnlyBeacon, 'u': _steward},
        );
        expect(stewards, hasLength(1));
        final participants = await writer.execute(
          Sql.named(
            'SELECT 1 FROM public.beacon_participant '
            'WHERE beacon_id = @b AND user_id = @u',
          ),
          parameters: {'b': _stewardOnlyBeacon, 'u': _steward},
        );
        expect(participants, isEmpty);
        // Content already recognises the steward via beacon_steward.
        expect(
          await sqlPredicate(
            'beacon_can_read_content',
            _stewardOnlyBeacon,
            _steward,
          ),
          isTrue,
        );
      },
      skip: skipReason,
    );

    test(
      'SQL beacon_can_read_involvement grants a beacon_steward-only steward',
      () async {
        expect(
          await sqlPredicate(
            'beacon_can_read_involvement',
            _stewardOnlyBeacon,
            _steward,
          ),
          isTrue,
          reason: 'involvement must agree with content for stewards',
        );
      },
      skip: skipReason,
    );

    test(
      'BeaconAccessRepository.canReadInvolvement grants a beacon_steward-only '
      'steward',
      () async {
        expect(
          await access.canReadInvolvement(
            beaconId: _stewardOnlyBeacon,
            viewerId: _steward,
          ),
          isTrue,
        );
      },
      skip: skipReason,
    );

    test(
      'non-steward stranger still fails involvement; author still passes',
      () async {
        expect(
          await access.canReadInvolvement(
            beaconId: _stewardOnlyBeacon,
            viewerId: _stranger,
          ),
          isFalse,
        );
        expect(
          await access.canReadInvolvement(
            beaconId: _stewardOnlyBeacon,
            viewerId: _author,
          ),
          isTrue,
        );
      },
      skip: skipReason,
    );

    test(
      'CoordinationCase.helpOffersWithCoordination admits a '
      'beacon_steward-only steward',
      () async {
        final sut = _buildCoordinationCase(
          access: access,
          beaconId: _stewardOnlyBeacon,
        );
        final rows = await sut.helpOffersWithCoordination(
          beaconId: _stewardOnlyBeacon,
          viewerId: _steward,
        );
        expect(rows, isEmpty);

        await expectLater(
          sut.helpOffersWithCoordination(
            beaconId: _stewardOnlyBeacon,
            viewerId: _stranger,
          ),
          throwsA(
            isA<UnauthorizedException>().having(
              (e) => e.description,
              'description',
              'Viewer cannot read request involvement',
            ),
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'BeaconInvolvementCase.asMap admits a beacon_steward-only steward',
      () async {
        final sut = _buildBeaconInvolvementCase(
          access: access,
          beaconId: _stewardOnlyBeacon,
        );
        final result = await sut.asMap(
          beaconId: _stewardOnlyBeacon,
          currentUserId: _steward,
        );
        expect(result.forwardedToIds, isEmpty);
        expect(result.helpOfferedIds, isEmpty);

        await expectLater(
          _buildBeaconInvolvementCase(
            access: access,
            beaconId: _stewardOnlyBeacon,
          ).asMap(
            beaconId: _stewardOnlyBeacon,
            currentUserId: _stranger,
          ),
          throwsA(
            isA<UnauthorizedException>().having(
              (e) => e.description,
              'description',
              'Viewer cannot read request involvement',
            ),
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'setBeaconSteward on a user without a participant row grants involvement',
      () async {
        final before = await writer.execute(
          Sql.named(
            'SELECT 1 FROM public.beacon_participant '
            'WHERE beacon_id = @b AND user_id = @u',
          ),
          parameters: {'b': _appointedBeacon, 'u': _appointed},
        );
        expect(before, isEmpty);

        await BeaconRoomRepository(db).setBeaconSteward(
          beaconId: _appointedBeacon,
          stewardUserId: _appointed,
          authorUserId: _author,
        );

        expect(
          await access.canReadContent(
            beaconId: _appointedBeacon,
            viewerId: _appointed,
          ),
          isTrue,
        );
        expect(
          await access.canReadInvolvement(
            beaconId: _appointedBeacon,
            viewerId: _appointed,
          ),
          isTrue,
        );
        final rows = await _buildCoordinationCase(
          access: access,
          beaconId: _appointedBeacon,
        ).helpOffersWithCoordination(
          beaconId: _appointedBeacon,
          viewerId: _appointed,
        );
        expect(rows, isEmpty);
      },
      skip: skipReason,
    );
  });
}

final _env = Env(environment: Environment.test);
final _logger = Logger('beacon_steward_involvement_pg_test');

/// Real [BeaconAccessRepository] guard; downstream ports stubbed so a call
/// that passes the guard completes without touching the database.
BeaconInvolvementCase _buildBeaconInvolvementCase({
  required BeaconAccessRepository access,
  required String beaconId,
}) {
  final forward = help_mocks.MockForwardEdgeRepositoryPort();
  when(forward.fetchByBeaconId(beaconId)).thenAnswer((_) async => []);
  when(forward.fetchDistinctSenderIdsByBeaconId(beaconId))
      .thenAnswer((_) async => []);
  when(forward.markAsRead(any, any)).thenAnswer((_) async {});
  final help = help_mocks.MockHelpOfferRepositoryPort();
  when(help.fetchAllByBeaconId(beaconId)).thenAnswer((_) async => []);
  final inbox = help_mocks.MockInboxRepositoryPort();
  when(inbox.fetchRejectedUserIdsByBeacon(beaconId))
      .thenAnswer((_) async => []);
  when(inbox.fetchWatchingUserIdsByBeacon(beaconId))
      .thenAnswer((_) async => []);
  return BeaconInvolvementCase(
    forward,
    help,
    inbox,
    access,
    env: _env,
    logger: _logger,
  );
}

CoordinationCase _buildCoordinationCase({
  required BeaconAccessRepository access,
  required String beaconId,
}) {
  final now = DateTime.utc(2026);
  final beacons = help_mocks.MockBeaconRepositoryPort();
  when(beacons.getBeaconById(beaconId: beaconId)).thenAnswer(
    (_) async => BeaconEntity(
      id: beaconId,
      title: 'Steward involvement',
      author: const UserEntity(id: _author),
      createdAt: now,
      updatedAt: now,
    ),
  );
  final room = help_mocks.MockBeaconRoomRepositoryPort();
  when(
    room.isBeaconSteward(beaconId: beaconId, userId: anyNamed('userId')),
  ).thenAnswer((_) async => true);
  final coordination = help_mocks.MockCoordinationRepositoryPort();
  when(
    coordination.helpOffersWithCoordination(
      beaconId,
      viewerId: anyNamed('viewerId'),
    ),
  ).thenAnswer((_) async => []);
  return CoordinationCase(
    beacons,
    help_mocks.MockHelpOfferRepositoryPort(),
    coordination,
    room,
    _FakeEvaluationRepository(),
    FakeUserBlockRepository(),
    RecordingCommitmentRepository(),
    CommitmentQueryCase(
      RecordingCommitmentRepository(),
      help_mocks.MockHelpOfferRepositoryPort(),
      env: _env,
      logger: _logger,
    ),
    FakeBeaconHierarchyRepository(),
    guard: access,
    env: _env,
    logger: _logger,
  );
}

final class _FakeEvaluationRepository extends Fake
    implements EvaluationRepositoryPort {}

Future<void> _seed(Connection writer) async {
  for (final (i, id) in [_author, _steward, _appointed, _stranger].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('sv', i + 1)},
    );
  }
  for (final b in [_stewardOnlyBeacon, _appointedBeacon]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  @b, @author, 'Steward involvement', '', @status, false,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
      parameters: {
        'b': b,
        'author': _author,
        'status': BeaconStatus.open.smallintValue,
      },
    );
  }
  // Legacy / steward-table-only shape: no beacon_participant row.
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon_steward (beacon_id, user_id) VALUES (@b, @u)',
    ),
    parameters: {'b': _stewardOnlyBeacon, 'u': _steward},
  );
}
