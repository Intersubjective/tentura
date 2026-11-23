@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/postgres_serialization_retry.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/user_erasure_test_stack.dart';

const _deadlock = '40P01';
const _serializationFailure = '40001';
const _uniqueViolation = '23505';

// Leave room for the project's five-second bounded retry and local DB work.
const _callTimeout = Duration(seconds: 8);

typedef _Account = ({
  String id,
  String request,
  String draftImage,
  String? requestImage,
  String avatar,
});

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_USER_ERASURE_RETRY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_erasure_retry',
  );
  final skip = await pgSkipReason(target);

  group('Account erasure against Postgres', () {
    DisposablePgWriterSession? session;
    TenturaDb? db;
    late _ErasureFixture fixture;
    late UserErasureCase erasure;

    setUpAll(() async {
      final pg = session = await setUpDisposablePgWriter(target: target);
      final database = db = openDisposablePgDatabase(target);
      fixture = _ErasureFixture(pg.writer);
      await fixture.installFault();
      final logger = Logger('UserErasureTransactionRetryPgTest');
      erasure = buildUserErasureTestStack(
        db: database,
        userRepository: buildDefaultUserRepository(database),
        lifecycleEffects: BeaconLifecycleEffectsCase(
          BeaconHierarchyOutboxRepository(database),
          env: Env(environment: Environment.test),
          logger: logger,
        ),
        attention: TransactionalAttentionCase(
          MutatingUnitOfWork(database),
          AttentionDispatchRepository(database, logger),
        ),
      ).erasureCase;
    });

    tearDownAll(() async {
      if (session case final pg?) {
        await tearDownDisposablePgWriter(session: pg, drift: db);
      }
    });

    Future<bool> erase(_Account account) =>
        erasure.deleteById(id: account.id).timeout(_callTimeout);

    test('a deadlock replays the whole small account erasure once', () async {
      final account = await fixture.seedAccount();
      await fixture.arm(account, _deadlock);

      expect(await erase(account), isTrue);

      expect(await fixture.attempts(), 2);
      expect(await fixture.draftDeletes(), 2);
      expect(await fixture.lifecycleWrites(), 2);
      await fixture.expectErased(account);
    });

    test(
      'small account erasure rolls back a unique violation and retries a '
      'serialization failure',
      () async {
        final account = await fixture.seedAccount();
        final requests = await fixture.ownedRequests(account);
        expect(requests, hasLength(2));
        await fixture.arm(account, _uniqueViolation);

        await expectLater(
          erase(account),
          throwsA(_hasSqlState(_uniqueViolation)),
        );

        expect(await fixture.attempts(), 1);
        expect(await fixture.ownedRequests(account), requests);
        expect(await fixture.userRow(account), [
          [account.avatar],
        ]);
        expect(await fixture.cleanupJobs(account), isEmpty);

        await fixture.arm(account, _serializationFailure);
        expect(await erase(account), isTrue);

        expect(await fixture.attempts(), 2);
        await fixture.expectErased(account);
      },
    );

    test(
      'small account erasure stops retrying and rolls back every attempt',
      () async {
        final account = await fixture.seedAccount();
        final requests = await fixture.ownedRequests(account);
        await fixture.arm(account, _deadlock, everyAttempt: true);

        await expectLater(erase(account), throwsA(_hasSqlState(_deadlock)));

        final attempts = await fixture.attempts();
        expect(await fixture.userRow(account), [
          [account.avatar],
        ]);
        expect(await fixture.ownedRequests(account), requests);
        expect(await fixture.cleanupJobs(account), isEmpty);
        expect(await fixture.draftDeletes(), attempts);
        expect(await fixture.lifecycleWrites(), attempts);

        await fixture.disarm();
        expect(await erase(account), isTrue);
        await fixture.expectErased(account);

        expect(attempts, greaterThan(1), reason: 'retry budget');
      },
    );

    test(
      'chunked erasure propagates a unique violation and retries a deadlock '
      'only in the final transaction',
      () async {
        final rejected = await fixture.seedAccount(drafts: 201);
        await fixture.arm(rejected, _uniqueViolation);

        await expectLater(
          erase(rejected),
          throwsA(_hasSqlState(_uniqueViolation)),
        );

        expect(await fixture.attempts(), 1);
        expect(await fixture.userRow(rejected), [
          [rejected.avatar],
        ]);

        final account = await fixture.seedAccount(drafts: 201);
        await fixture.arm(account, _deadlock);
        expect(await erase(account), isTrue);

        expect(await fixture.attempts(), 2);
        expect(await fixture.draftDeletes(), 2, reason: 'the two draft chunks');
        expect(await fixture.lifecycleWrites(), 1, reason: 'the Request chunk');
        expect(
          await fixture.gcWrites(),
          3,
          reason: 'one draft cleanup enqueue and two avatar enqueue attempts',
        );
        await fixture.expectErased(account);
      },
    );

    test(
      'exhausting final-step retries preserves committed chunks for a later '
      'erasure',
      () async {
        final account = await fixture.seedAccount(drafts: 201);
        await fixture.arm(account, _deadlock, everyAttempt: true);

        await expectLater(erase(account), throwsA(_hasSqlState(_deadlock)));

        final attempts = await fixture.attempts();
        expect(await fixture.userRow(account), [
          [account.avatar],
        ]);
        expect(await fixture.drafts(account), isEmpty);
        expect(await fixture.cleanupJobs(account), [
          [account.draftImage, account.id],
        ]);
        expect(await fixture.draftDeletes(), 2);
        expect(await fixture.lifecycleWrites(), 1);
        expect(await fixture.gcWrites(), 1 + attempts);

        await fixture.disarm();
        expect(await erase(account), isTrue);
        await fixture.expectErased(account);

        expect(
          attempts,
          greaterThan(1),
          reason: 'final transaction retry budget',
        );
      },
    );
  }, skip: skip);
}

Matcher _hasSqlState(String expected) => isA<Object>().having(
  (error) {
    final cause = error is PostgresRetryDeadlineExceededException
        ? error.cause
        : error;
    return cause is ServerException ? cause.code : null;
  },
  'Postgres SQLSTATE',
  expected,
);

final class _ErasureFixture {
  _ErasureFixture(this.writer);

  final Connection writer;
  var _users = 0;

  static const _userDeletes = 'erasure_user_delete_attempts';
  static const _draftDeletes = 'erasure_draft_delete_statements';
  static const _lifecycleWrites = 'erasure_lifecycle_insert_attempts';
  static const _gcWrites = 'erasure_gc_insert_attempts';
  static const _counters = [
    _userDeletes,
    _draftDeletes,
    _lifecycleWrites,
    _gcWrites,
  ];

  Future<void> installFault() async {
    for (final counter in _counters) {
      await writer.execute('CREATE SEQUENCE public.$counter');
    }
    await writer.execute('''
CREATE TABLE public.erasure_fault (
  user_id text PRIMARY KEY, sqlstate text NOT NULL, every_attempt boolean NOT NULL
)
''');
    // A deferred trigger fails after the other writes have run. Sequence
    // increments survive rollback so the test can observe failed attempts.
    await writer.execute('''
CREATE FUNCTION public.fail_erasure() RETURNS trigger LANGUAGE plpgsql AS \$\$
DECLARE
  fault public.erasure_fault%ROWTYPE;
  attempt bigint;
BEGIN
  SELECT * INTO fault FROM public.erasure_fault WHERE user_id = OLD.id;
  IF FOUND THEN
    attempt := nextval('public.$_userDeletes');
    IF attempt = 1 OR fault.every_attempt THEN
      RAISE EXCEPTION USING ERRCODE = fault.sqlstate,
        MESSAGE = 'test account erasure failure';
    END IF;
  END IF;
  RETURN OLD;
END;
\$\$;
CREATE CONSTRAINT TRIGGER fail_erasure
AFTER DELETE ON public."user" DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.fail_erasure();
CREATE FUNCTION public.count_erasure_write() RETURNS trigger LANGUAGE plpgsql AS \$\$
BEGIN
  PERFORM nextval(TG_ARGV[0]::regclass);
  RETURN NEW;
END;
\$\$;
CREATE TRIGGER count_erasure_draft_delete
BEFORE DELETE ON public.beacon FOR EACH STATEMENT
EXECUTE FUNCTION public.count_erasure_write('public.$_draftDeletes');
CREATE TRIGGER count_erasure_lifecycle_insert
BEFORE INSERT ON public.beacon_activity_event FOR EACH ROW
WHEN (NEW.type = ${BeaconActivityEventTypeBits.beaconLifecycleChanged})
EXECUTE FUNCTION public.count_erasure_write('public.$_lifecycleWrites');
CREATE TRIGGER count_erasure_gc_insert
BEFORE INSERT ON public.image_object_gc FOR EACH ROW
EXECUTE FUNCTION public.count_erasure_write('public.$_gcWrites');
''', queryMode: QueryMode.simple);
  }

  Future<void> arm(
    _Account account,
    String sqlState, {
    bool everyAttempt = false,
  }) async {
    await disarm();
    for (final counter in _counters) {
      await writer.execute('ALTER SEQUENCE public.$counter RESTART');
    }
    await query(
      'INSERT INTO public.erasure_fault VALUES (@id, @state, @every)',
      {'id': account.id, 'state': sqlState, 'every': everyAttempt},
    );
  }

  Future<void> disarm() async {
    await writer.execute('DELETE FROM public.erasure_fault');
  }

  Future<int> attempts() => _count(_userDeletes);
  Future<int> draftDeletes() => _count(_draftDeletes);
  Future<int> lifecycleWrites() => _count(_lifecycleWrites);
  Future<int> gcWrites() => _count(_gcWrites);

  Future<int> _count(String sequence) async =>
      (await writer.execute(
            'SELECT CASE WHEN is_called THEN last_value ELSE 0 END FROM public.$sequence',
          )).single.single!
          as int;

  Future<_Account> seedAccount({int drafts = 1}) => writer.runTx((tx) async {
    final slot = ++_users;
    final id = 'Ueraser${slot.toString().padLeft(6, '0')}';
    final request = 'Br$id';
    final draftPrefix = 'Bd$id';
    Future<Result> seed(String sql, Map<String, Object?> values) =>
        tx.execute(Sql.named(sql), parameters: values);

    await seed(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @id, @key)',
      {'id': id, 'key': pgTestPublicKey('erasure-retry', slot)},
    );
    await seed(
      '''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES (@request, @id, 'Request', 'Published details', @open, now())
''',
      {'request': request, 'id': id, 'open': BeaconStatus.open.smallintValue},
    );
    await seed(
      '''
INSERT INTO public.beacon (id, user_id, title, description, status)
SELECT @prefix || n::text, @id, 'Draft', 'Draft details', @draft
FROM generate_series(1, @drafts::int) AS n
''',
      {
        'prefix': draftPrefix,
        'id': id,
        'draft': BeaconStatus.draft.smallintValue,
        'drafts': drafts,
      },
    );
    Future<String> newImage() async =>
        (await seed(
              'INSERT INTO public.image (author_id) VALUES (@id) RETURNING id::text',
              {'id': id},
            )).single.single!
            as String;

    Future<String> attachCover(String beacon) async {
      final image = await newImage();
      await seed(
        'INSERT INTO public.beacon_image (beacon_id, image_id) '
        'VALUES (@id, @image::uuid)',
        {'image': image, 'id': beacon},
      );
      await seed(
        'UPDATE public.beacon SET cover_image_id = @image::uuid WHERE id = @id',
        {'image': image, 'id': beacon},
      );
      return image;
    }

    final draftImage = await attachCover('${draftPrefix}1');
    final requestImage = drafts == 1 ? await attachCover(request) : null;
    final avatar = await newImage();
    await seed(
      'UPDATE public."user" SET image_id = @image::uuid WHERE id = @id',
      {'image': avatar, 'id': id},
    );
    return (
      id: id,
      request: request,
      draftImage: draftImage,
      requestImage: requestImage,
      avatar: avatar,
    );
  });

  Future<Result> query(String sql, Map<String, Object?> values) =>
      writer.execute(Sql.named(sql), parameters: values);

  Future<Result> userRow(_Account account) => query(
    'SELECT image_id::text FROM public."user" WHERE id = @id',
    {'id': account.id},
  );

  Future<Result> drafts(_Account account) => query(
    'SELECT id FROM public.beacon WHERE id LIKE @prefix',
    {'prefix': 'Bd${account.id}%'},
  );

  Future<Result> ownedRequests(_Account account) => query(
    'SELECT id, status, title, description, cover_image_id::text, published_at '
    'FROM public.beacon WHERE user_id = @id ORDER BY id',
    {'id': account.id},
  );

  Future<Result> cleanupJobs(_Account account) => query(
    'SELECT image_id::text, author_id FROM public.image_object_gc '
    'WHERE author_id = @id',
    {'id': account.id},
  );

  Future<void> expectErased(_Account account) async {
    expect(await userRow(account), isEmpty);
    expect(await drafts(account), isEmpty);
    expect(
      await cleanupJobs(account),
      unorderedEquals([
        [account.draftImage, account.id],
        [account.avatar, account.id],
        if (account.requestImage case final image?) [image, account.id],
      ]),
    );

    final request = {'id': account.request};
    const open = BeaconStatus.open;
    const deleted = BeaconStatus.deleted;
    expect(
      await query(
        'SELECT status, user_id, cover_image_id FROM public.beacon WHERE id = @id',
        request,
      ),
      [
        [deleted.smallintValue, null, null],
      ],
    );
    expect(
      await query('''
SELECT (diff->>'fromStatus')::int, (diff->>'toStatus')::int, diff->>'reason'
FROM public.beacon_activity_event
WHERE beacon_id = @id AND type = ${BeaconActivityEventTypeBits.beaconLifecycleChanged}
''', request),
      [
        [
          open.smallintValue,
          deleted.smallintValue,
          BeaconLifecycleChangeReason.deleted,
        ],
      ],
    );
    expect(
      await query('''
SELECT from_status, to_status
FROM public.beacon_hierarchy_events WHERE source_beacon_id = @id
''', request),
      [
        [open.smallintValue, deleted.smallintValue],
      ],
    );
  }
}
