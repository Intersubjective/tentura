@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/closure/author_split.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_exception.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/recording_beacon_hierarchy_outbox.dart';

const _authorId = 'Uclwrauth0001';
const _outsiderId = 'Uclwroutsd001';
const _beaconId = 'Bclwrbeac0001';
final _finalizedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);

/// Helper ids `Uclwrhelp0101` … `Uclwrhelp0122`.
String _h(int i) => 'Uclwrhelp01${i.toString().padLeft(2, '0')}';

/// A13: author and voter writes (Arch §5.4 write rules, §7 closure* rows).
///
/// The write API under test (all through `_inClosureTx` with `expectedEpoch`):
/// `saveOutcome`, `saveAuthorSplit`, `toggleSupport` (returns the released
/// target id or null), `done`, `skip`, `setMark`, `saveStory`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CLOSURE_WRITES_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_closure_writes',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late ClosureRepository repo;
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
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    setUp(() async {
      await _reset(writer);
      await _seed(writer);
      closureCase = ClosureCase(
        unitOfWork: MutatingUnitOfWork(database),
        closureRepository: repo,
        beaconRepository: BeaconRepository(database),
        commitmentRepository: CommitmentRepository(database),
        helpOfferRepository: HelpOfferRepository(database),
        hierarchyRepository: FakeBeaconHierarchyRepository(),
        lifecycleEffects: buildLifecycleEffectsCase(
          outbox: RecordingBeaconHierarchyOutbox(),
        ),
        attentionSystemSettlement: _NoSettlement(),
        receipts: _NoReceipts(),
        finalizer: _NoFinalizer(),
        env: Env(environment: Environment.test),
        logger: Logger('ClosureCaseWritesTest'),
      );
    });
  }

  /// Epoch 1 over [helpers] (all voters unless listed in [nonVoters]).
  Future<void> openEpoch(
    List<String> helpers, {
    Set<String> nonVoters = const {},
    bool finalized = false,
  }) async {
    await repo.createEpoch(
      beaconId: _beaconId,
      epoch: 1,
      openedAt: DateTime.timestamp().subtract(const Duration(days: 1)),
      closesAt: DateTime.timestamp().add(const Duration(days: 6)),
    );
    await repo.insertMembers(
      beaconId: _beaconId,
      epoch: 1,
      members: [
        for (final h in helpers)
          ClosureMemberInsert(
            userId: h,
            activeAtOpen: !nonVoters.contains(h),
          ),
      ],
    );
    if (finalized) {
      await repo.setEpochStatus(
        beaconId: _beaconId,
        epoch: 1,
        status: ClosureEpochStatus.finalized,
        finalizedAt: _finalizedAt,
        finalizeReason: FinalizeReason.authorCloseNow.dbValue,
      );
    }
  }

  Future<void> answerAll(List<String> helpers) async {
    for (final h in helpers) {
      await repo.saveOutcome(
        beaconId: _beaconId,
        helperId: h,
        outcome: ClosureOutcome.done,
      );
    }
  }

  Future<Set<String>> draft(String voter) async => {
    for (final s in await repo.supports(
      beaconId: _beaconId,
      version: ClosureSupportVersion.draft,
    ))
      if (s.voterId == voter) s.targetId,
  };

  Future<Set<String>> committed(String voter) async => {
    for (final s in await repo.supports(
      beaconId: _beaconId,
      version: ClosureSupportVersion.committed,
    ))
      if (s.voterId == voter) s.targetId,
  };

  Matcher closureError(ClosureExceptionCode code) => throwsA(
    isA<ClosureException>().having((e) => e.closureCode, 'closureCode', code),
  );

  Matcher anyClosureError() => throwsA(isA<ClosureException>());

  group('ClosureCase writes: toggleSupport', () {
    test('U56: all others supported releases the earliest press', () async {
      final a = _h(1);
      final b = _h(2);
      final c = _h(3);
      await openEpoch([a, b, c]);

      final first = await closureCase.toggleSupport(
        voterId: a,
        beaconId: _beaconId,
        expectedEpoch: 1,
        targetId: b,
        on: true,
      );
      expect(first, isNull);
      final released = await closureCase.toggleSupport(
        voterId: a,
        beaconId: _beaconId,
        expectedEpoch: 1,
        targetId: c,
        on: true,
      );

      expect(released, b);
      expect(await draft(a), {c});
    }, skip: skipReason);

    test(
      'pressed_at of an existing row is kept when toggled on again',
      () async {
        final helpers = [_h(1), _h(2), _h(3), _h(4)];
        await openEpoch(helpers);
        Future<void> press() => closureCase.toggleSupport(
          voterId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: helpers[1],
          on: true,
        );

        await press();
        final before = (await repo.supports(
          beaconId: _beaconId,
          version: ClosureSupportVersion.draft,
        )).single.pressedAt;
        // Push the stored press into the past so an implementation that
        // rewrites pressed_at (e.g. ON CONFLICT DO UPDATE) is observable.
        final old = DateTime.utc(2026, 1, 1, 12);
        await writer.execute(
          "UPDATE public.beacon_closure_support SET pressed_at = '${old.toIso8601String()}' "
          "WHERE beacon_id = '$_beaconId'",
        );
        await press();
        final after = (await repo.supports(
          beaconId: _beaconId,
          version: ClosureSupportVersion.draft,
        )).single.pressedAt;

        expect(before, isNot(old));
        expect(after.toUtc(), old);
      },
      skip: skipReason,
    );

    test('off deletes the draft row', () async {
      final helpers = [_h(1), _h(2), _h(3), _h(4)];
      await openEpoch(helpers);
      await closureCase.toggleSupport(
        voterId: helpers[0],
        beaconId: _beaconId,
        expectedEpoch: 1,
        targetId: helpers[1],
        on: true,
      );
      final released = await closureCase.toggleSupport(
        voterId: helpers[0],
        beaconId: _beaconId,
        expectedEpoch: 1,
        targetId: helpers[1],
        on: false,
      );

      expect(released, isNull);
      expect(await draft(helpers[0]), isEmpty);
    }, skip: skipReason);

    test('a non-voter cannot toggle', () async {
      final helpers = [_h(1), _h(2), _h(3), _h(4)];
      await openEpoch(helpers, nonVoters: {helpers[3]});

      await expectLater(
        closureCase.toggleSupport(
          voterId: helpers[3],
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: helpers[0],
          on: true,
        ),
        closureError(ClosureExceptionCode.notVoter),
      );
      await expectLater(
        closureCase.toggleSupport(
          voterId: _outsiderId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: helpers[0],
          on: true,
        ),
        closureError(ClosureExceptionCode.notVoter),
      );
      expect(
        await repo.supports(
          beaconId: _beaconId,
          version: ClosureSupportVersion.draft,
        ),
        isEmpty,
      );
    }, skip: skipReason);

    test('with two members nobody can toggle', () async {
      final helpers = [_h(1), _h(2)];
      await openEpoch(helpers);

      await expectLater(
        closureCase.toggleSupport(
          voterId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: helpers[1],
          on: true,
        ),
        anyClosureError(),
      );
      expect(
        await repo.supports(
          beaconId: _beaconId,
          version: ClosureSupportVersion.draft,
        ),
        isEmpty,
      );
    }, skip: skipReason);

    test('target must be another member; stale epoch is rejected', () async {
      final helpers = [_h(1), _h(2), _h(3)];
      await openEpoch(helpers);

      await expectLater(
        closureCase.toggleSupport(
          voterId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: helpers[0],
          on: true,
        ),
        anyClosureError(),
      );
      await expectLater(
        closureCase.toggleSupport(
          voterId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: _authorId,
          on: true,
        ),
        anyClosureError(),
      );
      await expectLater(
        closureCase.toggleSupport(
          voterId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 2,
          targetId: helpers[1],
          on: true,
        ),
        closureError(ClosureExceptionCode.staleEpoch),
      );
    }, skip: skipReason);
  });

  group('ClosureCase writes: done and skip', () {
    test('done copies the latest draft; later edits leave version 1', () async {
      final helpers = [_h(1), _h(2), _h(3), _h(4)];
      final me = helpers[0];
      Future<void> toggle(String t, {required bool on}) =>
          closureCase.toggleSupport(
            voterId: me,
            beaconId: _beaconId,
            expectedEpoch: 1,
            targetId: t,
            on: on,
          );
      await openEpoch(helpers);

      await toggle(helpers[1], on: true);
      await closureCase.done(
        voterId: me,
        beaconId: _beaconId,
        expectedEpoch: 1,
      );
      expect(await committed(me), {helpers[1]});
      expect(await draft(me), {helpers[1]});

      // Edit the draft, then Done again: version 1 is replaced by the latest.
      await toggle(helpers[2], on: true);
      await toggle(helpers[1], on: false);
      expect(await draft(me), {helpers[2]});
      expect(await committed(me), {helpers[1]});
      await closureCase.done(
        voterId: me,
        beaconId: _beaconId,
        expectedEpoch: 1,
      );

      expect(await committed(me), {helpers[2]});
      expect(await draft(me), {helpers[2]});
      final commit = (await repo.commits(_beaconId)).single;
      expect(commit.voterId, me);

      await toggle(helpers[3], on: true);
      expect(await committed(me), {helpers[2]});
      expect(await draft(me), {helpers[2], helpers[3]});
    }, skip: skipReason);

    test('skip drops version 1 and records the commit row', () async {
      final helpers = [_h(1), _h(2), _h(3), _h(4)];
      final me = helpers[0];
      await openEpoch(helpers);
      await closureCase.toggleSupport(
        voterId: me,
        beaconId: _beaconId,
        expectedEpoch: 1,
        targetId: helpers[1],
        on: true,
      );
      await closureCase.done(
        voterId: me,
        beaconId: _beaconId,
        expectedEpoch: 1,
      );

      await closureCase.skip(
        voterId: me,
        beaconId: _beaconId,
        expectedEpoch: 1,
      );

      expect(await committed(me), isEmpty);
      expect((await repo.commits(_beaconId)).map((c) => c.voterId), [me]);
    }, skip: skipReason);

    test('done by a non-voter is rejected', () async {
      final helpers = [_h(1), _h(2), _h(3)];
      await openEpoch(helpers, nonVoters: {helpers[2]});

      await expectLater(
        closureCase.done(
          voterId: helpers[2],
          beaconId: _beaconId,
          expectedEpoch: 1,
        ),
        closureError(ClosureExceptionCode.notVoter),
      );
      expect(await repo.commits(_beaconId), isEmpty);
    }, skip: skipReason);
  });

  group('ClosureCase writes: outcome and split', () {
    test('saveOutcome notDone renormalizes a custom split (E7)', () async {
      final helpers = [_h(1), _h(2), _h(3)];
      await openEpoch(helpers);
      await answerAll(helpers);
      await repo.replaceSplit(_beaconId, {
        helpers[0]: 50,
        helpers[1]: 30,
        helpers[2]: 20,
      });

      await closureCase.saveOutcome(
        authorId: _authorId,
        beaconId: _beaconId,
        expectedEpoch: 1,
        helperId: helpers[1],
        outcome: ClosureOutcome.notDone,
      );

      final expected = renormalize(
        current: {helpers[0]: 50, helpers[1]: 30, helpers[2]: 20},
        newA: {helpers[0], helpers[2]},
        beaconId: _beaconId,
      )!;
      expect(expected.keys.toSet(), {helpers[0], helpers[2]});
      expect(await repo.split(_beaconId), expected);
      final outcomes = await repo.outcomes(_beaconId);
      expect(
        outcomes.singleWhere((o) => o.helperId == helpers[1]).outcome,
        ClosureOutcome.notDone,
      );
    }, skip: skipReason);

    test('saveOutcome without a split writes no split rows', () async {
      final helpers = [_h(1), _h(2), _h(3)];
      await openEpoch(helpers);

      await closureCase.saveOutcome(
        authorId: _authorId,
        beaconId: _beaconId,
        expectedEpoch: 1,
        helperId: helpers[0],
        outcome: ClosureOutcome.done,
      );

      expect(await repo.split(_beaconId), isEmpty);
    }, skip: skipReason);

    test('saveOutcome is author-only and members-only', () async {
      final helpers = [_h(1), _h(2), _h(3)];
      await openEpoch(helpers);

      await expectLater(
        closureCase.saveOutcome(
          authorId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 1,
          helperId: helpers[1],
          outcome: ClosureOutcome.done,
        ),
        closureError(ClosureExceptionCode.notAuthor),
      );
      await expectLater(
        closureCase.saveOutcome(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          helperId: _outsiderId,
          outcome: ClosureOutcome.done,
        ),
        closureError(ClosureExceptionCode.notMember),
      );
    }, skip: skipReason);

    test('saveAuthorSplit stores a valid split; null deletes it', () async {
      final helpers = [_h(1), _h(2)];
      await openEpoch(helpers);
      await answerAll(helpers);

      await closureCase.saveAuthorSplit(
        authorId: _authorId,
        beaconId: _beaconId,
        expectedEpoch: 1,
        split: {helpers[0]: 70, helpers[1]: 30},
      );
      expect(await repo.split(_beaconId), {helpers[0]: 70, helpers[1]: 30});

      await expectLater(
        closureCase.saveAuthorSplit(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          split: {helpers[0]: 70, helpers[1]: 20},
        ),
        closureError(ClosureExceptionCode.invalidSplit),
      );
      expect(await repo.split(_beaconId), {helpers[0]: 70, helpers[1]: 30});

      await closureCase.saveAuthorSplit(
        authorId: _authorId,
        beaconId: _beaconId,
        expectedEpoch: 1,
        split: null,
      );
      expect(await repo.split(_beaconId), isEmpty);
    }, skip: skipReason);

    Future<void> answerMixed(List<String> helpers) async {
      // Done, can't judge and unanswered (no row) all belong to A.
      for (var i = 0; i < helpers.length; i++) {
        if (i % 3 == 2) continue;
        await repo.saveOutcome(
          beaconId: _beaconId,
          helperId: helpers[i],
          outcome: i % 3 == 0 ? ClosureOutcome.done : ClosureOutcome.cantJudge,
        );
      }
    }

    test('a split with 21 members in A is splitTooLarge', () async {
      // 22 epoch members; the notDone one is outside A, so |A| == 21.
      final helpers = [for (var i = 1; i <= 22; i++) _h(i)];
      final a = helpers.take(21).toList();
      await openEpoch(helpers);
      await answerMixed(a);
      await repo.saveOutcome(
        beaconId: _beaconId,
        helperId: helpers[21],
        outcome: ClosureOutcome.notDone,
      );

      await expectLater(
        closureCase.saveAuthorSplit(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          split: {for (final h in a) h: 5},
        ),
        closureError(ClosureExceptionCode.splitTooLarge),
      );
      expect(await repo.split(_beaconId), isEmpty);
    }, skip: skipReason);

    test('22 members with 20 in A is not splitTooLarge', () async {
      // Counting epoch members instead of A would wrongly reject this.
      final helpers = [for (var i = 1; i <= 22; i++) _h(i)];
      final a = helpers.take(20).toList();
      await openEpoch(helpers);
      await answerMixed(a);
      for (final h in helpers.skip(20)) {
        await repo.saveOutcome(
          beaconId: _beaconId,
          helperId: h,
          outcome: ClosureOutcome.notDone,
        );
      }

      await closureCase.saveAuthorSplit(
        authorId: _authorId,
        beaconId: _beaconId,
        expectedEpoch: 1,
        split: {for (final h in a) h: 5},
      );

      expect(await repo.split(_beaconId), {for (final h in a) h: 5});
    }, skip: skipReason);
  });

  group('ClosureCase writes: story', () {
    test('trims, deletes on empty and rejects over 2000 chars', () async {
      await openEpoch([_h(1), _h(2)]);

      await closureCase.saveStory(
        authorId: _authorId,
        beaconId: _beaconId,
        expectedEpoch: 1,
        body: '  we did it  ',
      );
      expect(await repo.story(_beaconId), 'we did it');

      await expectLater(
        closureCase.saveStory(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          body: 'x' * 2001,
        ),
        throwsA(anything),
      );
      expect(await repo.story(_beaconId), 'we did it');

      await closureCase.saveStory(
        authorId: _authorId,
        beaconId: _beaconId,
        expectedEpoch: 1,
        body: '   ',
      );
      expect(await repo.story(_beaconId), isNull);
    }, skip: skipReason);
  });

  group('ClosureCase writes: setMark', () {
    const markedKind = 3;

    Future<List<_LedgerRow>> ledger() => _ledger(writer);

    test('evaluating epoch writes the mark row only', () async {
      final helpers = [_h(1), _h(2), _h(3)];
      await openEpoch(helpers);

      await closureCase.setMark(
        userId: helpers[0],
        beaconId: _beaconId,
        expectedEpoch: 1,
        targetId: helpers[1],
        on: true,
      );

      final marks = await repo.marks(_beaconId);
      expect(marks.map((m) => (m.markerId, m.targetId)), [
        (helpers[0], helpers[1]),
      ]);
      expect(await ledger(), isEmpty);

      await closureCase.setMark(
        userId: helpers[0],
        beaconId: _beaconId,
        expectedEpoch: 1,
        targetId: helpers[1],
        on: false,
      );
      expect(await repo.marks(_beaconId), isEmpty);
    }, skip: skipReason);

    test('the author may mark members; self and outsiders may not', () async {
      final helpers = [_h(1), _h(2)];
      await openEpoch(helpers);

      await closureCase.setMark(
        userId: _authorId,
        beaconId: _beaconId,
        expectedEpoch: 1,
        targetId: helpers[0],
        on: true,
      );
      expect((await repo.marks(_beaconId)).single.markerId, _authorId);

      await expectLater(
        closureCase.setMark(
          userId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: helpers[0],
          on: true,
        ),
        anyClosureError(),
      );
      await expectLater(
        closureCase.setMark(
          userId: _outsiderId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: helpers[0],
          on: true,
        ),
        closureError(ClosureExceptionCode.notMember),
      );
      await expectLater(
        closureCase.setMark(
          userId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: _outsiderId,
          on: true,
        ),
        closureError(ClosureExceptionCode.notMember),
      );
    }, skip: skipReason);

    test(
      'after finalize: evidence dated finalized_at; off retracts; on unretracts',
      () async {
        final helpers = [_h(1), _h(2), _h(3)];
        await openEpoch(helpers, finalized: true);
        const key = 'closure:$_beaconId:1:mark:Uclwrhelp0101:Uclwrhelp0102';
        Future<void> mark({required bool on}) => closureCase.setMark(
          userId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: helpers[1],
          on: on,
        );

        await mark(on: true);

        var rows = await ledger();
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row.sourceKey, key);
        expect(row.kind, markedKind);
        expect(row.count, 1);
        expect(row.subject, helpers[0]);
        expect(row.object, helpers[1]);
        expect(row.occurredAt, _finalizedAt);
        expect(row.retractedAt, isNull);
        expect(
          (await repo.marks(_beaconId)).map((m) => (m.markerId, m.targetId)),
          [(helpers[0], helpers[1])],
        );

        await mark(on: false);
        rows = await ledger();
        expect(rows, hasLength(1));
        expect(rows.single.id, row.id);
        expect(rows.single.retractedAt, isNotNull, reason: 'off retracts');
        expect(await repo.marks(_beaconId), isEmpty);

        await mark(on: true);
        rows = await ledger();
        expect(rows, hasLength(1));
        expect(rows.single.id, row.id);
        expect(rows.single.retractedAt, isNull, reason: 'on unretracts');
        expect(rows.single.occurredAt, _finalizedAt);
      },
      skip: skipReason,
    );

    test('the author may mark after finalize', () async {
      final helpers = [_h(1), _h(2)];
      await openEpoch(helpers, finalized: true);

      await closureCase.setMark(
        userId: _authorId,
        beaconId: _beaconId,
        expectedEpoch: 1,
        targetId: helpers[0],
        on: true,
      );

      final rows = await ledger();
      expect(
        rows.single.sourceKey,
        'closure:$_beaconId:1:mark:$_authorId:${helpers[0]}',
      );
      expect(rows.single.occurredAt, _finalizedAt);
    }, skip: skipReason);

    test('a final epoch needs expectedEpoch equal to the latest', () async {
      final helpers = [_h(1), _h(2)];
      await openEpoch(helpers, finalized: true);

      await expectLater(
        closureCase.setMark(
          userId: helpers[0],
          beaconId: _beaconId,
          expectedEpoch: 2,
          targetId: helpers[1],
          on: true,
        ),
        closureError(ClosureExceptionCode.staleEpoch),
      );
      expect(await _ledger(writer), isEmpty);
    }, skip: skipReason);
  });
}

typedef _LedgerRow = ({
  String id,
  String sourceKey,
  int kind,
  double count,
  String subject,
  String object,
  DateTime occurredAt,
  DateTime? retractedAt,
});

Future<List<_LedgerRow>> _ledger(Connection writer) async {
  final r = await writer.execute('''
SELECT id, source_key, kind, count, subject_user_id, object_user_id,
       occurred_at, retracted_at
FROM public.trust_evidence
WHERE beacon_id = '$_beaconId'
ORDER BY source_key
''');
  return [
    for (final row in r)
      (
        id: row[0]! as String,
        sourceKey: row[1]! as String,
        kind: row[2]! as int,
        count: (row[3]! as num).toDouble(),
        subject: row[4]! as String,
        object: row[5]! as String,
        occurredAt: (row[6]! as DateTime).toUtc(),
        retractedAt: (row[7] as DateTime?)?.toUtc(),
      ),
  ];
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
    "DELETE FROM public.trust_evidence WHERE beacon_id = '$_beaconId'",
  );
  await writer.execute("DELETE FROM public.beacon WHERE id = '$_beaconId'");
}

Future<void> _seed(Connection writer) async {
  final users = [
    _authorId,
    _outsiderId,
    for (var i = 1; i <= 22; i++) _h(i),
  ];
  for (var i = 0; i < users.length; i++) {
    final key = (i + 10).toString().padRight(44, 'wr');
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${users[i]}', '${users[i]}', '${key.substring(0, 44)}')
ON CONFLICT (id) DO NOTHING
''');
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, published_at)
VALUES ('$_beaconId', '$_authorId', 'closure writes test', '', now())
''');
}

final class _NoSettlement extends Fake
    implements AttentionSystemSettlementPort {}

final class _NoReceipts extends Fake implements ClosureReceiptsPort {}

final class _NoFinalizer extends Fake implements ClosureFinalizerPort {}
