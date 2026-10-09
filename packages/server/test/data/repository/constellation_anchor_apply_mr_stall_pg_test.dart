@Tags(['pg', 'mr'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Connection, ServerException;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/postgres_serialization_retry.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:test/test.dart';

import '../../support/constellation_profiles_from_public_records.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/meritrank_blackhole.dart';

/// An `applyBatch` whose MeritRank call never answers (a blackholed peer)
/// fails with a retryable error within the request budget and leaves the
/// connection reusable; a MeritRank that fails fast is retryable too, and is
/// never recorded as a rejection of the batch's ops.
///
/// Two stalls are covered, and they prove different things:
///  - a real blackhole: the MeritRank service is paused, so the pgmer2
///    connector inside `mr_mutual_scores` blocks in its receive wait. This is
///    the acceptance scenario; it needs docker control of the MeritRank
///    container. Where docker is unavailable it is skipped with the reason,
///    unless `TENTURA_PG_TESTS_REQUIRED=1`, which makes the suite fail to
///    load instead (so a required run can never pass without it).
///  - a backend stall: a `pg_sleep` inside the visibility function the batch
///    calls. It proves only that the transaction-local `statement_timeout`
///    bounds a blocking statement and that the cancel is surfaced as
///    retryable; it does NOT exercise the connector's wait.
///
/// Both stalls are injected by wrapping `public.person_visible_peers_symmetric`
/// (the connector-backed visibility function the batch computes visibility
/// with). That coupling is intentional; a counter that survives the batch's
/// rollback proves the wrapper was reached, so a batch that stops calling that
/// function fails the tests with a message saying so rather than for the wrong
/// reason.
///
/// The request budget is the interactive 5 s deadline of `applyBatch`
/// (`withMutatingRepeatableRead`'s default); no repository member is read for
/// it.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_APPLY_MR_STALL_TEST_DB',
    defaultNamePrefix: 'tentura_test_apply_mr_stall',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  const viewer = 'Ustallviewer0001';
  const peer = 'Ustallpeer000001';
  const params = AnchorApplyParams(
    context: kConstellationContext,
    filters: ConstellationFieldMembershipFilters.defaults,
  );
  const budget = Duration(seconds: 5);
  final (blackhole, blackholeSkip) = await MeritRankBlackhole.probe();
  // The stall outlasts the budget by far, so only a cancel at the budget can
  // end it early.
  final stallSeconds = budget.inSeconds + 3;

  late DisposablePgWriterSession fixture;
  late Connection backend;
  late TenturaDb db;
  late ConstellationAnchorRepository repository;

  final ops = [
    AnchorApplyOp(
      clientOpId: 'pin-after-stall',
      kind: AnchorOpKind.upsert,
      target: ConstellationAnchorTarget.person(peer),
      position: const ConstellationAnchorPosition(
        xUnits: 2,
        yUnits: -3,
        coordinateSpaceVersion: 1,
      ),
      ifRevision: ConstellationAnchorRevision.zero,
    ),
  ];

  Future<AnchorApplyBatchResult> apply() =>
      repository.applyBatch(viewerId: viewer, ops: ops, params: params);

  Future<int> statementTimeoutMs() async {
    final row = await db.customSelect('''
SELECT (extract(epoch FROM current_setting('statement_timeout')::interval)
        * 1000)::bigint AS ms
''').getSingle();
    return row.read<int>('ms');
  }

  Future<int> visibilityComputations() async {
    final row = (await fixture.writer.execute(
      'SELECT CASE WHEN is_called THEN last_value ELSE 0 END '
      'FROM public.apply_mr_stall_entries',
    )).single;
    return (row.single! as num).toInt();
  }

  Future<void> expectNothingRecorded() async {
    final logs = await fixture.writer.execute(
      'SELECT count(*) FROM public.constellation_anchor_op_log',
    );
    final anchors = await fixture.writer.execute(
      'SELECT count(*) FROM public.constellation_anchor',
    );
    expect(logs.single.single, 0, reason: 'No op may be logged.');
    expect(anchors.single.single, 0, reason: 'No anchor may be written.');
  }

  Future<int> backendPid() async =>
      (await db.customSelect('SELECT pg_backend_pid() AS pid').getSingle())
          .read<int>('pid');

  setUpAll(() async {
    fixture = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    backend = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    db = TenturaDb.forTest(
      database: PgDatabase.opened(backend, enableMigrations: false),
    );
    repository = ConstellationAnchorRepository(db, _Profiles(db));
    final writer = fixture.writer;
    // `sleep` blocks the visibility function, `fail` makes it raise at once
    // the way a connector error does; no row means it behaves normally.
    await writer.execute(
      'CREATE TABLE public.apply_mr_stall (mode text NOT NULL)',
    );
    // A sequence is not rolled back with the batch's transaction, so it counts
    // the visibility computations even of a batch that fails.
    await writer.execute('CREATE SEQUENCE public.apply_mr_stall_entries');
    await writer.execute('''
CREATE TABLE public.apply_mr_stall_seen_timeout (
  timeout_ms bigint NOT NULL
)
''');
    await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
RENAME TO apply_mr_stall_visible_impl
''');
    await writer.execute('''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE plpgsql VOLATILE AS \$probe\$
DECLARE
  _mode text := (SELECT mode FROM public.apply_mr_stall LIMIT 1);
BEGIN
  PERFORM nextval('public.apply_mr_stall_entries');
  INSERT INTO public.apply_mr_stall_seen_timeout
  VALUES ((extract(epoch FROM current_setting('statement_timeout')::interval)
           * 1000)::bigint);
  IF _mode = 'sleep' THEN
    PERFORM pg_sleep($stallSeconds);
  ELSIF _mode = 'fail' THEN
    RAISE EXCEPTION 'meritrank connector: call failed' USING ERRCODE = 'XX000';
  END IF;
  RETURN QUERY SELECT s.peer_id
  FROM public.apply_mr_stall_visible_impl(viewer_id, ctx) s;
END;
\$probe\$
''');
  });

  tearDownAll(() async {
    await db.close();
    if (backend.isOpen) await backend.close();
    await tearDownDisposablePgWriter(session: fixture);
  });

  setUp(() async {
    final writer = fixture.writer;
    await writer.execute('DELETE FROM public.apply_mr_stall');
    await writer.execute('DELETE FROM public.apply_mr_stall_seen_timeout');
    await writer.execute(
      "SELECT setval('public.apply_mr_stall_entries', 1, false)",
    );
    await writer.execute('DELETE FROM public.constellation_anchor_op_log');
    await writer.execute('DELETE FROM public.constellation_anchor');
    await writer.execute(
      'DELETE FROM public.constellation_anchor_target_watermark',
    );
    await writer.execute('DELETE FROM public.constellation_anchor_cursor');
    await writer.execute('DELETE FROM public.user_block');
    await writer.execute('DELETE FROM public.vote_user');
    await writer.execute('DELETE FROM public."user"');
    for (final id in [viewer, peer]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    }
    await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$peer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$peer', '$viewer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    await writer.execute('SELECT public.mr_reset()');
    for (final (src, dst) in [(viewer, peer), (peer, viewer)]) {
      await writer.execute('''
SELECT public.mr_put_edge('$src', '$dst', 0.75::double precision, '${params.context}', 0)
''');
    }
    await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES ('$viewer')
''');
  });

  group('applyBatch request budget', () {
    test(
      'runs with a statement_timeout equal to the apply request budget',
      () async {
        final connectionWide = await statementTimeoutMs();
        expect(
          connectionWide,
          isNot(budget.inMilliseconds),
          reason: 'The fixture connection must not already carry the budget.',
        );
        final result = await apply();
        expect(result.results.single.status, AnchorOpStatus.ok);

        final seen = await fixture.writer.execute(
          'SELECT DISTINCT timeout_ms FROM public.apply_mr_stall_seen_timeout',
        );
        expect(
          seen.map((row) => (row.single! as num).toInt()),
          [budget.inMilliseconds],
          reason:
              'Every visibility computation of the batch transaction '
              'must see current_setting(statement_timeout) == the budget.',
        );
        expect(
          await statementTimeoutMs(),
          connectionWide,
          reason: 'The budget is transaction-local (SET LOCAL).',
        );
      },
    );

    Future<void> expectRetryableWithinBudget({
      required Future<void> Function() stall,
      required Future<void> Function() recover,
    }) async {
      final pidBefore = await backendPid();

      final clock = Stopwatch();
      Object? failure;
      await stall();
      try {
        clock.start();
        await apply();
      } on Object catch (error) {
        failure = error;
      } finally {
        clock.stop();
        await recover();
      }

      expect(
        await visibilityComputations(),
        greaterThanOrEqualTo(1),
        reason:
            'The batch never reached public.person_visible_peers_symmetric, '
            'so the stall was not exercised: this test injects its stall '
            'there on purpose (see the file comment).',
      );
      expect(
        failure,
        isNotNull,
        reason: 'The stalled apply must fail, not wait out the stall.',
      );
      expect(
        clock.elapsed,
        lessThanOrEqualTo(budget + const Duration(milliseconds: 100)),
      );
      expect(failure, _isRetryableStatementCancel);

      // Degraded MeritRank is never a recorded rejection or a partial write.
      await expectNothingRecorded();

      // The connection is reusable: same backend, no transaction left behind,
      // and the same request succeeds once MeritRank answers again.
      expect(backend.isOpen, isTrue);
      expect(await backendPid(), pidBefore);
      final recovered = await apply();
      expect(recovered.results.single.status, AnchorOpStatus.ok);
      expect(recovered.beforeRevision, ConstellationAnchorRevision.zero);
    }

    test(
      'a blackholed MeritRank service during apply ends in a retryable error '
      'within the budget plus 100 ms and leaves the connection reusable',
      () async {
        final hole = blackhole!;
        addTearDown(hole.release);
        await expectRetryableWithinBudget(
          stall: hole.engage,
          recover: hole.release,
        );
      },
      skip: blackholeSkip,
      timeout: Timeout(budget * 3 + const Duration(seconds: 60)),
    );

    test(
      'a blocking backend statement during apply is cancelled at the budget '
      'as a retryable error and leaves the connection reusable',
      () async {
        await expectRetryableWithinBudget(
          stall: () => fixture.writer.execute(
            "INSERT INTO public.apply_mr_stall VALUES ('sleep')",
          ),
          recover: () =>
              fixture.writer.execute('DELETE FROM public.apply_mr_stall'),
        );
      },
      timeout: Timeout(budget * 3 + const Duration(seconds: 30)),
    );
  });

  group('applyBatch with a degraded MeritRank', () {
    test(
      'a MeritRank call that fails fast is a retryable error, not a recorded '
      'rejection, and a later apply succeeds',
      () async {
        await fixture.writer.execute(
          "INSERT INTO public.apply_mr_stall VALUES ('fail')",
        );
        Object? failure;
        AnchorApplyBatchResult? result;
        try {
          result = await apply();
        } on Object catch (error) {
          failure = error;
        }

        expect(
          result,
          isNull,
          reason: 'A degraded MeritRank must not produce a batch result '
              '(a rejected op would be recorded as final).',
        );
        expect(failure, _isRetryable);
        expect(await visibilityComputations(), greaterThanOrEqualTo(1));
        await expectNothingRecorded();

        await fixture.writer.execute('DELETE FROM public.apply_mr_stall');
        final recovered = await apply();
        expect(recovered.results.single.status, AnchorOpStatus.ok);
      },
    );

    test(
      'a peer MeritRank genuinely does not show the viewer is a recorded '
      'rejection, unlike a degraded MeritRank',
      () async {
        await fixture.writer.execute('DELETE FROM public.vote_user');
        await fixture.writer.execute('SELECT public.mr_reset()');

        final result = await apply();

        expect(result.results.single.status, AnchorOpStatus.rejected);
        final logs = await fixture.writer.execute(
          'SELECT count(*) FROM public.constellation_anchor_op_log',
        );
        expect(logs.single.single, 1);
      },
    );
  });
}

/// The causes a batch failure carries through the retry wrappers, outermost
/// first.
Iterable<Object> _causes(Object error) sync* {
  Object? current = error;
  while (current != null) {
    yield current;
    current = switch (current) {
      PostgresSnapshotUnavailableException(:final cause) => cause,
      PostgresRetryDeadlineExceededException(:final cause) => cause,
      _ => null,
    };
  }
}

final Matcher _isTypedRetryLater = isA<ConstellationException>().having(
  (e) => e.code,
  'code',
  isA<ConstellationExceptionCodes>().having(
    (c) => c.exceptionCode,
    'exceptionCode',
    ConstellationExceptionCode.retryLater,
  ),
);

/// The retryable-error contract of an apply whose MeritRank failed: a typed
/// RETRY_LATER, or the retry-the-whole-transaction signal of
/// `withMutatingRepeatableRead`. A raw database error does not qualify.
final Matcher _isRetryable = anyOf(
  _isTypedRetryLater,
  isA<PostgresSnapshotUnavailableException>(),
  isA<PostgresRetryDeadlineExceededException>(),
);

/// The contract of an apply whose MeritRank never answers: the batch
/// transaction's statement was cancelled at the request budget (SQLSTATE
/// 57014, query_canceled) and that is surfaced as retryable - either the typed
/// RETRY_LATER or a retry signal that keeps the cancellation as its cause. A
/// deadlock or serialization failure is not a cancellation at the budget.
final Matcher _isRetryableStatementCancel = anyOf(
  _isTypedRetryLater,
  allOf(
    _isRetryable,
    predicate<Object>(
      (error) => _causes(error).any(
        (cause) => cause is ServerException && cause.code == '57014',
      ),
      'a retryable error caused by a 57014 statement cancellation',
    ),
  ),
);

final class _Profiles implements UserProfileBatchLookup {
  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) => constellationProfilesFromRecords(this, ids);

  _Profiles(this.db);

  final TenturaDb db;

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async {
    final users = await db.managers.users
        .filter((u) => u.id.isIn(ids.toSet()))
        .get();
    return {
      for (final u in users)
        u.id: UserEntity(id: u.id, displayName: u.displayName),
    };
  }

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async {
    final users = await userEntitiesByIds(ids);
    return {
      for (final u in users.values)
        u.id: UserPublicRecord(
          id: u.id,
          displayName: u.displayName,
          description: u.description,
          isMutualFriend: reciprocalPeerIds.contains(u.id),
          subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(u.id),
          userAvailability: null,
        ),
    };
  }
}
