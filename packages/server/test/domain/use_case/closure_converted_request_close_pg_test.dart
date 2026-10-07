@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_view.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/recording_beacon_hierarchy_outbox.dart';

const _authorId = 'Uclconvauth01';
const _beaconId = 'Bclconvbeac01';
const _helpers = ['Uclconvhelp01', 'Uclconvhelp02', 'Uclconvhelp03'];
const _roles = ['Driver', 'Cook', 'Host'];

/// Closing a converted Request whose helpers were carried over as admitted
/// room participants, offered, and were given roles but never went through
/// the acknowledge step.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CLOSURE_CONVERTED_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_closure_converted',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late ClosureRepository repo;
  late CommitmentRepository commitments;
  late HelpOfferRepository helpOffers;
  late BeaconRepository beacons;
  late ClosureCase closureCase;

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
      beacons = BeaconRepository(database);
      commitments = CommitmentRepository(database);
      helpOffers = HelpOfferRepository(database);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    setUp(() async {
      await _reset(writer);
      await _seed(writer);
      expect(
        (await beacons.getBeaconById(beaconId: _beaconId)).kind,
        BeaconKind.post,
      );
      await beacons.convertPostToRequest(
        beaconId: _beaconId,
        title: 'converted request',
        description: '',
        needs: null,
        primaryNeedSlug: null,
        startAt: null,
        endAt: null,
        isDiscoverable: false,
      );
      await beacons.convertPostMembers(
        beaconId: _beaconId,
        authorId: _authorId,
        helperIds: _helpers.toSet(),
      );
      expect(
        (await beacons.getBeaconById(beaconId: _beaconId)).kind,
        BeaconKind.request,
      );
      final participants = await writer.execute('''
SELECT user_id, room_access FROM public.beacon_participant
WHERE beacon_id = '$_beaconId' AND user_id <> '$_authorId'
''');
      expect(participants.map((p) => p[0]), unorderedEquals(_helpers));
      expect(
        participants.map((p) => p[1]),
        everyElement(RoomAccessBits.admitted),
      );
      // Conversion grants room access, without creating offers.
      expect(await helpOffers.fetchByBeaconId(_beaconId), isEmpty);
      closureCase = ClosureCase(
        unitOfWork: MutatingUnitOfWork(database),
        closureRepository: repo,
        beaconRepository: beacons,
        commitmentRepository: commitments,
        helpOfferRepository: helpOffers,
        hierarchyRepository: FakeBeaconHierarchyRepository(),
        lifecycleEffects: buildLifecycleEffectsCase(
          outbox: RecordingBeaconHierarchyOutbox(),
        ),
        attentionSystemSettlement: _Settlement(),
        receipts: _NoReceipts(),
        finalizer: _NoFinalizer(),
        env: Env(environment: Environment.test),
        logger: Logger('ClosureConvertedRequestCloseTest'),
      );
    });
  }

  /// Admitted room participant (as carried over by a conversion), then an
  /// active offer + role from the author, no acknowledgement.
  Future<void> offerWithRole(String helperId, String role) async {
    await helpOffers.upsert(beaconId: _beaconId, userId: helperId);
    await commitments.record(
      beaconId: _beaconId,
      userId: helperId,
      actorUserId: helperId,
      kind: CommitmentEventKind.offered,
    );
    await helpOffers.setRoleLabel(
      beaconId: _beaconId,
      offerUserId: helperId,
      actorUserId: _authorId,
      roleLabel: role,
    );
  }

  Future<void> offerWithoutRole(String helperId) async {
    await helpOffers.upsert(beaconId: _beaconId, userId: helperId);
    await commitments.record(
      beaconId: _beaconId,
      userId: helperId,
      actorUserId: helperId,
      kind: CommitmentEventKind.offered,
    );
  }

  Future<List<CommitmentEventKind>> kindsOf(String helperId) async => [
    for (final e in await commitments.eventsForPair(
      beaconId: _beaconId,
      userId: helperId,
    ))
      e.kind,
  ];

  group('closing a Request whose helpers all have assigned roles', () {
    test(
      'an open Request without an epoch still has no closure state or result',
      () async {
        await expectLater(
          closureCase.state(viewerId: _authorId, beaconId: _beaconId),
          throwsA(isA<IdNotFoundException>()),
        );
        await expectLater(
          closureCase.resultForViewer(viewerId: _authorId, beaconId: _beaconId),
          throwsA(isA<IdNotFoundException>()),
        );
      },
      skip: skipReason,
    );

    test(
      'a closed Request without an epoch has no closure view for non-authors',
      () async {
        await closureCase.close(authorId: _authorId, beaconId: _beaconId);
        await expectLater(
          closureCase.state(viewerId: _helpers[0], beaconId: _beaconId),
          throwsA(isA<IdNotFoundException>()),
        );
        await expectLater(
          closureCase.resultForViewer(
            viewerId: _helpers[0],
            beaconId: _beaconId,
          ),
          throwsA(isA<IdNotFoundException>()),
        );
      },
      skip: skipReason,
    );

    test(
      'close succeeds and leaves no epoch',
      () async {
        for (var i = 0; i < _helpers.length; i++) {
          await offerWithRole(_helpers[i], _roles[i]);
        }

        final offers = await helpOffers.fetchByBeaconId(_beaconId);
        expect(offers, hasLength(3));
        expect(
          offers.where((o) => o.roleLabel?.trim().isEmpty ?? true).length,
          0,
          reason: 'The close precheck has zero unsettled offers',
        );
        await closureCase.close(authorId: _authorId, beaconId: _beaconId);

        final r = await writer.execute(
          "SELECT status FROM public.beacon WHERE id = '$_beaconId'",
        );
        expect(r.single.single, BeaconStatus.closed.smallintValue);
        expect(await repo.latestEpoch(_beaconId), isNull);
        final view = await closureCase.state(
          viewerId: _authorId,
          beaconId: _beaconId,
        );
        expect(view.epoch, 0);
        expect(view.status, ClosureEpochStatus.finalized);
        expect(view.role, ClosureRole.author);
        expect(view.members, isEmpty);
        expect(view.canCloseNow, isFalse);
        expect(view.canReopen, isFalse);
        expect(
          await closureCase.resultForViewer(
            viewerId: _authorId,
            beaconId: _beaconId,
          ),
          isNull,
        );
        final closedOffers = await helpOffers.fetchByBeaconId(_beaconId);
        expect(closedOffers, hasLength(3));
        for (var i = 0; i < _helpers.length; i++) {
          final offer = closedOffers.singleWhere(
            (o) => o.userId == _helpers[i],
          );
          expect(offer.isActive, isTrue);
          expect(offer.roleLabel, _roles[i]);
          expect(
            await kindsOf(_helpers[i]),
            [CommitmentEventKind.offered],
          );
        }
      },
      skip: skipReason,
    );

    test(
      'a helper with an assigned role is not recorded as unanswered at close',
      () async {
        for (var i = 0; i < _helpers.length; i++) {
          await offerWithRole(_helpers[i], _roles[i]);
        }

        await closureCase.close(authorId: _authorId, beaconId: _beaconId);

        for (final h in _helpers) {
          expect(
            await kindsOf(h),
            isNot(contains(CommitmentEventKind.unansweredAtClose)),
            reason: '$h was given a role',
          );
        }
      },
      skip: skipReason,
    );

    test(
      'a helper without a role is still recorded as unanswered at close',
      () async {
        await offerWithRole(_helpers[0], _roles[0]);
        await offerWithoutRole(_helpers[1]);

        await closureCase.close(authorId: _authorId, beaconId: _beaconId);

        expect(
          await kindsOf(_helpers[1]),
          contains(CommitmentEventKind.unansweredAtClose),
        );
        expect(
          await kindsOf(_helpers[0]),
          isNot(contains(CommitmentEventKind.unansweredAtClose)),
        );
      },
      skip: skipReason,
    );

    test(
      'each helper offer keeps its assigned role and is not answered with '
      '"no answer" after close',
      () async {
        for (var i = 0; i < _helpers.length; i++) {
          await offerWithRole(_helpers[i], _roles[i]);
        }

        await closureCase.close(authorId: _authorId, beaconId: _beaconId);

        final offers = {
          for (final o in await helpOffers.fetchByBeaconId(_beaconId))
            o.userId: o,
        };
        for (var i = 0; i < _helpers.length; i++) {
          final offer = offers[_helpers[i]]!;
          expect(offer.isActive, isTrue);
          expect(offer.roleLabel, _roles[i]);
          expect(
            (await kindsOf(_helpers[i])).last,
            isNot(CommitmentEventKind.unansweredAtClose),
            reason: '${_helpers[i]} must not read as "no answer"',
          );
        }
      },
      skip: skipReason,
    );

    test(
      'closure state read right after a close without an epoch is a closed '
      'author state',
      () async {
        for (var i = 0; i < _helpers.length; i++) {
          await offerWithRole(_helpers[i], _roles[i]);
        }
        await closureCase.close(authorId: _authorId, beaconId: _beaconId);

        final view = await closureCase.state(
          viewerId: _authorId,
          beaconId: _beaconId,
        );

        expect(view.status, ClosureEpochStatus.finalized);
        expect(view.role, ClosureRole.author);
      },
      skip: skipReason,
    );

    test(
      'closure result read right after a close without an epoch does not '
      'throw for the author',
      () async {
        for (var i = 0; i < _helpers.length; i++) {
          await offerWithRole(_helpers[i], _roles[i]);
        }
        await closureCase.close(authorId: _authorId, beaconId: _beaconId);

        expect(
          await closureCase.resultForViewer(
            viewerId: _authorId,
            beaconId: _beaconId,
          ),
          isNull,
        );
      },
      skip: skipReason,
    );
  });
}

Future<void> _reset(Connection writer) async {
  await writer.execute('''
TRUNCATE
  public.beacon_closure_result, public.beacon_closure_member,
  public.beacon_closure, public.beacon_closure_outcome,
  public.beacon_closure_author_split, public.beacon_closure_support,
  public.beacon_closure_commit, public.beacon_closure_mark,
  public.beacon_closure_story
CASCADE
''');
  await writer.execute(
    "DELETE FROM public.beacon_commitment_event WHERE beacon_id = '$_beaconId'",
  );
  await writer.execute(
    "DELETE FROM public.beacon_help_offer WHERE beacon_id = '$_beaconId'",
  );
  await writer.execute("DELETE FROM public.beacon WHERE id = '$_beaconId'");
}

Future<void> _seed(Connection writer) async {
  final users = [_authorId, ..._helpers];
  for (var i = 0; i < users.length; i++) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${users[i]}', '${users[i]}', '${pgTestPublicKey('clconv', i + 1)}')
ON CONFLICT (id) DO NOTHING
''');
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, forward_policy, is_discoverable,
   published_at)
VALUES ('$_beaconId', '$_authorId', '', '', 1, 0, false, now())
''');
  for (var i = 0; i < _helpers.length; i++) {
    await writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id)
VALUES ('Fclconvmember$i', '$_beaconId', '$_authorId', '${_helpers[i]}')
''');
  }
}

final class _Settlement extends Fake implements AttentionSystemSettlementPort {
  @override
  Future<int> supersedeAuthorHelpOfferObligationsOnBeaconClose(
    String beaconId,
  ) async => 0;
}

final class _NoReceipts extends Fake implements ClosureReceiptsPort {}

final class _NoFinalizer extends Fake implements ClosureFinalizerPort {}
