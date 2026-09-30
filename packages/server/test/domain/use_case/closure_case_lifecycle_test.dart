@Tags(['pg'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/closure/closure_band.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_exception.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/recording_beacon_hierarchy_outbox.dart';

const _authorId = 'Uclcaseauth01';
const _aId = 'Uclcasehelp01';
const _bId = 'Uclcasehelp02';
const _cId = 'Uclcasehelp03';
const _dId = 'Uclcasehelp04';
const _pendingId = 'Uclcasepend01';
const _beaconId = 'Bclcasebeac01';
const _childId = 'Bclcasechld01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CLOSURE_CASE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_closure_case',
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
  late MutatingUnitOfWork uow;
  late ClosureCase closureCase;
  late RecordingBeaconHierarchyOutbox outbox;
  late _RecordingReceipts receipts;
  late _RecordingSettlement settlement;
  late _RecordingFinalizer finalizer;

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
      commitments = CommitmentRepository(database);
      helpOffers = HelpOfferRepository(database);
      beacons = BeaconRepository(database);
      uow = MutatingUnitOfWork(database);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    setUp(() async {
      await _reset(writer);
      await _seed(writer);
      outbox = RecordingBeaconHierarchyOutbox();
      receipts = _RecordingReceipts();
      settlement = _RecordingSettlement();
      finalizer = _RecordingFinalizer(repo);
      closureCase = ClosureCase(
        unitOfWork: uow,
        closureRepository: repo,
        beaconRepository: beacons,
        commitmentRepository: commitments,
        helpOfferRepository: helpOffers,
        hierarchyRepository: FakeBeaconHierarchyRepository(),
        lifecycleEffects: buildLifecycleEffectsCase(outbox: outbox),
        attentionSystemSettlement: settlement,
        receipts: receipts,
        finalizer: finalizer,
        env: Env(environment: Environment.test),
        logger: Logger('ClosureCaseLifecycleTest'),
      );
    });
  }

  Future<void> member(String userId) async {
    await helpOffers.upsert(beaconId: _beaconId, userId: userId);
    await commitments.record(
      beaconId: _beaconId,
      userId: userId,
      actorUserId: userId,
      kind: CommitmentEventKind.offered,
    );
    await commitments.record(
      beaconId: _beaconId,
      userId: userId,
      actorUserId: _authorId,
      kind: CommitmentEventKind.acknowledged,
    );
    await _backdateEvents(writer, userId);
  }

  Future<void> writeEvent(
    String helperId,
    CommitmentEventKind kind, {
    bool hook = true,
  }) async {
    final actorId = kind == CommitmentEventKind.withdrawnByHelper
        ? helperId
        : _authorId;
    await uow.run(
      actorUserId: actorId,
      action: () async {
        await repo.lockRequest(_beaconId);
        await commitments.record(
          beaconId: _beaconId,
          userId: helperId,
          actorUserId: actorId,
          kind: kind,
        );
        if (hook) {
          await closureCase.applyMembershipEvent(_beaconId, helperId);
        }
      },
    );
    await _backdateEvents(writer, helperId);
  }

  Future<List<ClosureMemberRow>> members([int epoch = 1]) =>
      repo.members(beaconId: _beaconId, epoch: epoch);

  Future<ClosureMemberRow> row(String userId, [int epoch = 1]) async =>
      (await members(epoch)).singleWhere((m) => m.userId == userId);

  bool isVoter(ClosureMemberRow m) =>
      m.activeAtOpen && m.departure != Departure.removed;

  Future<void> openWith(List<String> helpers) async {
    for (final h in helpers) {
      await member(h);
    }
    await closureCase.close(authorId: _authorId, beaconId: _beaconId);
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

  Matcher closureError(ClosureExceptionCode code) => throwsA(
    isA<ClosureException>().having((e) => e.closureCode, 'closureCode', code),
  );

  group('ClosureCase lifecycle', () {
    test(
      'close with zero members closes the request directly, no epoch',
      () async {
        await closureCase.close(authorId: _authorId, beaconId: _beaconId);

        expect(await _beaconStatus(writer), BeaconStatus.closed.smallintValue);
        expect(await repo.liveEpoch(_beaconId), isNull);
        expect(await _epochCount(writer), 0);
        expect(outbox.recordedEvents.map((e) => e.toStatus), [
          BeaconStatus.closed,
        ]);
        expect(receipts.openedCalls, isEmpty);
        expect(await _transitions(writer, _beaconId), [
          (
            from: BeaconStatus.open.smallintValue,
            to: BeaconStatus.closed.smallintValue,
            reason: 'directClose',
          ),
        ]);
      },
      skip: skipReason,
    );

    test('close is author-only', () async {
      await member(_aId);
      await expectLater(
        closureCase.close(authorId: _aId, beaconId: _beaconId),
        closureError(ClosureExceptionCode.notAuthor),
      );
      expect(await _beaconStatus(writer), BeaconStatus.open.smallintValue);
    }, skip: skipReason);

    test('close with 3 members creates epoch 1 with three voters', () async {
      await openWith([_aId, _bId, _cId]);

      final epoch = (await repo.liveEpoch(_beaconId))!;
      expect(epoch.epoch, 1);
      expect(epoch.status, ClosureEpochStatus.evaluating);
      expect(
        epoch.closesAt.difference(epoch.openedAt),
        const Duration(days: 7),
      );
      expect(epoch.extensionsUsed, 0);
      final rows = await members();
      expect(rows.map((m) => m.userId).toSet(), {_aId, _bId, _cId});
      expect(rows.every(isVoter), isTrue);
      expect(rows.every((m) => m.departure == null), isTrue);
      expect(
        await _beaconStatus(writer),
        BeaconStatus.reviewOpen.smallintValue,
      );
      expect(receipts.openedCalls, [(_beaconId, 1)]);
      expect(await _transitions(writer, _beaconId), [
        (
          from: BeaconStatus.open.smallintValue,
          to: BeaconStatus.reviewOpen.smallintValue,
          reason: 'reviewWindowOpened',
        ),
      ]);
    }, skip: skipReason);

    test(
      'a member withdrawn before close is not a voter, departure voluntary',
      () async {
        await member(_aId);
        await member(_bId);
        await writeEvent(
          _bId,
          CommitmentEventKind.withdrawnByHelper,
          hook: false,
        );
        await closureCase.close(authorId: _authorId, beaconId: _beaconId);

        final b = await row(_bId);
        expect(b.activeAtOpen, isFalse);
        expect(b.departure, Departure.voluntary);
        expect(isVoter(b), isFalse);
        expect(isVoter(await row(_aId)), isTrue);
      },
      skip: skipReason,
    );

    test('reopen twice: second fails with reopenLimit; keeps outcomes and '
        'drafts, removes committed rows', () async {
      await openWith([_aId, _bId]);
      await answerAll([_aId, _bId]);
      await repo.toggleSupport(
        beaconId: _beaconId,
        voterId: _aId,
        targetId: _bId,
        on: true,
      );
      await repo.commitSupport(beaconId: _beaconId, voterId: _aId);
      await repo.toggleSupport(
        beaconId: _beaconId,
        voterId: _bId,
        targetId: _aId,
        on: true,
      );

      await closureCase.reopen(authorId: _authorId, beaconId: _beaconId);

      expect(await repo.liveEpoch(_beaconId), isNull);
      expect(
        await _epochStatus(writer, 1),
        ClosureEpochStatus.cancelled.dbValue,
      );
      expect(
        await _beaconStatus(writer),
        BeaconStatus.needsMoreHelp.smallintValue,
      );
      expect(receipts.cancelledCalls, [(_beaconId, 1)]);
      // Same status-transition effects reopenFromReview records: an activity
      // row with reason reopenedFromReview, and no hierarchy lifecycle event
      // (reopen is ineligible for hierarchy notices).
      expect((await _transitions(writer, _beaconId)).last, (
        from: BeaconStatus.reviewOpen.smallintValue,
        to: BeaconStatus.needsMoreHelp.smallintValue,
        reason: 'reopenedFromReview',
      ));
      expect(outbox.recordedEvents.map((e) => e.toStatus), [
        BeaconStatus.reviewOpen,
      ]);
      expect((await repo.outcomes(_beaconId)).length, 2);
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
        isNotEmpty,
      );

      await closureCase.close(authorId: _authorId, beaconId: _beaconId);
      expect((await repo.liveEpoch(_beaconId))!.epoch, 2);
      await expectLater(
        closureCase.reopen(authorId: _authorId, beaconId: _beaconId),
        closureError(ClosureExceptionCode.reopenLimit),
      );
    }, skip: skipReason);

    test('reopen requires the author and an evaluating epoch', () async {
      await expectLater(
        closureCase.reopen(authorId: _authorId, beaconId: _beaconId),
        closureError(ClosureExceptionCode.wrongStatus),
      );
      await openWith([_aId]);
      await expectLater(
        closureCase.reopen(authorId: _aId, beaconId: _beaconId),
        closureError(ClosureExceptionCode.notAuthor),
      );
    }, skip: skipReason);

    test('stale expectedEpoch is rejected with staleEpoch', () async {
      await openWith([_aId, _bId, _cId]);
      for (final call in <Future<void> Function()>[
        () => closureCase.extend(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 99,
        ),
        () => closureCase.reopen(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 99,
        ),
        () => closureCase.closeNow(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 99,
        ),
      ]) {
        await expectLater(
          call(),
          closureError(ClosureExceptionCode.staleEpoch),
        );
      }
      expect((await repo.liveEpoch(_beaconId))!.epoch, 1);
    }, skip: skipReason);

    test('extend adds 7 days, at most twice', () async {
      await openWith([_aId, _bId, _cId]);
      final before = (await repo.liveEpoch(_beaconId))!;

      await closureCase.extend(authorId: _authorId, beaconId: _beaconId);
      await closureCase.extend(authorId: _authorId, beaconId: _beaconId);

      final after = (await repo.liveEpoch(_beaconId))!;
      expect(after.extensionsUsed, 2);
      expect(
        after.closesAt.difference(before.closesAt),
        const Duration(days: 14),
      );
      await expectLater(
        closureCase.extend(authorId: _authorId, beaconId: _beaconId),
        closureError(ClosureExceptionCode.extendLimit),
      );
    }, skip: skipReason);

    group('canCloseNow (observed through closeNow)', () {
      test('false while one member outcome is unanswered', () async {
        await openWith([_aId, _bId, _cId]);
        await answerAll([_aId, _bId]);
        await _backdateOpenedAt(writer, const Duration(hours: 49));

        await expectLater(
          closureCase.closeNow(authorId: _authorId, beaconId: _beaconId),
          closureError(ClosureExceptionCode.notReady),
        );
        expect(finalizer.calls, isEmpty);
      }, skip: skipReason);

      test('false for 3 members, outcomes set, no commits, < 48 h', () async {
        await openWith([_aId, _bId, _cId]);
        await answerAll([_aId, _bId, _cId]);

        await expectLater(
          closureCase.closeNow(authorId: _authorId, beaconId: _beaconId),
          closureError(ClosureExceptionCode.notReady),
        );
      }, skip: skipReason);

      test('true after 48 h even if voters did not commit', () async {
        await openWith([_aId, _bId, _cId]);
        await answerAll([_aId, _bId, _cId]);
        await _backdateOpenedAt(writer, const Duration(hours: 49));

        await closureCase.closeNow(authorId: _authorId, beaconId: _beaconId);

        expect(finalizer.calls, [
          (_beaconId, 1, FinalizeReason.authorCloseNow),
        ]);
      }, skip: skipReason);

      test('true once every voter has a commit row', () async {
        await openWith([_aId, _bId, _cId]);
        await answerAll([_aId, _bId, _cId]);
        for (final v in [_aId, _bId, _cId]) {
          await repo.commitSupport(beaconId: _beaconId, voterId: v);
        }

        await closureCase.closeNow(authorId: _authorId, beaconId: _beaconId);

        expect(finalizer.calls, hasLength(1));
      }, skip: skipReason);

      test('true immediately for 2 members with both outcomes set', () async {
        await openWith([_aId, _bId]);
        await answerAll([_aId, _bId]);

        await closureCase.closeNow(authorId: _authorId, beaconId: _beaconId);

        expect(finalizer.calls, [
          (_beaconId, 1, FinalizeReason.authorCloseNow),
        ]);
      }, skip: skipReason);
    });

    group('voter derivation', () {
      test(
        'author removes a member: not a voter; readmitted: voter again',
        () async {
          await openWith([_aId, _bId, _cId]);

          await writeEvent(_bId, CommitmentEventKind.releasedByAuthor);
          final removed = await row(_bId);
          expect(removed.departure, Departure.removed);
          expect(removed.activeAtOpen, isTrue);
          expect(isVoter(removed), isFalse);

          await writeEvent(_bId, CommitmentEventKind.readmittedToChat);
          final back = await row(_bId);
          expect(back.departure, isNull);
          expect(isVoter(back), isTrue);
        },
        skip: skipReason,
      );

      test('removedFromChat and blockedCleanup also remove the vote', () async {
        await openWith([_aId, _bId, _cId]);

        await writeEvent(_aId, CommitmentEventKind.removedFromChat);
        await writeEvent(_cId, CommitmentEventKind.blockedCleanup);

        expect((await row(_aId)).departure, Departure.removed);
        expect((await row(_cId)).departure, Departure.removed);
        expect(isVoter(await row(_aId)), isFalse);
        expect(isVoter(await row(_cId)), isFalse);
        expect(isVoter(await row(_bId)), isTrue);
      }, skip: skipReason);

      test('a removed member is not a voter for closeNow: remaining voters '
          'committing is enough', () async {
        await openWith([_aId, _bId, _cId]);
        await answerAll([_aId, _bId, _cId]);
        await writeEvent(_bId, CommitmentEventKind.releasedByAuthor);
        await repo.commitSupport(beaconId: _beaconId, voterId: _aId);
        await repo.commitSupport(beaconId: _beaconId, voterId: _cId);

        await closureCase.closeNow(authorId: _authorId, beaconId: _beaconId);

        expect(finalizer.calls, hasLength(1));
      }, skip: skipReason);

      test('a voluntary leave keeps the vote', () async {
        await openWith([_aId, _bId, _cId]);

        await writeEvent(_cId, CommitmentEventKind.withdrawnByHelper);

        final c = await row(_cId);
        expect(c.departure, Departure.voluntary);
        expect(c.activeAtOpen, isTrue);
        expect(isVoter(c), isTrue);
      }, skip: skipReason);

      test('inactive at open, then readmitted: stays a non-voter', () async {
        await member(_dId);
        await writeEvent(
          _dId,
          CommitmentEventKind.withdrawnByHelper,
          hook: false,
        );
        await openWith([_aId, _bId]);
        expect((await row(_dId)).activeAtOpen, isFalse);

        await writeEvent(_dId, CommitmentEventKind.readmittedToChat);

        final d = await row(_dId);
        expect(d.departure, isNull);
        expect(d.activeAtOpen, isFalse);
        expect(isVoter(d), isFalse);
      }, skip: skipReason);

      test('applyMembershipEvent ignores helpers without a member row and '
          'requests without a live epoch', () async {
        await member(_aId);
        await closureCase.applyMembershipEvent(_beaconId, _aId);
        expect(await _epochCount(writer), 0);

        await openWith([_bId, _cId]);
        // _aId was acknowledged before close, so it is a member too; _dId never
        // was and has no member row.
        await closureCase.applyMembershipEvent(_beaconId, _dId);
        expect((await members()).map((m) => m.userId).toSet(), {
          _aId,
          _bId,
          _cId,
        });
      }, skip: skipReason);
    });

    group('membership hook racing finalize', () {
      const cases = <(String, CommitmentEventKind, CommitmentEventKind?)>[
        ('withdraw', CommitmentEventKind.withdrawnByHelper, null),
        ('release', CommitmentEventKind.releasedByAuthor, null),
        ('remove', CommitmentEventKind.removedFromChat, null),
        (
          'readmit',
          CommitmentEventKind.readmittedToChat,
          CommitmentEventKind.releasedByAuthor,
        ),
        ('blocked cleanup', CommitmentEventKind.blockedCleanup, null),
      ];
      for (final (name, kind, prior) in cases) {
        test('$name: event lands after finalize or is reflected, never '
            'partial', () async {
          await member(_aId);
          await member(_bId);
          if (prior != null) {
            await writeEvent(_bId, prior, hook: false);
          }
          await closureCase.close(authorId: _authorId, beaconId: _beaconId);
          await answerAll([_aId, _bId]);

          final entered = Completer<void>();
          final gate = Completer<void>();
          finalizer
            ..onEnter = entered.complete
            ..gate = gate.future;

          final finalizing = closureCase.closeNow(
            authorId: _authorId,
            beaconId: _beaconId,
          );
          await entered.future.timeout(const Duration(seconds: 10));

          var writerDone = false;
          final racing = writeEvent(_bId, kind).then((_) => writerDone = true);
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(
            writerDone,
            isFalse,
            reason: 'hook must wait on the per-request lock held by finalize',
          );

          gate.complete();
          await finalizing;
          await racing;

          final snapshot = finalizer.membersAtFinalize!;
          final after = await row(_bId);
          // Finalize saw the pre-event state; the event, landing after
          // finalize, does not rewrite the finalized snapshot.
          expect(
            snapshot.singleWhere((m) => m.userId == _bId).departure,
            after.departure,
          );
          // Nothing changed while finalize held the lock, and the finalized
          // result rows are complete and untouched by the later event.
          expect(
            finalizer.membersAtEntry!.map((m) => (m.userId, m.departure)),
            snapshot.map((m) => (m.userId, m.departure)),
          );
          final resultB = (await repo.resultFor(
            beaconId: _beaconId,
            userId: _bId,
          ))!;
          // A helper released before open was not active at open: never a voter.
          expect(resultB.helped, prior == null ? 1.0 : 0.0);
          expect(await _resultCount(writer), 2);
          expect(
            await _epochStatus(writer, 1),
            ClosureEpochStatus.finalized.dbValue,
          );
        }, skip: skipReason);

        test('$name: hook holding the lock completes before finalize '
            'proceeds and is reflected in the result rows', () async {
          await member(_aId);
          await member(_bId);
          if (prior != null) {
            await writeEvent(_bId, prior, hook: false);
          }
          await closureCase.close(authorId: _authorId, beaconId: _beaconId);
          await answerAll([_aId, _bId]);

          final hookHoldsLock = Completer<void>();
          final releaseHook = Completer<void>();
          final hookActorId = kind == CommitmentEventKind.withdrawnByHelper
              ? _bId
              : _authorId;
          final hook = uow.run(
            actorUserId: hookActorId,
            action: () async {
              await repo.lockRequest(_beaconId);
              await commitments.record(
                beaconId: _beaconId,
                userId: _bId,
                actorUserId: hookActorId,
                kind: kind,
              );
              await closureCase.applyMembershipEvent(_beaconId, _bId);
              hookHoldsLock.complete();
              await releaseHook.future;
            },
          );
          await hookHoldsLock.future.timeout(const Duration(seconds: 10));

          final finalizing = closureCase.closeNow(
            authorId: _authorId,
            beaconId: _beaconId,
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(
            finalizer.calls,
            isEmpty,
            reason: 'finalize must wait for the hook holding the lock',
          );

          releaseHook.complete();
          await hook;
          await finalizing;

          final expected = switch (kind) {
            CommitmentEventKind.withdrawnByHelper => Departure.voluntary,
            CommitmentEventKind.readmittedToChat => null,
            _ => Departure.removed,
          };
          final snapshotRow = finalizer.membersAtFinalize!.singleWhere(
            (m) => m.userId == _bId,
          );
          expect(snapshotRow.departure, expected);
          final resultB = (await repo.resultFor(
            beaconId: _beaconId,
            userId: _bId,
          ))!;
          final voter =
              snapshotRow.activeAtOpen &&
              snapshotRow.departure != Departure.removed;
          expect(resultB.helped, voter ? 1.0 : 0.0);
          expect(await _resultCount(writer), 2);
          expect(
            await _epochStatus(writer, 1),
            ClosureEpochStatus.finalized.dbValue,
          );
        }, skip: skipReason);
      }
    });

    group('close preserves existing effects', () {
      test('pending offer gets unansweredAtClose; supersede runs', () async {
        await member(_aId);
        await helpOffers.upsert(beaconId: _beaconId, userId: _pendingId);
        await commitments.record(
          beaconId: _beaconId,
          userId: _pendingId,
          actorUserId: _pendingId,
          kind: CommitmentEventKind.offered,
        );

        await closureCase.close(authorId: _authorId, beaconId: _beaconId);

        final events = await commitments.eventsForPair(
          beaconId: _beaconId,
          userId: _pendingId,
        );
        expect(
          events.map((e) => e.kind),
          contains(CommitmentEventKind.unansweredAtClose),
        );
        expect(settlement.supersededBeacons, [_beaconId]);
        expect((await members()).map((m) => m.userId), [_aId]);
      }, skip: skipReason);

      test('child request close records the lifecycle effect', () async {
        await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, parent_beacon_id)
VALUES ('$_childId', '$_authorId', 'child', '', '$_beaconId')
''');

        await closureCase.close(authorId: _authorId, beaconId: _childId);

        expect(
          await _beaconStatus(writer, _childId),
          BeaconStatus.closed.smallintValue,
        );
        expect(await _transitions(writer, _childId), [
          (
            from: BeaconStatus.open.smallintValue,
            to: BeaconStatus.closed.smallintValue,
            reason: 'directClose',
          ),
        ]);
        expect(outbox.recordedEvents.single.sourceBeaconId, _childId);
        expect(outbox.recordedEvents.single.toStatus, BeaconStatus.closed);
        expect(outbox.topologyInserts.single.sourceBeaconId, _childId);
      }, skip: skipReason);

      Future<void> expectOrderedEffects({
        required String closedBeaconId,
        required bool withMember,
      }) async {
        final log = <String>[];
        final ordered = ClosureCase(
          unitOfWork: uow,
          closureRepository: repo,
          beaconRepository: _LoggingBeacons(beacons, log),
          commitmentRepository: _LoggingCommitments(commitments, log),
          helpOfferRepository: helpOffers,
          hierarchyRepository: FakeBeaconHierarchyRepository(),
          lifecycleEffects: BeaconLifecycleEffectsCase(
            _LoggingOutbox(outbox, log),
            env: Env(environment: Environment.test),
            logger: Logger('ClosureCaseOrderTest'),
          ),
          attentionSystemSettlement: _RecordingSettlement(log),
          receipts: receipts,
          finalizer: finalizer,
          env: Env(environment: Environment.test),
          logger: Logger('ClosureCaseOrderTest'),
        );
        await ordered.close(authorId: _authorId, beaconId: closedBeaconId);
        expect(
          log,
          ['statusTransition', 'lifecycle', 'unansweredAtClose', 'supersede'],
          reason:
              'close effects must run in the documented order '
              '(withMember=$withMember)',
        );
      }

      Future<void> seedChild({required bool withMember}) async {
        await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, parent_beacon_id)
VALUES ('$_childId', '$_authorId', 'child', '', '$_beaconId')
''');
        if (withMember) {
          await helpOffers.upsert(beaconId: _childId, userId: _aId);
          for (final (actor, kind) in [
            (_aId, CommitmentEventKind.offered),
            (_authorId, CommitmentEventKind.acknowledged),
          ]) {
            await commitments.record(
              beaconId: _childId,
              userId: _aId,
              actorUserId: actor,
              kind: kind,
            );
          }
          await writer.execute('''
UPDATE public.beacon_commitment_event
SET created_at = created_at - interval '1 day' WHERE beacon_id = '$_childId'
''');
        }
        await helpOffers.upsert(beaconId: _childId, userId: _pendingId);
        await commitments.record(
          beaconId: _childId,
          userId: _pendingId,
          actorUserId: _pendingId,
          kind: CommitmentEventKind.offered,
        );
      }

      test(
        'effect order on direct close of a child with a pending offer',
        () async {
          await seedChild(withMember: false);
          await expectOrderedEffects(
            closedBeaconId: _childId,
            withMember: false,
          );
        },
        skip: skipReason,
      );

      test('effect order on review-open close of a child with a member and '
          'a pending offer', () async {
        await seedChild(withMember: true);
        await expectOrderedEffects(closedBeaconId: _childId, withMember: true);
      }, skip: skipReason);

      test(
        'reviewOpen transition records lifecycle effect with members',
        () async {
          await openWith([_aId]);
          expect(
            outbox.recordedEvents.single.toStatus,
            BeaconStatus.reviewOpen,
          );
        },
        skip: skipReason,
      );
    });
  });
}

final class _RecordingReceipts implements ClosureReceiptsPort {
  final openedCalls = <(String, int)>[];
  final cancelledCalls = <(String, int)>[];
  final finalizedCalls = <(String, int)>[];

  @override
  Future<void> opened(String beaconId, int epoch) async =>
      openedCalls.add((beaconId, epoch));

  @override
  Future<void> finalized(String beaconId, int epoch) async =>
      finalizedCalls.add((beaconId, epoch));

  @override
  Future<void> cancelled(String beaconId, int epoch) async =>
      cancelledCalls.add((beaconId, epoch));
}

final class _RecordingSettlement extends Fake
    implements AttentionSystemSettlementPort {
  _RecordingSettlement([this._log]);

  final List<String>? _log;
  final supersededBeacons = <String>[];

  @override
  Future<int> supersedeAuthorHelpOfferObligationsOnBeaconClose(
    String beaconId,
  ) async {
    supersededBeacons.add(beaconId);
    _log?.add('supersede');
    return 0;
  }
}

final class _RecordingFinalizer implements ClosureFinalizerPort {
  _RecordingFinalizer(this._repo);

  final ClosureRepository _repo;
  final calls = <(String, int, FinalizeReason)>[];
  void Function()? onEnter;
  Future<void>? gate;
  List<ClosureMemberRow>? membersAtEntry;
  List<ClosureMemberRow>? membersAtFinalize;

  @override
  Future<void> finalize({
    required String beaconId,
    required int epoch,
    required FinalizeReason reason,
  }) async {
    calls.add((beaconId, epoch, reason));
    membersAtEntry = await _repo.members(beaconId: beaconId, epoch: epoch);
    onEnter?.call();
    await gate;
    // Result rows are derived from the member rows visible under the lock,
    // written in the same transaction as the status change (all or nothing).
    final rows = await _repo.members(beaconId: beaconId, epoch: epoch);
    membersAtFinalize = rows;
    await _repo.insertResults(
      beaconId: beaconId,
      epoch: epoch,
      rows: [
        for (final m in rows)
          ClosureResultInsert(
            userId: m.userId,
            outcome: ClosureOutcome.done,
            band: ClosureBand.none,
            draftFlag: ClosureResultDraftFlag.none,
            helped: m.activeAtOpen && m.departure != Departure.removed
                ? 1.0
                : 0.0,
          ),
      ],
    );
    await _repo.setEpochStatus(
      beaconId: beaconId,
      epoch: epoch,
      status: ClosureEpochStatus.finalized,
      finalizedAt: DateTime.timestamp(),
      finalizeReason: reason.dbValue,
    );
  }
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
    "DELETE FROM public.beacon_commitment_event WHERE beacon_id IN ('$_beaconId','$_childId')",
  );
  await writer.execute(
    "DELETE FROM public.beacon_help_offer WHERE beacon_id IN ('$_beaconId','$_childId')",
  );
  await writer.execute(
    "DELETE FROM public.beacon WHERE id IN ('$_childId','$_beaconId')",
  );
}

Future<void> _seed(Connection writer) async {
  const users = [_authorId, _aId, _bId, _cId, _dId, _pendingId];
  for (var i = 0; i < users.length; i++) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${users[i]}', '${users[i]}', '${pgTestPublicKey('clcase', i + 1)}')
ON CONFLICT (id) DO NOTHING
''');
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, published_at)
VALUES ('$_beaconId', '$_authorId', 'closure case test', '', now())
''');
}

Future<void> _backdateEvents(Connection writer, String userId) =>
    writer.execute('''
UPDATE public.beacon_commitment_event
SET created_at = created_at - interval '1 day'
WHERE beacon_id = '$_beaconId' AND user_id = '$userId'
''');

Future<void> _backdateOpenedAt(Connection writer, Duration d) =>
    writer.execute('''
UPDATE public.beacon_closure
SET opened_at = opened_at - interval '${d.inHours} hours',
    closes_at = closes_at - interval '${d.inHours} hours'
WHERE beacon_id = '$_beaconId'
''');

Future<int> _beaconStatus(Connection writer, [String id = _beaconId]) async {
  final r = await writer.execute(
    "SELECT status FROM public.beacon WHERE id = '$id'",
  );
  return r.single.single! as int;
}

Future<int> _epochCount(Connection writer) async {
  final r = await writer.execute(
    "SELECT count(*) FROM public.beacon_closure WHERE beacon_id = '$_beaconId'",
  );
  return r.single.single! as int;
}

Future<int> _epochStatus(Connection writer, int epoch) async {
  final r = await writer.execute(
    "SELECT status FROM public.beacon_closure WHERE beacon_id = '$_beaconId' AND epoch = $epoch",
  );
  return r.single.single! as int;
}

typedef _Transition = ({int from, int to, String reason});

Future<List<_Transition>> _transitions(
  Connection writer,
  String beaconId,
) async {
  final r = await writer.execute('''
SELECT (diff->>'fromStatus')::int, (diff->>'toStatus')::int, diff->>'reason'
FROM public.beacon_activity_event
WHERE beacon_id = '$beaconId' AND type = 16
ORDER BY created_at, id
''');
  return [
    for (final row in r)
      (
        from: row[0]! as int,
        to: row[1]! as int,
        reason: row[2]! as String,
      ),
  ];
}

Future<int> _resultCount(Connection writer) async {
  final r = await writer.execute(
    "SELECT count(*) FROM public.beacon_closure_result WHERE beacon_id = '$_beaconId'",
  );
  return r.single.single! as int;
}

/// Forwards the calls `ClosureCase.close` makes to the real collaborator and
/// appends a label to the shared order log for the ordered ones.
final class _LoggingBeacons implements BeaconRepositoryPort {
  _LoggingBeacons(this._real, this._log);

  final BeaconRepositoryPort _real;
  final List<String> _log;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) => _real.getBeaconById(
    beaconId: beaconId,
    filterByUserId: filterByUserId,
  );

  @override
  Future<void> recordBeaconStatusTransition({
    required String beaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required String reason,
    required String? actorId,
  }) {
    _log.add('statusTransition');
    return _real.recordBeaconStatusTransition(
      beaconId: beaconId,
      fromStatus: fromStatus,
      toStatus: toStatus,
      reason: reason,
      actorId: actorId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LoggingCommitments implements CommitmentRepositoryPort {
  _LoggingCommitments(this._real, this._log);

  final CommitmentRepositoryPort _real;
  final List<String> _log;

  @override
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(String beaconId) =>
      _real.eventsByUser(beaconId);

  @override
  Future<List<CommitmentEvent>> eventsForPair({
    required String beaconId,
    required String userId,
  }) => _real.eventsForPair(beaconId: beaconId, userId: userId);

  @override
  Future<void> record({
    required String beaconId,
    required String userId,
    required String actorUserId,
    required CommitmentEventKind kind,
    String? reason,
  }) {
    if (kind == CommitmentEventKind.unansweredAtClose) {
      _log.add('unansweredAtClose');
    }
    return _real.record(
      beaconId: beaconId,
      userId: userId,
      actorUserId: actorUserId,
      kind: kind,
      reason: reason,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LoggingOutbox implements BeaconHierarchyOutboxPort {
  _LoggingOutbox(this._real, this._log);

  final BeaconHierarchyOutboxPort _real;
  final List<String> _log;

  @override
  Future<BeaconHierarchyEvent> recordEvent({
    required String sourceBeaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    String? actorUserId,
  }) {
    _log.add('lifecycle');
    return _real.recordEvent(
      sourceBeaconId: sourceBeaconId,
      fromStatus: fromStatus,
      toStatus: toStatus,
      occurredAt: occurredAt,
      actorUserId: actorUserId,
    );
  }

  @override
  Future<void> insertTopologyDeliveryTargets({
    required String sourceBeaconId,
    required String eventId,
  }) => _real.insertTopologyDeliveryTargets(
    sourceBeaconId: sourceBeaconId,
    eventId: eventId,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
