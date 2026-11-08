@Tags(['pg'])
library;

import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _owner = 'Ugetbyidowner01';
const _stranger = 'Ugetbyidstranger1';
const _ghostAuthor = 'Ugetbyidghost001';
const _request = 'Bgetbyidrequest01';
const _post = 'Bgetbyidpost00001';
const _missing = 'Bgetbyidmissing001';
const _orphanAuthor = 'Bgetbyidghostauth1';
const _deletedNoOwner = 'Bgetbyiddeleted001';
const _openNoOwner = 'Bgetbyidnoowner001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_GET_BY_ID_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_get_by_id',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('BeaconRepository.getBeaconById on a real database', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late BeaconRepository beacons;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      database = openDisposablePgDatabase(target);
      beacons = BeaconRepository(database);
      final writer = session.writer;
      for (final (i, id) in [_owner, _stranger].indexed) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', '${pgTestPublicKey('getbyid', i + 1)}')
''');
      }
      await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_request', '$_owner', 'A request', 'Needs a hand', 0)
''');
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_owner', '', '', 0, 1, 1, false, now())
''');
      // A beacon whose author row is gone while user_id still points at it
      // (the foreign key is bypassed on purpose to build the broken row).
      // Needs a superuser connection (session_replication_role); the test
      // database is disposable, so the writer is one.
      await writer.execute('SET session_replication_role = replica');
      await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_orphanAuthor', '$_ghostAuthor', 'Orphan', 'No author row', 0)
''');
      await writer.execute('SET session_replication_role = DEFAULT');
      // Schema dependency: a live ownerless beacon is normally refused by the
      // `beacon_owner_or_deleted_ck` check; the branch that reports it still
      // exists, so lift the check in this throwaway DB. If the constraint is
      // renamed this fails here, not in the behaviour under test.
      await writer.execute(
        'ALTER TABLE public.beacon DROP CONSTRAINT beacon_owner_or_deleted_ck',
      );
      await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES
  ('$_deletedNoOwner', NULL, 'Gone', '', ${BeaconStatus.deleted.smallintValue}),
  ('$_openNoOwner', NULL, 'Ownerless', '', 0)
''');
    });

    tearDownAll(() async {
      await database.close();
      await tearDownDisposablePgWriter(session: session);
    });

    // The typed exception (never Drift's StateError from `getSingle`) carrying
    // the requested id in its default `Id not found: [<id>]` description.
    Matcher notFoundFor(String id) => isA<IdNotFoundException>()
        .having((e) => e.code.codeNumber, 'wire code', 1002)
        .having((e) => e.description, 'names the id', 'Id not found: [$id]');

    test(
      'an id with no beacon row is a typed not-found, not a StateError',
      () async {
        await expectLater(
          beacons.getBeaconById(beaconId: _missing),
          throwsA(notFoundFor(_missing)),
        );
      },
    );

    test('a beacon that exists but is not owned by the filter user is a '
        'typed not-found, not a StateError', () async {
      await expectLater(
        beacons.getBeaconById(beaconId: _request, filterByUserId: _stranger),
        throwsA(notFoundFor(_request)),
      );
    });

    test('a beacon whose author row is missing is a typed not-found, '
        'not a StateError', () async {
      await expectLater(
        beacons.getBeaconById(beaconId: _orphanAuthor),
        throwsA(notFoundFor(_orphanAuthor)),
      );
    });

    test('locking a missing beacon for a state change is a typed not-found '
        'and never runs the change', () async {
      var ran = false;
      await expectLater(
        beacons.runInBeaconStateTransaction<void>(
          beaconId: _missing,
          userId: _owner,
          fn: (_) async {
            ran = true;
          },
        ),
        throwsA(notFoundFor(_missing)),
      );
      expect(ran, isFalse);
    });

    test(
      'locking an existing Request hands the change the locked Request',
      () async {
        final lockedId = await beacons.runInBeaconStateTransaction<String>(
          beaconId: _request,
          userId: _owner,
          fn: (locked) async => locked.id,
        );
        expect(lockedId, _request);
      },
    );

    test('an existing Request still loads with its author', () async {
      final beacon = await beacons.getBeaconById(beaconId: _request);
      expect(beacon.id, _request);
      expect(beacon.kind, BeaconKind.request);
      expect(beacon.author.id, _owner);
      expect(beacon.images, isEmpty);
    });

    test('an existing Post still loads with its author', () async {
      final beacon = await beacons.getBeaconById(beaconId: _post);
      expect(beacon.id, _post);
      expect(beacon.kind, BeaconKind.post);
      expect(beacon.author.id, _owner);
      expect(beacon.images, isEmpty);
    });

    test("the owner filter still finds the owner's own beacon", () async {
      final beacon = await beacons.getBeaconById(
        beaconId: _request,
        filterByUserId: _owner,
      );
      expect(beacon.id, _request);
    });

    test('a deleted beacon with no owner is still structural-only', () async {
      await expectLater(
        beacons.getBeaconById(beaconId: _deletedNoOwner),
        throwsA(isA<BeaconStructuralOnlyException>()),
      );
    });

    test('a live beacon with no owner is still a not-found naming the '
        'missing owner', () async {
      await expectLater(
        beacons.getBeaconById(beaconId: _openNoOwner),
        throwsA(
          isA<IdNotFoundException>().having(
            (e) => e.description,
            'description',
            'Request owner missing for [$_openNoOwner]',
          ),
        ),
      );
    });
  });
}
