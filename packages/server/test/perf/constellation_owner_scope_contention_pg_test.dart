@Tags(['perf', 'pg', 'mr'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/people_tag_consts.dart';
import 'package:tentura_server/data/database/postgres_serialization_retry.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    show QueryExecutor, QueryInterceptor, TenturaDb, TransactionExecutor;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/owner_graph_unit_of_work.dart';
import 'package:tentura_server/data/repository/people_tags_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import '../support/owner_graph_contention.dart';
import 'perf_report.dart';

const _anchorFixture = 'owner_scope_anchor_batch';
const _fieldFixture = 'owner_scope_field_read';
const _attemptBudget = 3;
const _timeBudgetMs = 5000;
const _tagOpsPerImport = 20;
const _anchorCalls = 100;
const _fieldCalls = 8;
const _anchorViewer = 'Uperfowner00';
const _unseenPerson = 'Uperfnewpeer';

typedef _AnchorCall = ({int attempts, double latencyMs, bool committed});
typedef _WriteState = ({int tagRows, int anchorOps, int anchorCursor});

double _milliseconds(Stopwatch clock) => clock.elapsedMicroseconds / 1000;

Map<String, double> _percentiles(List<double> samples) => {
  'p95': nearestRankPercentile(samples, 0.95),
  'p99': nearestRankPercentile(samples, 0.99),
};

void _report(String fixture, int calls, Map<String, Object?> contention) {
  stdout.writeln(
    jsonEncode({
      'fixture': fixture,
      'parameters': {
        'attemptBudget': _attemptBudget,
        'timeBudgetMs': _timeBudgetMs,
        'tagOpsPerImport': _tagOpsPerImport,
        'calls': calls,
      },
      'contention': contention,
    }),
  );
}

void _reportAnchorBudget(
  List<_AnchorCall> calls, {
  Map<String, Object?>? loadSanity,
}) {
  final distribution = <String, int>{};
  final samples = <Map<String, Object>>[];
  var withinBudget = 0;
  var exhausted = 0;
  for (final call in calls) {
    final qualifies =
        call.committed &&
        call.attempts <= _attemptBudget &&
        call.latencyMs <= _timeBudgetMs;
    if (qualifies) withinBudget++;
    if (!call.committed) exhausted++;
    distribution.update('${call.attempts}', (n) => n + 1, ifAbsent: () => 1);
    samples.add({
      'attempts': call.attempts,
      'latencyMs': call.latencyMs,
      'committed': call.committed,
      'withinBudget': qualifies,
    });
  }
  final ratio = withinBudget / calls.length;
  final retryRate = (calls.length - (distribution['1'] ?? 0)) / calls.length;
  _report(_anchorFixture, calls.length, {
    'calls': calls.length,
    'withinBudget': withinBudget,
    'budgetMisses': calls.length - withinBudget,
    'exhaustedCalls': exhausted,
    'retryRate': retryRate,
    'attemptDistribution': distribution,
    'callSamples': samples,
    'callLatencyMs': _percentiles([for (final call in calls) call.latencyMs]),
    'loadSanity': ?loadSanity,
  });
  String percent(double rate) => '${(rate * 100).toStringAsFixed(2)}%';
  expect(
    ratio,
    greaterThanOrEqualTo(0.99),
    reason:
        'Within-budget ratio ${percent(ratio)}, retry rate ${percent(retryRate)}',
  );
}

List<_AnchorCall> _parseReplay(String input) {
  final Object? decoded = jsonDecode(input);
  if (decoded is! List<Object?> || decoded.isEmpty) {
    throw const FormatException('Expected a non-empty list of anchor calls');
  }
  return [
    for (final call in decoded)
      if (call case {
        'attempts': final int attempts,
        'latencyMs': final num latencyMs,
        'committed': final bool committed,
      } when attempts > 0 && latencyMs.isFinite && latencyMs > 0)
        (
          attempts: attempts,
          latencyMs: latencyMs.toDouble(),
          committed: committed,
        )
      else
        throw FormatException('Invalid recorded anchor call', call),
  ];
}

final class _Probe {
  _Probe(this.directory);

  final String? directory;
  int _next = 0;

  Future<void> checkpoint(
    String fixture,
    String phase,
    String viewer, {
    int? iteration,
  }) async {
    final directory = this.directory;
    if (directory == null) return;
    final path = '$directory/${_next++}';
    final event = File('$path.tmp');
    await event.writeAsString(
      jsonEncode({
        'fixture': fixture,
        'phase': phase,
        'viewerId': viewer,
        if (iteration != null) ...{
          'iteration': iteration,
          'unseenPersonId': _unseenPerson,
        },
      }),
    );
    await event.rename('$path.json');
    final ack = File('$path.ack');
    final clock = Stopwatch()..start();
    while (!ack.existsSync()) {
      if (clock.elapsed >= ownerGraphWriteLimit) {
        throw TimeoutException('Waiting for the $fixture $phase observer');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

final class _Attempts extends QueryInterceptor {
  int begun = 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    begun++;
    return super.beginTransaction(parent);
  }
}

/// The Field snapshot and its first-seen write use separate connection scopes.
/// Only the latter tries the owner lock and can complete the write measurement.
final class _FirstSeenCommit extends QueryInterceptor {
  _FirstSeenCommit(this.committed);

  final Completer<double> committed;
  final _clock = Stopwatch();
  bool _firstSeen = false;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    _clock.start();
    return super.beginTransaction(parent);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('pg_try_advisory_xact_lock(')) _firstSeen = true;
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await super.commitTransaction(inner);
    if (_firstSeen) committed.complete(_milliseconds(_clock));
  }
}

void main() {
  final replay = Platform.environment['TENTURA_OWNER_SCOPE_BUDGET_SAMPLES'];
  if (replay != null) {
    test('recorded anchor calls meet the retry and latency budget', () {
      _reportAnchorBudget(_parseReplay(replay));
    });
    return;
  }

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_OWNER_SCOPE_CONTENTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_owner_scope_perf',
  );
  final probe = _Probe(Platform.environment['TENTURA_OWNER_SCOPE_PROBE_DIR']);
  final tagPeople = List.generate(_anchorCalls, (i) => 'Uperftag${1000 + i}');
  final fieldViewers = List.generate(
    _fieldCalls,
    (i) => 'Uperffield${100 + i}',
  );
  late Connection observer;
  late OwnerGraphUnitOfWork tagGraph;
  late PeopleTagsRepository tags;

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    observer = session.writer;
    final db = openDisposablePgDatabase(target);
    addTearDown(db.close);
    tagGraph = OwnerGraphUnitOfWork(db);
    tags = PeopleTagsRepository(db);
    await observer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT id, id, left(md5(id) || md5('owner-scope:' || id), 44)
FROM unnest(@ids::text[]) AS id
'''),
      parameters: {
        'ids': TypedValue(Type.textArray, [
          _anchorViewer,
          _unseenPerson,
          ...tagPeople,
          ...fieldViewers,
        ]),
      },
    );
    await observer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
SELECT v, @peer, 1 FROM unnest(@viewers::text[]) AS v
UNION ALL
SELECT @peer, v, 1 FROM unnest(@viewers::text[]) AS v
'''),
      parameters: {
        'peer': _unseenPerson,
        'viewers': TypedValue(Type.textArray, fieldViewers),
      },
    );
  });

  Future<PersonTag> createTag(String viewer) => tags.create(
    ownerId: viewer,
    clientOpId: 'create-tag',
    fingerprint: 'create-tag',
    name: 'Contacts',
    glyph: 'C',
  );

  Future<double> whileTagWriterHoldsScope({
    required String viewer,
    required String tagId,
    required Iterable<String> people,
    required Future<void> Function() whileHeld,
  }) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final held = Stopwatch();
    final writer = tagGraph.run({viewer}, viewer, (_) async {
      held.start();
      for (final person in people) {
        await tags.applyMembers(
          ownerId: viewer,
          clientOpId: 'tag-$person',
          fingerprint: 'add-$tagId-$person',
          ops: [
            PersonTagMemberOp(
              tagId: tagId,
              personId: person,
              add: true,
              source: kPersonTagSourceManual,
            ),
          ],
        );
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      }
    })..ignore();
    try {
      await Future.any([entered.future, writer]).timeout(ownerGraphWriteLimit);
      await whileHeld();
    } finally {
      release.complete();
      await writer.timeout(ownerGraphWriteLimit);
    }
    return _milliseconds(held);
  }

  Future<void> observeWait<T>(
    String fixture,
    String viewer,
    Future<T> pending, {
    required bool checkpoint,
    int? iteration,
  }) async {
    if (checkpoint && probe.directory != null) {
      await probe.checkpoint(fixture, 'waiting', viewer, iteration: iteration);
    } else {
      expect(await waitsForOwnerGraphScope(observer, viewer, pending), isTrue);
    }
  }

  Future<_WriteState> writeState(String viewer) async {
    final rows = await observer.execute(
      Sql.named('''
SELECT (SELECT count(*) FROM public.person_tag_member WHERE owner_id = @viewer),
       (SELECT count(*) FROM public.constellation_anchor_op_log WHERE viewer_id = @viewer),
       COALESCE((SELECT revision FROM public.constellation_anchor_cursor WHERE viewer_id = @viewer), 0)
'''),
      parameters: {'viewer': viewer},
    );
    if (rows.single case [final int tags, final int ops, final int cursor]) {
      return (tagRows: tags, anchorOps: ops, anchorCursor: cursor);
    }
    throw StateError('Expected tag, anchor op-log, and cursor counts');
  }

  Future<bool> firstSeen(String viewer) async => (await observer.execute(
    Sql.named('''
SELECT 1 FROM public.person_field_first_seen WHERE viewer_id = @viewer AND peer_id = @peer
'''),
    parameters: {'viewer': viewer, 'peer': _unseenPerson},
  )).isNotEmpty;

  test(
    'anchor batches meet their budget while people tags use the same scope',
    () async {
      final attempts = _Attempts();
      final db = TenturaDb(
        target.databaseEnv,
        scopeInterceptor: () => attempts,
      );
      addTearDown(db.close);
      final anchors = ConstellationAnchorRepository(db);
      final tag = await createTag(_anchorViewer);
      final before = await writeState(_anchorViewer);
      await probe.checkpoint(_anchorFixture, 'before', _anchorViewer);

      final calls = <_AnchorCall>[];
      var committedOps = 0;
      Future<_AnchorCall> apply(int index) async {
        final begun = attempts.begun;
        final clock = Stopwatch()..start();
        var committed = false;
        try {
          final result = await anchors
              .applyBatch(
                viewerId: _anchorViewer,
                ops: [
                  for (final (offset, person) in tagPeople.take(2).indexed)
                    AnchorApplyOp(
                      clientOpId: 'pin-$index-$offset',
                      kind: AnchorOpKind.upsert,
                      target: ConstellationAnchorTarget.person(person),
                      position: ConstellationAnchorPosition(
                        xUnits: (index % 10).toDouble(),
                        yUnits: offset.toDouble(),
                        coordinateSpaceVersion: 1,
                      ),
                    ),
                ],
              )
              .timeout(ownerGraphWriteLimit);
          clock.stop();
          for (final op in result.results) {
            expect(op.status, AnchorOpStatus.ok);
          }
          committedOps += result.results.length;
          committed = true;
        } on PostgresRetryDeadlineExceededException {
          clock.stop();
        } on PostgresSnapshotUnavailableException {
          clock.stop();
        } on ServerException catch (error) {
          if (error.code != '57014' &&
              !isPostgresDeadlockOrSerializationFailure(error)) {
            rethrow;
          }
          clock.stop();
        }
        return (
          attempts: attempts.begun - begun,
          latencyMs: _milliseconds(clock),
          committed: committed,
        );
      }

      // Drive one tag edit and one batch at a time per connection. Each batch
      // sees an actual concurrent mutation under its own viewer's lock.
      for (final (index, person) in tagPeople.indexed) {
        late Future<_AnchorCall> pending;
        await whileTagWriterHoldsScope(
          viewer: _anchorViewer,
          tagId: tag.id,
          people: [person],
          whileHeld: () {
            pending = apply(index)..ignore();
            return observeWait(
              _anchorFixture,
              _anchorViewer,
              pending,
              checkpoint: index == 0,
            );
          },
        );
        calls.add(await pending);
      }

      final after = await writeState(_anchorViewer);
      await probe.checkpoint(_anchorFixture, 'after', _anchorViewer);
      final load = {
        'overlappingCalls': calls.length,
        'tagOpsIssued': tagPeople.length,
        'tagRowsCommitted': after.tagRows - before.tagRows,
        'anchorOpsCommitted': committedOps,
        'anchorCursorAdvance': after.anchorCursor - before.anchorCursor,
        'anchorOpLogAdvance': after.anchorOps - before.anchorOps,
      };
      _reportAnchorBudget(calls, loadSanity: load);
      expect(load['tagRowsCommitted'], tagPeople.length);
      expect(load['anchorCursorAdvance'], committedOps);
      expect(load['anchorOpLogAdvance'], committedOps);
    },
  );

  test(
    'Field returns while its first-seen write waits for a 20-edit tag transaction',
    () async {
      var firstSeenCommit = Completer<double>();
      final db = TenturaDb(
        target.databaseEnv,
        scopeInterceptor: () => _FirstSeenCommit(firstSeenCommit),
      );
      addTearDown(db.close);
      final field = ConstellationFieldRepository(
        db,
        DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
      );
      final iterations = <Map<String, Object?>>[];
      final waitSamples = <double>[];
      final responseSamples = <double>[];
      var totalHoldMs = 0.0;

      for (final (index, viewer) in fieldViewers.indexed) {
        final tag = await createTag(viewer);
        final before = await writeState(viewer);
        expect(await firstSeen(viewer), isFalse);
        await probe.checkpoint(
          _fieldFixture,
          'before',
          viewer,
          iteration: index,
        );
        firstSeenCommit = Completer<double>();
        late Future<(ConstellationFieldSnapshot, double)> response;
        final holdMs = await whileTagWriterHoldsScope(
          viewer: viewer,
          tagId: tag.id,
          people: tagPeople.take(_tagOpsPerImport),
          whileHeld: () {
            final clock = Stopwatch()..start();
            response =
                field
                    .readSnapshot(
                      viewerId: viewer,
                      context: '',
                      params: (
                        filters: ConstellationFieldMembershipFilters.defaults,
                        projection: ConstellationProjection.full,
                      ),
                    )
                    .then((snapshot) => (snapshot, _milliseconds(clock)))
                  ..ignore();
            return observeWait(
              _fieldFixture,
              viewer,
              firstSeenCommit.future,
              checkpoint: true,
              iteration: index,
            );
          },
        );
        final (snapshot, responseMs) = await response.timeout(
          ownerGraphWriteLimit,
        );
        final waitMs = await firstSeenCommit.future.timeout(
          ownerGraphWriteLimit,
        );
        final person = snapshot.peers.singleWhere(
          (peer) => peer.id == _unseenPerson,
        );
        expect(await firstSeen(viewer), isTrue);
        final tagRows = (await writeState(viewer)).tagRows - before.tagRows;
        expect(tagRows, _tagOpsPerImport);
        await probe.checkpoint(
          _fieldFixture,
          'after',
          viewer,
          iteration: index,
        );
        totalHoldMs += holdMs;
        waitSamples.add(waitMs);
        responseSamples.add(responseMs);
        iterations.add({
          'viewerId': viewer,
          'unseenPersonId': _unseenPerson,
          'firstSeenBefore': null,
          'fieldReadSucceeded': true,
          'fieldPersonId': person.id,
          'waitedOnWriter': true,
          'firstSeenAfterWriterCommit': {
            'viewerId': viewer,
            'personId': person.id,
          },
          'tagRowsCommitted': tagRows,
          'firstSeenWaitMs': waitMs,
          'fieldResponseMs': responseMs,
          'writerHoldMs': holdMs,
        });
      }
      _report(_fieldFixture, iterations.length, {
        'iterations': iterations,
        'firstSeenWaitMs': _percentiles(waitSamples),
        'fieldResponseMs': _percentiles(responseSamples),
        'writerHoldMs': totalHoldMs,
      });
    },
  );
}
