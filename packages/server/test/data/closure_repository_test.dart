@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/closure/closure_band.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';

import '../support/closure_repository_a11_contract.dart';
import '../support/closure_repository_red_fixture.dart';
import '../support/disposable_pg_target.dart';
import '../support/pg_test_public_keys.dart';

const _authorId = 'Uclrepoauth01';
const _helper1Id = 'Uclrepohelp01';
const _helper2Id = 'Uclrepohelp02';
const _helper3Id = 'Uclrepohelp03';
const _voterId = _helper1Id;
const _beaconId = 'Bclrepobeac01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CLOSURE_REPO_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_closure_repo',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late ClosureRepositoryPort repo;
  late MutatingUnitOfWork unitOfWork;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      repo = ClosureRepository(database);
      unitOfWork = MutatingUnitOfWork(database);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  group('ClosureRepository', () {
    setUp(() async {
      await _truncateClosureTables(writer);
      await _seedUsersAndBeacon(writer);
    });

    test(
      'lockRequest runs inside a transaction',
      () async {
        await unitOfWork.run(
          actorUserId: _authorId,
          action: () => repo.lockRequest(_beaconId),
        );
      },
      skip: skipReason,
    );

    test(
      'liveEpoch createEpoch and setEpochStatus round-trip',
      () async {
        final openedAt = DateTime.utc(2026, 3, 1, 12);
        final closesAt = openedAt.add(const Duration(days: 7));

        expect(await repo.liveEpoch(_beaconId), isNull);

        final created = await repo.createEpoch(
          beaconId: _beaconId,
          epoch: 1,
          openedAt: openedAt,
          closesAt: closesAt,
        );
        expect(created.beaconId, _beaconId);
        expect(created.epoch, 1);
        expect(created.status, ClosureEpochStatus.evaluating);
        expect(created.openedAt, openedAt);
        expect(created.closesAt, closesAt);
        expect(created.extensionsUsed, 0);

        final live = await repo.liveEpoch(_beaconId);
        expect(live, isNotNull);
        expect(live!.epoch, 1);
        expect(live.status, ClosureEpochStatus.evaluating);

        await repo.setEpochStatus(
          beaconId: _beaconId,
          epoch: 1,
          status: ClosureEpochStatus.cancelled,
        );
        expect(await repo.liveEpoch(_beaconId), isNull);

        final reopenedAt = DateTime.utc(2026, 3, 2, 12);
        final reopened = await repo.createEpoch(
          beaconId: _beaconId,
          epoch: 2,
          openedAt: reopenedAt,
          closesAt: reopenedAt.add(const Duration(days: 7)),
        );
        expect(reopened.epoch, 2);
        expect(reopened.status, ClosureEpochStatus.evaluating);
        expect((await repo.liveEpoch(_beaconId))?.epoch, 2);

        final finalizedAt = DateTime.utc(2026, 3, 9, 12);
        await repo.setEpochStatus(
          beaconId: _beaconId,
          epoch: 2,
          status: ClosureEpochStatus.finalized,
          finalizedAt: finalizedAt,
          finalizeReason: 1,
          settlementVersion: 1,
          settlementParams: const {'B': 1.0},
        );
        expect(await repo.liveEpoch(_beaconId), isNull);
      },
      skip: skipReason,
    );

    test(
      'insertMembers setDeparture and members round-trip',
      () async {
        await repo.createEpoch(
          beaconId: _beaconId,
          epoch: 1,
          openedAt: DateTime.utc(2026, 3, 1),
          closesAt: DateTime.utc(2026, 3, 8),
        );

        await repo.insertMembers(
          beaconId: _beaconId,
          epoch: 1,
          members: const [
            ClosureMemberInsert(
              userId: _helper1Id,
              activeAtOpen: true,
              arrivalEdgeId: 'Fclrepoedge01',
            ),
            ClosureMemberInsert(
              userId: _helper2Id,
              activeAtOpen: false,
              departure: Departure.voluntary,
            ),
          ],
        );

        var rows = await repo.members(beaconId: _beaconId, epoch: 1);
        expect(rows, hasLength(2));
        rows = List.of(rows)..sort((a, b) => a.userId.compareTo(b.userId));

        expect(rows[0].userId, _helper1Id);
        expect(rows[0].activeAtOpen, isTrue);
        expect(rows[0].arrivalEdgeId, 'Fclrepoedge01');
        expect(rows[0].departure, isNull);

        expect(rows[1].userId, _helper2Id);
        expect(rows[1].activeAtOpen, isFalse);
        expect(rows[1].departure, Departure.voluntary);

        await repo.setDeparture(
          beaconId: _beaconId,
          epoch: 1,
          userId: _helper1Id,
          departure: Departure.removed,
        );

        rows = await repo.members(beaconId: _beaconId, epoch: 1);
        final h1 = rows.singleWhere((r) => r.userId == _helper1Id);
        expect(h1.departure, Departure.removed);
        expect(h1.activeAtOpen, isTrue);
      },
      skip: skipReason,
    );

    test(
      'saveOutcome and outcomes round-trip',
      () async {
        await repo.saveOutcome(
          beaconId: _beaconId,
          helperId: _helper1Id,
          outcome: ClosureOutcome.done,
        );
        await repo.saveOutcome(
          beaconId: _beaconId,
          helperId: _helper2Id,
          outcome: ClosureOutcome.cantJudge,
        );

        final rows = await repo.outcomes(_beaconId);
        expect(rows, hasLength(2));
        final byHelper = {for (final r in rows) r.helperId: r.outcome};
        expect(byHelper[_helper1Id], ClosureOutcome.done);
        expect(byHelper[_helper2Id], ClosureOutcome.cantJudge);

        await repo.saveOutcome(
          beaconId: _beaconId,
          helperId: _helper1Id,
          outcome: null,
        );
        final cleared = await repo.outcomes(_beaconId);
        final h1 = cleared.singleWhere((r) => r.helperId == _helper1Id);
        expect(h1.outcome, isNull);
      },
      skip: skipReason,
    );

    test(
      'replaceSplit and split round-trip',
      () async {
        expect(await repo.split(_beaconId), isEmpty);

        await repo.replaceSplit(_beaconId, {
          _helper1Id: 70,
          _helper2Id: 30,
        });
        expect(await repo.split(_beaconId), {
          _helper1Id: 70,
          _helper2Id: 30,
        });

        await repo.replaceSplit(_beaconId, null);
        expect(await repo.split(_beaconId), isEmpty);
      },
      skip: skipReason,
    );

    test(
      'toggleSupport commitSupport skip clearCommitted and supports round-trip',
      () async {
        await repo.toggleSupport(
          beaconId: _beaconId,
          voterId: _voterId,
          targetId: _helper2Id,
          on: true,
        );
        await repo.toggleSupport(
          beaconId: _beaconId,
          voterId: _voterId,
          targetId: _helper3Id,
          on: true,
        );

        final drafts = await repo.supports(
          beaconId: _beaconId,
          version: ClosureSupportVersion.draft,
        );
        expect(drafts, hasLength(2));
        expect(
          drafts.map((r) => r.targetId).toSet(),
          {_helper2Id, _helper3Id},
        );

        await repo.commitSupport(beaconId: _beaconId, voterId: _voterId);

        final committed = await repo.supports(
          beaconId: _beaconId,
          version: ClosureSupportVersion.committed,
        );
        expect(committed, hasLength(2));

        final commitRows = await repo.commits(_beaconId);
        expect(commitRows, hasLength(1));
        expect(commitRows.single.voterId, _voterId);

        await repo.toggleSupport(
          beaconId: _beaconId,
          voterId: _helper2Id,
          targetId: _helper3Id,
          on: true,
        );
        await repo.skip(beaconId: _beaconId, voterId: _helper2Id);
        expect(await repo.commits(_beaconId), hasLength(2));

        await repo.clearCommitted(_beaconId);
        expect(
          await repo.supports(
            beaconId: _beaconId,
            version: ClosureSupportVersion.committed,
          ),
          isEmpty,
        );
        expect(await repo.commits(_beaconId), isEmpty);
        expect(
          await repo.supports(
            beaconId: _beaconId,
            version: ClosureSupportVersion.draft,
          ),
          hasLength(1),
        );
      },
      skip: skipReason,
    );

    test(
      'setMark marks saveStory and story round-trip',
      () async {
        await repo.setMark(
          beaconId: _beaconId,
          markerId: _voterId,
          targetId: _helper2Id,
          on: true,
        );
        final marks = await repo.marks(_beaconId);
        expect(marks, hasLength(1));
        expect(marks.single.markerId, _voterId);
        expect(marks.single.targetId, _helper2Id);

        await repo.setMark(
          beaconId: _beaconId,
          markerId: _voterId,
          targetId: _helper2Id,
          on: false,
        );
        expect(await repo.marks(_beaconId), isEmpty);

        const body = 'Closure story body';
        await repo.saveStory(beaconId: _beaconId, body: body);
        expect(await repo.story(_beaconId), body);
      },
      skip: skipReason,
    );

    test(
      'insertResults and resultFor round-trip',
      () async {
        await repo.createEpoch(
          beaconId: _beaconId,
          epoch: 1,
          openedAt: DateTime.utc(2026, 3, 1),
          closesAt: DateTime.utc(2026, 3, 8),
        );
        await repo.setEpochStatus(
          beaconId: _beaconId,
          epoch: 1,
          status: ClosureEpochStatus.finalized,
          finalizedAt: DateTime.utc(2026, 3, 8),
          finalizeReason: 2,
        );

        await repo.insertResults(
          beaconId: _beaconId,
          epoch: 1,
          rows: const [
            ClosureResultInsert(
              userId: _helper1Id,
              outcome: ClosureOutcome.done,
              band: ClosureBand.raised,
              draftFlag: ClosureResultDraftFlag.none,
              helped: 0.42,
            ),
            ClosureResultInsert(
              userId: _helper2Id,
              outcome: ClosureOutcome.notDone,
              band: ClosureBand.none,
              draftFlag: ClosureResultDraftFlag.notCounted,
              helped: 0.0,
            ),
          ],
        );

        final row = await repo.resultFor(
          beaconId: _beaconId,
          userId: _helper1Id,
        );
        expect(row, isNotNull);
        expect(row!.epoch, 1);
        expect(row.outcome, ClosureOutcome.done);
        expect(row.band, ClosureBand.raised);
        expect(row.draftFlag, ClosureResultDraftFlag.none);
        expect(row.helped, closeTo(0.42, 1e-9));
      },
      skip: skipReason,
    );
  });

  group('ClosureRepository.selectArrivalEdge', () {
    const arrivalBeaconId = 'Bclrepoarrv01';
    const arrivalAuthorId = 'Uclrepoarrauth';
    const arrivalHelperId = 'Uclrepoarrhelp';
    final offerAt = DateTime.utc(2026, 4, 10, 12);

    setUp(() async {
      await writer.execute('''
DELETE FROM public.beacon_forward_edge WHERE beacon_id = '$arrivalBeaconId'
''');
      await writer.execute('''
DELETE FROM public.beacon WHERE id = '$arrivalBeaconId'
''');
      await writer.execute('''
DELETE FROM public."user" WHERE id LIKE 'Uclrepoarr%'
''');
      await _insertUser(writer, arrivalAuthorId, 5);
      await _insertUser(writer, arrivalHelperId, 6);
      await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES (
  '$arrivalBeaconId', '$arrivalAuthorId', 'arrival', '',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
''');
    });

    Future<void> insertEdge({
      required String id,
      required DateTime createdAt,
      DateTime? cancelledAt,
    }) async {
      // bfe_active_unique allows one active edge per
      // (beacon_id, sender_id, recipient_id): one sender per edge.
      final senderId = 'Uclrepoarrs${id.substring(id.length - 3)}';
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (
  '$senderId', '$senderId', '${senderId.padRight(44, 'k')}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
''');
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  @id, @beaconId, @senderId, @recipientId, @createdAt, @cancelledAt
)
ON CONFLICT (id) DO UPDATE SET
  created_at = EXCLUDED.created_at,
  cancelled_at = EXCLUDED.cancelled_at
'''),
        parameters: {
          'id': id,
          'beaconId': arrivalBeaconId,
          'senderId': senderId,
          'recipientId': arrivalHelperId,
          'createdAt': createdAt,
          'cancelledAt': cancelledAt,
        },
      );
    }

    test(
      'picks the latest edge strictly before the offer timestamp',
      () async {
        await insertEdge(
          id: 'Fclrepoarr001',
          createdAt: offerAt.subtract(const Duration(hours: 2)),
        );
        await insertEdge(
          id: 'Fclrepoarr002',
          createdAt: offerAt.subtract(const Duration(hours: 1)),
        );
        final edge = await repo.selectArrivalEdge(
          beaconId: arrivalBeaconId,
          helperId: arrivalHelperId,
          offerCreatedAt: offerAt,
        );
        expect(edge, isNotNull);
        expect(edge!.id, 'Fclrepoarr002');
      },
      skip: skipReason,
    );

    test(
      'ignores edges created after the offer',
      () async {
        await insertEdge(
          id: 'Fclrepoarr003',
          createdAt: offerAt.subtract(const Duration(minutes: 1)),
        );
        await insertEdge(
          id: 'Fclrepoarr004',
          createdAt: offerAt.add(const Duration(minutes: 1)),
        );
        final edge = await repo.selectArrivalEdge(
          beaconId: arrivalBeaconId,
          helperId: arrivalHelperId,
          offerCreatedAt: offerAt,
        );
        expect(edge?.id, 'Fclrepoarr003');
      },
      skip: skipReason,
    );

    test(
      'ignores edges cancelled at or before the offer',
      () async {
        await insertEdge(
          id: 'Fclrepoarr005',
          createdAt: offerAt.subtract(const Duration(hours: 1)),
          cancelledAt: offerAt,
        );
        await insertEdge(
          id: 'Fclrepoarr006',
          createdAt: offerAt.subtract(const Duration(hours: 2)),
          cancelledAt: offerAt.subtract(const Duration(minutes: 30)),
        );
        final edge = await repo.selectArrivalEdge(
          beaconId: arrivalBeaconId,
          helperId: arrivalHelperId,
          offerCreatedAt: offerAt,
        );
        expect(edge, isNull);
      },
      skip: skipReason,
    );

    test(
      'keeps edges cancelled after the offer timestamp',
      () async {
        await insertEdge(
          id: 'Fclrepoarr007',
          createdAt: offerAt.subtract(const Duration(hours: 1)),
          cancelledAt: offerAt.add(const Duration(hours: 1)),
        );
        final edge = await repo.selectArrivalEdge(
          beaconId: arrivalBeaconId,
          helperId: arrivalHelperId,
          offerCreatedAt: offerAt,
        );
        expect(edge?.id, 'Fclrepoarr007');
      },
      skip: skipReason,
    );

    test(
      'breaks equal created_at by id descending',
      () async {
        final createdAt = offerAt.subtract(const Duration(minutes: 5));
        await insertEdge(id: 'Fclrepoarr008', createdAt: createdAt);
        await insertEdge(id: 'Fclrepoarr009', createdAt: createdAt);
        final edge = await repo.selectArrivalEdge(
          beaconId: arrivalBeaconId,
          helperId: arrivalHelperId,
          offerCreatedAt: offerAt,
        );
        expect(edge?.id, 'Fclrepoarr009');
      },
      skip: skipReason,
    );
  });
}

Future<void> _truncateClosureTables(Connection writer) async {
  await writer.execute('''
TRUNCATE
  public.beacon_closure_result,
  public.beacon_closure_member,
  public.beacon_closure,
  public.beacon_closure_outcome,
  public.beacon_closure_author_split,
  public.beacon_closure_support,
  public.beacon_closure_commit,
  public.beacon_closure_mark,
  public.beacon_closure_story
CASCADE
''');
  await writer.execute('''
DELETE FROM public.beacon_forward_edge WHERE beacon_id = '$_beaconId'
''');
  await writer.execute('''
DELETE FROM public.beacon WHERE id = '$_beaconId'
''');
}

Future<void> _seedUsersAndBeacon(Connection writer) async {
  await _insertUser(writer, _authorId, 1);
  await _insertUser(writer, _helper1Id, 2);
  await _insertUser(writer, _helper2Id, 3);
  await _insertUser(writer, _helper3Id, 4);
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES (
  '$_beaconId', '$_authorId', 'closure repo test', '',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'Fclrepoedge01', '$_beaconId', '$_authorId', '$_helper1Id',
  '2026-01-01T00:00:01Z'
)
ON CONFLICT (id) DO NOTHING
''');
}

Future<void> _insertUser(Connection writer, String id, int slot) async {
  final key = pgTestPublicKey('clrepo', slot);
  await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', '$key', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
}
