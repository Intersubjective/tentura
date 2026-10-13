@Tags(['pg'])
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/user_erasure_test_stack.dart';

/// Publishing a draft Request takes the lock sequence hierarchy scope → beacon
/// row and checks the draft status only after holding both, so it cannot
/// deadlock against deletion/erasure (hierarchy → beacon) and an overlapping
/// duplicate publish is a no-op for every caller but the one that transitions.
/// Every race waits until the backends are observed blocked on the held lock
/// before the lock is released, so the overlap is proven, not assumed.
const _author = 'Upublocklauth1';
const _draft = 'Bpublockdraft1';
const _childDraft = 'Bpublockchild1';
const _statusDraft = 3;
const _budget = Duration(seconds: 10);
const _hierarchyLock =
    "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))";

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_PUBLISH_LOCK_ORDER_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_publish_lock',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Request publication locking', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    // One pooled connection per TenturaDb: separate databases give each side
    // of a race its own connection.
    late TenturaDb dbA;
    late TenturaDb dbB;
    late BeaconRepository repoA;
    late BeaconRepository repoB;
    late int pidA;
    late int pidB;
    late BeaconCase deleteCase;
    late UserErasureCase erasureCase;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      dbA = openDisposablePgDatabase(target);
      dbB = openDisposablePgDatabase(target);
      repoA = BeaconRepository(dbA);
      repoB = BeaconRepository(dbB);
      pidA = await _backendPid(dbA);
      pidB = await _backendPid(dbB);

      final env = Env(environment: Environment.test);
      final logger = Logger('BeaconPublishLockOrderPgTest');
      final uow = MutatingUnitOfWork(dbB);
      final attention = TransactionalAttentionCase(
        uow,
        AttentionDispatchRepository(dbB, logger),
      );
      final lifecycle = BeaconLifecycleEffectsCase(
        BeaconHierarchyOutboxRepository(dbB),
        env: env,
        logger: logger,
      );
      deleteCase = BeaconCase(
        BeaconRepository(dbB),
        _UnusedImages(),
        _UnusedImageGc(),
        _UnusedTasks(),
        CommitmentQueryCase(
          CommitmentRepository(dbB),
          HelpOfferRepository(dbB),
          env: env,
          logger: logger,
        ),
        BeaconAccessRepository(dbB),
        BeaconHierarchyRepository(dbB),
        FakeBeaconChildCreatePort(),
        lifecycle,
        attention: attention,
        env: env,
        logger: logger,
      );
      erasureCase = buildUserErasureTestStack(
        db: dbB,
        userRepository: buildDefaultUserRepository(dbB),
        lifecycleEffects: lifecycle,
        attention: attention,
      ).erasureCase;

      // Records every status write, so "one transition" is observable.
      await writer.execute('''
CREATE TABLE public.publish_probe_status_write (
  seq bigserial PRIMARY KEY,
  beacon_id text NOT NULL,
  old_status smallint,
  new_status smallint
)
''');
      await writer.execute('''
CREATE FUNCTION public.publish_probe_status_write_fn() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  INSERT INTO public.publish_probe_status_write (beacon_id, old_status, new_status)
  VALUES (OLD.id, OLD.status, NEW.status);
  RETURN NEW;
END;
\$\$
''');
      await writer.execute('''
CREATE TRIGGER publish_probe_status_write_trg
AFTER UPDATE OF status ON public.beacon
FOR EACH ROW EXECUTE FUNCTION public.publish_probe_status_write_fn()
''');
    });

    setUp(() async {
      await _resetFixture(writer);
      // A scope that ends in a non-database error (e.g. the not-found
      // BeaconCreateException) closes its connection, so re-read the backends.
      pidA = await _backendPid(dbA);
      pidB = await _backendPid(dbB);
    });

    tearDownAll(() async {
      await dbB.close();
      await tearDownDisposablePgWriter(session: session, drift: dbA);
    });

    Future<Connection> holderWithHierarchyLock() async {
      final holder = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      addTearDown(holder.close);
      await holder.execute('BEGIN');
      await holder.execute(_hierarchyLock);
      return holder;
    }

    for (final child in [false, true]) {
      final label = child ? 'child draft' : 'draft';
      final id = child ? _childDraft : _draft;
      Future<BeaconEntity> publish(BeaconRepository r) => child
          ? r.publishChildDraft(childBeaconId: id, actorId: _author)
          : r.publishDraft(id: id, actorId: _author);

      test(
        'a $label publish waiting for the hierarchy lock holds no row lock '
        'on the beacon',
        () async {
          final holder = await holderWithHierarchyLock();
          final done = publish(repoA);
          unawaited(done.then<void>((_) {}, onError: (_) {}));
          await _waitForLockWait(writer, pidA);

          // Fails with lock_not_available while publish already holds the row.
          await writer.execute(
            "SELECT 1 FROM public.beacon WHERE id = '$id' FOR UPDATE NOWAIT",
          );

          await holder.execute('COMMIT');
          await done.timeout(_budget);
        },
      );

      test(
        'a $label publish queued behind BeaconCase.deleteById does not '
        'deadlock and then reports the Request as not found',
        () async {
          final holder = await holderWithHierarchyLock();
          final deletion = _settle(
            deleteCase.deleteById(beaconId: id, userId: _author),
          );
          await _waitForLockWait(writer, pidB);
          final publication = _settle(publish(repoA));
          await _waitForLockWait(writer, pidA);
          await holder.execute('COMMIT');

          final outcomes = await Future.wait([
            deletion,
            publication,
          ]).timeout(_budget);
          _expectNoDeadlock(outcomes);
          expect(outcomes[0].error, isNull, reason: 'deletion succeeds');
          expect(
            outcomes[1].error,
            isA<BeaconCreateException>(),
            reason: 'publish after a committed deletion reports not found',
          );
          expect(await _beaconExists(writer, id), isFalse);
        },
      );

      test(
        'a $label publish queued behind account erasure does not deadlock '
        'and then reports the Request as not found',
        () async {
          final holder = await holderWithHierarchyLock();
          final erasure = _settle(erasureCase.deleteById(id: _author));
          await _waitForLockWait(writer, pidB);
          final publication = _settle(publish(repoA));
          await _waitForLockWait(writer, pidA);
          await holder.execute('COMMIT');

          final outcomes = await Future.wait([
            erasure,
            publication,
          ]).timeout(_budget);
          _expectNoDeadlock(outcomes);
          expect(outcomes[0].error, isNull, reason: 'erasure succeeds');
          expect(
            outcomes[1].error,
            isA<BeaconCreateException>(),
            reason: 'publish after a committed erasure reports not found',
          );
          expect(await _beaconExists(writer, id), isFalse);
        },
      );

      test(
        'two overlapping $label publishes make one draft-to-open transition, '
        'one published_at and one publication event',
        () async {
          final holder = await holderWithHierarchyLock();
          final first = _settle(publish(repoA));
          await _waitForLockWait(writer, pidA);
          final second = _settle(publish(repoB));
          await _waitForLockWait(writer, pidB);
          await holder.execute('COMMIT');

          final outcomes = await Future.wait([
            first,
            second,
          ]).timeout(_budget);
          _expectNoDeadlock(outcomes);
          for (final o in outcomes) {
            expect(o.error, isNull);
          }

          final writes = await writer.execute('''
SELECT old_status, new_status FROM public.publish_probe_status_write
WHERE beacon_id = '$id'
''');
          expect(
            [for (final r in writes) (r[0], r[1])],
            [(_statusDraft, BeaconStatus.open.smallintValue)],
            reason: 'exactly one status write, and it is draft to open',
          );

          final row = (await writer.execute(
            "SELECT status, published_at FROM public.beacon WHERE id = '$id'",
          )).single;
          expect(row[0], BeaconStatus.open.smallintValue);
          final stamp = row[1]! as DateTime;
          for (final o in outcomes) {
            final entity = o.value! as BeaconEntity;
            expect(entity.status, BeaconStatus.open);
            expect(entity.publishedAt?.toUtc(), stamp.toUtc());
          }

          final events = (await writer.execute('''
SELECT count(*) FROM public.beacon_activity_event
WHERE beacon_id = '$id'
  AND type = ${BeaconActivityEventTypeBits.beaconPublished}
''')).single.single! as int;
          expect(events, 1);
        },
      );
    }
  });
}

typedef _Outcome = ({Object? error, Object? value});

Future<_Outcome> _settle(Future<Object?> action) async {
  try {
    return (error: null, value: await action);
  } on Object catch (error) {
    return (error: error, value: null);
  }
}

void _expectNoDeadlock(List<_Outcome> outcomes) {
  for (final o in outcomes) {
    final isDeadlock =
        (o.error is ServerException &&
            (o.error! as ServerException).code == '40P01') ||
        '${o.error}'.toLowerCase().contains('deadlock');
    expect(isDeadlock, isFalse, reason: 'deadlock_detected: ${o.error}');
  }
}

Future<bool> _beaconExists(Connection writer, String id) async =>
    (await writer.execute(
      "SELECT 1 FROM public.beacon WHERE id = '$id'",
    )).isNotEmpty;

Future<int> _backendPid(TenturaDb db) async {
  final row = await db
      .customSelect('SELECT pg_backend_pid() AS pid')
      .getSingle();
  return row.read<int>('pid');
}

/// Waits until backend [pid] is blocked on a heavyweight lock, so a race only
/// proceeds once that side is provably queued behind the held lock.
Future<void> _waitForLockWait(Connection writer, int pid) async {
  final deadline = DateTime.now().add(_budget);
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      'SELECT 1 FROM pg_stat_activity '
      "WHERE pid = $pid AND wait_event_type = 'Lock'",
    );
    if (rows.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('backend $pid never blocked on a lock');
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE public.beacon_activity_event, public.beacon, public."user",
  public.publish_probe_status_write
CASCADE
''');
  await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_author', '$_author', 'pk-$_author')
''');
  for (final id in [_draft, _childDraft]) {
    await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  is_discoverable)
VALUES ('$id', '$_author', 'T', '', $_statusDraft, 0, true)
''');
  }
}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}
