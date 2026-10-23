@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/author_invite_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/bud_anchor_sweep_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_bud_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_contact_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/entity/post_parent_stage.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/admission_operation.dart';
import 'package:tentura_server/domain/use_case/anchor_inherit_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/author_invite_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/bud_anchor_sweep_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/post_bud_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

/// Budding C9 (plan §4 C9, Arch §4.1): every bud path races its neighbours
/// on two real connections. Each race runs [_rounds] rounds (simultaneous
/// start, or one side with a head start) under a statement timeout, and after each round asserts no
/// deadlock or timeout, a coherent outcome, and invariants I1, I2 and I6.
///
/// `_post` (author `_postAuthor`) admits `_budder`, `_budder2`, `_invitee`
/// and `_other` through forward edges. `_budder` writes `_budderMsg` and
/// `_budderMsg2`, `_budder2` writes `_budder2Msg`.
const _postAuthor = 'Upbc9author1';
const _budder = 'Upbc9budder1';
const _budder2 = 'Upbc9budder2';
const _invitee = 'Upbc9invitee';
const _other = 'Upbc9other01';
const _users = [_postAuthor, _budder, _budder2, _invitee, _other];

const _post = 'Bpbc9post001';
const _rootMsg = 'Rpbc9root001';
const _budderMsg = 'Rpbc9budd001';
const _budderMsg2 = 'Rpbc9budd002';
const _budder2Msg = 'Rpbc9bud2001';

const _rounds = 6;
const _headStart = Duration(milliseconds: 150);
const _statementTimeoutMs = 5000;
const _roundBudget = Duration(seconds: 30);
const _deadlockDetected = '40P01';
const _queryCanceled = '57014';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_CONCURRENCY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_bud_concurrency',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Post bud concurrency', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    // Drift keeps one pooled connection per TenturaDb, so each side of a
    // race runs on its own database handle to really run concurrently.
    late TenturaDb dbA;
    late TenturaDb dbB;
    late Env dbAEnv;
    late _Stack a;
    late _Stack b;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final base = target.databaseEnv;
      final env = Env(
        environment: Environment.test,
        pgHost: base.pgHost,
        pgPort: base.pgPort,
        pgDatabase: base.pgDatabase,
        pgUsername: base.pgUsername,
        pgPassword: base.pgPassword,
        pgStatementTimeoutMs: _statementTimeoutMs,
        printEnv: false,
        isDebugModeOn: false,
      );
      dbAEnv = env;
      dbA = TenturaDb(env);
      dbB = TenturaDb(env);
      a = _Stack.build(dbA, env);
      b = _Stack.build(dbB, env);
    });

    tearDownAll(() async {
      await dbB.close();
      await tearDownDisposablePgWriter(session: session, drift: dbA);
    });

    /// Runs [sides] concurrently for [_rounds] rounds after [setUpRound],
    /// checks no deadlock or statement timeout, then [verify] and I1/I2/I6.
    Future<void> race<S>({
      required Future<S> Function() setUpRound,
      required List<Future<Object?> Function(S state)> sides,
      required Future<void> Function(
        S state,
        List<_Outcome> outcomes,
        String round,
      )
      verify,
    }) async {
      for (var i = 0; i < _rounds; i++) {
        final round = 'round $i';
        await _seed(writer);
        final state = await setUpRound();
        // Round modes: both sides at once, then each side with a head start,
        // so both lock-acquisition orders are exercised.
        final headStart = switch (i % 3) {
          1 => 0,
          2 => 1,
          _ => null,
        };
        final outcomes =
            await Future.wait([
              for (var k = 0; k < sides.length; k++)
                _settle(() async {
                  if (headStart != null && headStart != k) {
                    await Future<void>.delayed(_headStart);
                  }
                  return sides[k](state);
                }()),
            ]).timeout(
              _roundBudget,
              onTimeout: () => fail('$round did not finish in $_roundBudget'),
            );
        for (final outcome in outcomes) {
          expect(
            _isDeadlockOrTimeout(outcome.error),
            isFalse,
            reason: '$round: deadlock or timeout: ${outcome.error}',
          );
          if (outcome.error != null) {
            expect(
              outcome.error,
              isA<ExceptionBase>(),
              reason: '$round: a losing side fails with a domain exception',
            );
          }
        }
        await verify(state, outcomes, round);
        await _expectInvariants(writer, round);
      }
    }

    Future<PostBudResult> bud(
      _Stack s, {
      String actor = _budder,
      String source = _budderMsg,
      String commandId = 'cmd-c9-1',
      List<String> invitees = const [],
      bool closePost = false,
    }) => s.buds.budFromPost(
      actorUserId: actor,
      postId: _post,
      sourceMessageId: source,
      clientCommandId: commandId,
      title: 'Move the piano',
      description: 'Saturday',
      invitees: [for (final id in invitees) PostBudInvitee(userId: id)],
      closePost: closePost,
    );

    /// A child budded by `_budder` with a pending invite to `_invitee`.
    Future<_Budded> buddedWithInvite() async {
      final result = await bud(a, invitees: const [_invitee]);
      expect(result.invitees.single.outcome, PostBudInviteOutcome.invited);
      final child = result.childBeaconId!;
      final invite = await _pendingInviteId(writer, child, _invitee);
      return (child: child, invite: invite!);
    }

    test('bud ∥ bud on the same source message: two children', () async {
      await race<void>(
        setUpRound: () async {},
        sides: [
          (_) => bud(a, commandId: 'cmd-c9-a'),
          (_) => bud(b, commandId: 'cmd-c9-b'),
        ],
        verify: (_, outcomes, round) async {
          final results = [
            for (final o in outcomes) o.value! as PostBudResult,
          ];
          expect(
            results.map((r) => r.outcome).toSet(),
            {PostBudResultJson.outcomeCreated},
            reason: round,
          );
          final children = await _childrenOf(writer, _post);
          expect(children, hasLength(2), reason: round);
          expect(
            results.map((r) => r.childBeaconId).toSet(),
            children.toSet(),
            reason: round,
          );
        },
      );
    });

    test(
      'bud ∥ bud with the same clientCommandId: the second replays',
      () async {
        await race<void>(
          setUpRound: () async {},
          sides: [
            (_) => bud(a, invitees: const [_invitee]),
            (_) => bud(b, invitees: const [_invitee]),
          ],
          verify: (_, outcomes, round) async {
            final results = [
              for (final o in outcomes) o.value! as PostBudResult,
            ];
            final children = await _childrenOf(writer, _post);
            expect(children, hasLength(1), reason: round);
            for (final r in results) {
              expect(
                r.outcome,
                PostBudResultJson.outcomeCreated,
                reason: round,
              );
              expect(r.childBeaconId, children.single, reason: round);
              expect(
                r.invitees.single.outcome,
                PostBudInviteOutcome.invited,
                reason: round,
              );
            }
            expect(await _inviteCount(writer), 1, reason: round);
          },
        );
      },
    );

    test('accept ∥ child cancel', () async {
      await race<_Budded>(
        setUpRound: buddedWithInvite,
        sides: [
          (s) => a.invites.accept(actorUserId: _invitee, inviteId: s.invite),
          (s) => b.beaconCase.beaconCancel(beaconId: s.child, userId: _budder),
        ],
        verify: (s, outcomes, round) async {
          await _expectExactlyOneWins(
            writer,
            s.invite,
            s.child,
            outcomes,
            round,
            losingStatus: 1,
            losingInviteStatus: AuthorInviteStatus.expired,
          );
        },
      );
    });

    test('accept ∥ child delete', () async {
      await race<_Budded>(
        setUpRound: buddedWithInvite,
        sides: [
          (s) => a.invites.accept(actorUserId: _invitee, inviteId: s.invite),
          (s) => b.beaconCase.deleteById(beaconId: s.child, userId: _budder),
        ],
        verify: (s, outcomes, round) async {
          await _expectExactlyOneWins(
            writer,
            s.invite,
            s.child,
            outcomes,
            round,
            losingStatus: 2,
            losingInviteStatus: AuthorInviteStatus.expired,
          );
        },
      );
    });

    test('accept ∥ block', () async {
      await race<_Budded>(
        setUpRound: buddedWithInvite,
        sides: [
          (s) => a.invites.accept(actorUserId: _invitee, inviteId: s.invite),
          (_) => b.blocks.block(
            blockerId: _invitee,
            blockedId: _budder,
            cascadeMode: 0,
          ),
        ],
        verify: (s, outcomes, round) async {
          expect(outcomes[1].error, isNull, reason: '$round: block succeeds');
          final status = await _inviteStatus(writer, s.invite);
          if (outcomes[0].error == null) {
            expect(status, AuthorInviteStatus.accepted.code, reason: round);
          } else {
            expect(status, AuthorInviteStatus.withdrawn.code, reason: round);
            expect(
              await _isAdmitted(writer, s.child, _invitee),
              isFalse,
              reason: round,
            );
          }
          expect(
            await _pendingInviteId(writer, s.child, _invitee),
            isNull,
            reason: '$round: no pending invite survives the block',
          );
        },
      );
    });

    test('bud ∥ block(budder, invitee)', () async {
      await race<void>(
        setUpRound: () async {},
        sides: [
          (_) => bud(a, invitees: const [_invitee]),
          (_) => b.blocks.block(
            blockerId: _invitee,
            blockedId: _budder,
            cascadeMode: 0,
          ),
        ],
        verify: (_, outcomes, round) async {
          expect(outcomes[0].error, isNull, reason: '$round: bud succeeds');
          expect(outcomes[1].error, isNull, reason: '$round: block succeeds');
          final result = outcomes[0].value! as PostBudResult;
          final child = result.childBeaconId!;
          final outcome = result.invitees.single.outcome;
          expect(
            await _pendingInviteId(writer, child, _invitee),
            isNull,
            reason: '$round: no pending invite between a blocked pair',
          );
          if (outcome != PostBudInviteOutcome.invited) {
            // The block came first: no invite, no snapshot row.
            expect(outcome, PostBudInviteOutcome.blocked, reason: round);
            expect(
              await _inviteStatuses(writer, child, _invitee),
              isEmpty,
              reason: round,
            );
            expect(
              await _observers(writer, child),
              isNot(contains(_invitee)),
              reason: round,
            );
          } else {
            expect(
              await _inviteStatuses(writer, child, _invitee),
              [AuthorInviteStatus.withdrawn.code],
              reason: round,
            );
          }
        },
      );
    });

    test('bud ∥ the invitee leaves the Post', () async {
      await race<void>(
        setUpRound: () async {},
        sides: [
          (_) => bud(a, invitees: const [_invitee]),
          (_) => b.posts.leave(userId: _invitee, beaconId: _post),
        ],
        verify: (_, outcomes, round) async {
          expect(outcomes[0].error, isNull, reason: '$round: bud succeeds');
          expect(outcomes[1].error, isNull, reason: '$round: leave succeeds');
          final result = outcomes[0].value! as PostBudResult;
          final child = result.childBeaconId!;
          final invited =
              result.invitees.single.outcome == PostBudInviteOutcome.invited;
          if (invited) {
            expect(
              await _pendingInviteId(writer, child, _invitee),
              isNotNull,
              reason: round,
            );
            expect(
              await _observers(writer, child),
              contains(_invitee),
              reason: round,
            );
          } else {
            expect(
              result.invitees.single.outcome,
              PostBudInviteOutcome.notEligible,
              reason: round,
            );
            expect(
              await _inviteStatuses(writer, child, _invitee),
              isEmpty,
              reason: round,
            );
            expect(
              await _observers(writer, child),
              isNot(contains(_invitee)),
              reason: round,
            );
          }
        },
      );
    });

    test('bud ∥ Post close', () async {
      await race<void>(
        setUpRound: () async {},
        sides: [
          // Only the Post's author may close it (#666).
          (_) => bud(
            a,
            actor: _postAuthor,
            source: _rootMsg,
            invitees: const [_invitee],
            closePost: true,
          ),
          (_) => bud(
            b,
            actor: _budder2,
            source: _budder2Msg,
            commandId: 'cmd-c9-2',
            invitees: const [_other],
          ),
        ],
        verify: (_, outcomes, round) async {
          expect(outcomes[0].error, isNull, reason: '$round: close bud wins');
          expect(await _beaconStatus(writer, _post), 6, reason: round);
          final children = await _childrenOf(writer, _post);
          if (outcomes[1].error == null) {
            expect(children, hasLength(2), reason: round);
          } else {
            expect(
              outcomes[1].error,
              isA<PostNotOpenException>(),
              reason: round,
            );
            expect(children, hasLength(1), reason: round);
            expect(
              await _inviteStatuses(writer, null, _other),
              isEmpty,
              reason: '$round: a refused bud leaves no invite',
            );
          }
        },
      );
    });

    test('withdraw ∥ accept', () async {
      await race<_Budded>(
        setUpRound: buddedWithInvite,
        sides: [
          (s) => a.invites.accept(actorUserId: _invitee, inviteId: s.invite),
          (s) => b.invites.withdraw(actorUserId: _budder, inviteId: s.invite),
        ],
        verify: (s, outcomes, round) async {
          expect(
            outcomes.where((o) => o.error == null),
            hasLength(1),
            reason: '$round: exactly one side wins',
          );
          final loser = outcomes.firstWhere((o) => o.error != null).error;
          expect(loser, isA<AuthorInviteNotPendingException>(), reason: round);
          final status = await _inviteStatus(writer, s.invite);
          final admitted = await _isAdmitted(writer, s.child, _invitee);
          if (outcomes[0].error == null) {
            expect(status, AuthorInviteStatus.accepted.code, reason: round);
            expect(admitted, isTrue, reason: round);
          } else {
            expect(status, AuthorInviteStatus.withdrawn.code, reason: round);
            expect(admitted, isFalse, reason: round);
          }
        },
      );
    });

    test(
      'helper withdrawal takes the hierarchy lock before the child lock, '
      'so it cannot deadlock with the same helper accepting an invite',
      () async {
        await _seed(writer);
        final s = await buddedWithInvite();
        await _seedActiveOffer(writer, s.child, _invitee);
        // The test holds the hierarchy lock while the accept queues for it
        // first and the withdrawal queues second. On release the accept owns
        // the hierarchy lock and wants the child lock; a withdrawal that
        // already took the child lock before queueing (wrong order) deadlocks
        // with it, one that queued on the hierarchy lock first does not.
        final pids = [await _backendPid(dbA), await _backendPid(dbB)];
        await writer.execute('BEGIN');
        late Future<_Outcome> accept;
        late Future<_Outcome> withdraw;
        try {
          await writer.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
          );
          accept = _settle(
            a.invites.accept(actorUserId: _invitee, inviteId: s.invite),
          );
          await _waitForBlockedBackends(writer, pids, 1);
          withdraw = _settle(
            b.helpOffers.withdraw(
              beaconId: s.child,
              userId: _invitee,
              withdrawReason: 'timing',
            ),
          );
          await _waitForBlockedBackends(writer, pids, 2);
          await writer.execute('COMMIT');
        } finally {
          await writer.execute('ROLLBACK');
        }
        final outcomes = await Future.wait([accept, withdraw]).timeout(
          _roundBudget,
          onTimeout: () => fail('did not finish in $_roundBudget'),
        );
        for (final outcome in outcomes) {
          expect(
            _isDeadlockOrTimeout(outcome.error),
            isFalse,
            reason: 'deadlock or timeout: ${outcome.error}',
          );
          expect(outcome.error, isNull);
        }
        // Accept ran first, then the withdrawal revoked the helper again.
        expect(
          await _inviteStatus(writer, s.invite),
          AuthorInviteStatus.accepted.code,
        );
        expect(await _offerStatus(writer, s.child, _invitee), 1);
        expect(await _isAdmitted(writer, s.child, _invitee), isFalse);
        await _expectInvariants(writer, 'accept then withdraw');
      },
    );

    test(
      'author decline takes the hierarchy lock before touching the offer, '
      'so it cannot deadlock with the helper withdrawing the same offer',
      () async {
        await _seed(writer);
        final s = await buddedWithInvite();
        await _seedActiveOffer(writer, s.child, _invitee);
        // The test holds the hierarchy lock while the withdrawal queues for
        // it first and the decline second. On release the withdrawal owns the
        // hierarchy lock and wants the offer row; a decline that already
        // locked the offer row before queueing (wrong order) deadlocks with
        // it, one that queued on the hierarchy lock first does not.
        final pids = [await _backendPid(dbA), await _backendPid(dbB)];
        await writer.execute('BEGIN');
        late Future<_Outcome> withdraw;
        late Future<_Outcome> decline;
        try {
          await writer.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
          );
          withdraw = _settle(
            b.helpOffers.withdraw(
              beaconId: s.child,
              userId: _invitee,
              withdrawReason: 'timing',
            ),
          );
          await _waitForBlockedBackends(writer, pids, 1);
          decline = _settle(
            a.coordination.declineHelpOffer(
              beaconId: s.child,
              offerUserId: _invitee,
              actorUserId: _budder,
              reason: 'not needed',
            ),
          );
          await _waitForBlockedBackends(writer, pids, 2);
          await writer.execute('COMMIT');
        } finally {
          await writer.execute('ROLLBACK');
        }
        final outcomes = await Future.wait([withdraw, decline]).timeout(
          _roundBudget,
          onTimeout: () => fail('did not finish in $_roundBudget'),
        );
        for (final outcome in outcomes) {
          expect(
            _isDeadlockOrTimeout(outcome.error),
            isFalse,
            reason: 'deadlock or timeout: ${outcome.error}',
          );
        }
        expect(outcomes.first.error, isNull);
        // The withdrawal ran first. The decline, after taking its locks,
        // either still applies or sees the offer is gone and refuses; it must
        // never be skipped silently or fail for another reason.
        final declineError = outcomes.last.error;
        final declineEvents = await _declineEventCount(
          writer,
          s.child,
          _invitee,
        );
        if (declineError == null) {
          expect(declineEvents, 1);
        } else {
          expect(declineError, isA<HelpOfferCoordinationException>());
          expect(
            (declineError as HelpOfferCoordinationException).code,
            isA<HelpOfferCoordinationExceptionCodes>().having(
              (c) => c.exceptionCode,
              'exceptionCode',
              HelpOfferCoordinationExceptionCode.helpOfferNotActive,
            ),
          );
          expect(declineEvents, 0);
        }
        expect(await _offerStatus(writer, s.child, _invitee), 1);
        expect(await _isAdmitted(writer, s.child, _invitee), isFalse);
        await _expectInvariants(writer, 'withdraw then decline');
      },
    );

    test(
      'author decline revalidates acknowledgement after locking, so it cannot '
      'revoke a helper whose invite acceptance acknowledged first',
      () async {
        await _seed(writer);
        final s = await buddedWithInvite();
        await _seedActiveOffer(writer, s.child, _invitee);
        // The test holds the hierarchy lock while the accept queues for it
        // first and the decline second. The decline has already read "not
        // acknowledged" by then; once the accept admits and acknowledges the
        // helper and commits, the decline must re-read and refuse.
        final pids = [await _backendPid(dbA), await _backendPid(dbB)];
        await writer.execute('BEGIN');
        late Future<_Outcome> accept;
        late Future<_Outcome> decline;
        try {
          await writer.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
          );
          accept = _settle(
            b.invites.accept(actorUserId: _invitee, inviteId: s.invite),
          );
          await _waitForBlockedBackends(writer, pids, 1);
          decline = _settle(
            a.coordination.declineHelpOffer(
              beaconId: s.child,
              offerUserId: _invitee,
              actorUserId: _budder,
              reason: 'not needed',
            ),
          );
          await _waitForBlockedBackends(writer, pids, 2);
          // Barrier: the decline's lock wait is only reached after its
          // pre-lock acknowledgement read, and the accept (queued first, so it
          // owns the lock next) has committed nothing yet. So that read can
          // only have seen an unacknowledged, still pending helper.
          expect(
            await _acknowledgementCount(writer, s.child, _invitee),
            0,
            reason: 'no acknowledgement exists while the decline has read',
          );
          expect(await _isAdmitted(writer, s.child, _invitee), isFalse);
          expect(
            await _inviteStatus(writer, s.invite),
            AuthorInviteStatus.pending.code,
          );
          await writer.execute('COMMIT');
        } finally {
          await writer.execute('ROLLBACK');
        }
        final outcomes = await Future.wait([accept, decline]).timeout(
          _roundBudget,
          onTimeout: () => fail('did not finish in $_roundBudget'),
        );
        expect(outcomes.first.error, isNull);
        expect(
          await _inviteStatus(writer, s.invite),
          AuthorInviteStatus.accepted.code,
        );
        final declineError = outcomes.last.error;
        expect(declineError, isA<HelpOfferCoordinationException>());
        expect(
          (declineError! as HelpOfferCoordinationException).code,
          isA<HelpOfferCoordinationExceptionCodes>().having(
            (c) => c.exceptionCode,
            'exceptionCode',
            HelpOfferCoordinationExceptionCode.commitmentAlreadyAcknowledged,
          ),
        );
        // The acknowledged helper keeps the offer, the room access and the
        // acknowledgement; the refused decline leaves no trace.
        expect(await _offerStatus(writer, s.child, _invitee), 0);
        expect(await _isAdmitted(writer, s.child, _invitee), isTrue);
        expect(await _declineEventCount(writer, s.child, _invitee), 0);
        expect(await _acknowledgementCount(writer, s.child, _invitee), 1);
        await _expectInvariants(writer, 'accept then decline');
      },
    );

    for (final path in [
      'accepting an invite',
      'offering help on a pending invite',
    ]) {
      test(
        'an author status change takes the hierarchy lock before the child '
        'row, so it cannot deadlock with the invitee $path',
        () async {
          await _seed(writer);
          final s = await buddedWithInvite();
          // The test holds the hierarchy lock while the invitee's operation
          // queues for it first and the status change second. On release the
          // invitee owns the hierarchy lock and wants the child row; a status
          // change that already locked the child row before queueing (wrong
          // order, its status trigger takes the hierarchy lock later)
          // deadlocks with it.
          final inviteePid = await _backendPid(dbA);
          final statusPid = await _backendPid(dbB);
          final pids = [inviteePid, statusPid];
          await writer.execute('BEGIN');
          late Future<_Outcome> invitee;
          late Future<_Outcome> statusChange;
          try {
            await writer.execute(
              "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
            );
            invitee = _settle(
              path == 'accepting an invite'
                  ? a.invites.accept(actorUserId: _invitee, inviteId: s.invite)
                  : a.helpOffers.offerHelp(
                      beaconId: s.child,
                      userId: _invitee,
                      message: 'On my way',
                    ),
            );
            await _waitForBlockedBackends(writer, pids, 1);
            expect(
              await _hierarchyWaiterPids(writer, pids),
              [inviteePid],
              reason:
                  'the invitee operation queues for the hierarchy lock first',
            );
            statusChange = _settle(
              b.coordination.setBeaconStatus(
                beaconId: s.child,
                authorUserId: _budder,
                status: BeaconStatus.enoughHelp.smallintValue,
              ),
            );
            await _waitForBlockedBackends(writer, pids, 2);
            expect(
              await _hierarchyWaiterPids(writer, pids),
              unorderedEquals(pids),
              reason: 'both queue for the hierarchy lock',
            );
            // Both participating backends are now confirmed waiting for the
            // hierarchy lock, and the invitee waits for it before it touches
            // the child row. So the only backend that could own the child row
            // here is the status change: a row-lock probe that finds it taken
            // pins the inversion (row held while queued for the hierarchy).
            final childRow = await writer.execute(
              Sql.named(
                'SELECT id FROM public.beacon WHERE id = @b '
                'FOR UPDATE SKIP LOCKED',
              ),
              parameters: {'b': s.child},
            );
            expect(
              childRow,
              isNotEmpty,
              reason:
                  'the status change must not hold the child row while it '
                  'waits for the hierarchy lock',
            );
            await writer.execute('COMMIT');
          } finally {
            await writer.execute('ROLLBACK');
          }
          final outcomes = await Future.wait([invitee, statusChange]).timeout(
            _roundBudget,
            onTimeout: () => fail('did not finish in $_roundBudget'),
          );
          for (final outcome in outcomes) {
            expect(
              _isDeadlockOrTimeout(outcome.error),
              isFalse,
              reason: 'deadlock or timeout: ${outcome.error}',
            );
            expect(outcome.error, isNull);
          }
          expect(
            await _beaconStatus(writer, s.child),
            BeaconStatus.enoughHelp.smallintValue,
          );
          await _expectInvariants(writer, 'invitee then status change');
        },
      );
    }

    test(
      'expiry finalization of a Request with a pending invite does not '
      'deadlock with the invitee accepting that invite',
      () async {
        await _seed(writer);
        final s = await buddedWithInvite();
        await writer.execute(
          Sql.named(
            'INSERT INTO public.beacon_closure '
            '(beacon_id, epoch, status, opened_at, closes_at) VALUES '
            "(@b, 1, 0, now() - interval '2 days', now() - interval '1 hour')",
          ),
          parameters: {'b': s.child},
        );
        final sweepPid = await _backendPid(dbA);
        final acceptPid = await _backendPid(dbB);
        // Finalization closes the Request through the real status update
        // (its trigger takes the hierarchy lock), but only once the accept
        // is parked on an advisory lock: with the child lock taken before
        // the hierarchy lock the accept owns hierarchy and waits for the
        // child lock, and the status update then waits for hierarchy. With
        // the right order the accept waits for the hierarchy lock the sweep
        // holds instead.
        final finalizer = _GatedClosingFinalizer(
          BeaconRepository(dbA),
          gate: () => _waitForInviteeParkedBehindSweep(
            writer,
            inviteePid: acceptPid,
            sweepPid: sweepPid,
            beaconId: s.child,
          ),
        );
        final sweep = ClosureFinalizeSweepCase(
          unitOfWork: MutatingUnitOfWork(dbA),
          closureRepository: ClosureRepository(dbA),
          finalizer: finalizer,
          env: dbAEnv,
          logger: Logger('ExpirySweepLockOrderPgTest'),
        );
        // Both sessions queue behind a test-held hierarchy lock so the
        // sweep's transaction starts first, then the accept follows.
        await writer.execute('BEGIN');
        late Future<_Outcome> sweeping;
        late Future<_Outcome> accepting;
        try {
          await writer.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
          );
          sweeping = _settle(sweep.run());
          // The correct sweep queues for the hierarchy lock before anything
          // else; the wrong one already holds the child lock and runs on.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          accepting = _settle(
            b.invites.accept(actorUserId: _invitee, inviteId: s.invite),
          );
          // The accept is queued for the test-held hierarchy lock; release
          // it only then, so the gate above sees the post-release state.
          await _waitForBlockedBackends(writer, [acceptPid], 1);
          await writer.execute('COMMIT');
        } finally {
          await writer.execute('ROLLBACK');
        }
        final outcomes = await Future.wait([sweeping, accepting]).timeout(
          _roundBudget,
          onTimeout: () => fail('did not finish in $_roundBudget'),
        );
        for (final outcome in outcomes) {
          expect(
            _isDeadlockOrTimeout(outcome.error),
            isFalse,
            reason: 'deadlock or timeout: ${outcome.error}',
          );
        }
        expect(outcomes[0].error, isNull, reason: 'the sweep finalizes');
        if (outcomes[1].error != null) {
          expect(outcomes[1].error, isA<ExceptionBase>());
        }
        expect(sweepPid, isNot(acceptPid));
        // The sweep logs and swallows a failed row, so a deadlock victim
        // shows up as a Request that was never closed.
        expect(
          await _beaconStatus(writer, s.child),
          BeaconStatus.closed.smallintValue,
          reason: 'the sweep finalized the expired Request',
        );
        await _expectInvariants(writer, 'expiry finalize and invite accept');
      },
    );

    for (final closeNow in [false, true]) {
      test(
        '${closeNow ? 'closing a Request now' : 'reopening a Request'} in '
        'review does not deadlock with the invitee accepting a pending invite',
        () async {
          await _seed(writer);
          final s = await buddedWithInvite();
          await writer.execute(
            Sql.named(
              'UPDATE public.beacon SET status = @s WHERE id = @b',
            ),
            parameters: {
              's': BeaconStatus.reviewOpen.smallintValue,
              'b': s.child,
            },
          );
          await writer.execute(
            Sql.named(
              'INSERT INTO public.beacon_closure '
              '(beacon_id, epoch, status, opened_at, closes_at) VALUES '
              "(@b, 1, 0, now() - interval '1 hour', now() + interval '6 days')",
            ),
            parameters: {'b': s.child},
          );
          final closurePid = await _backendPid(dbA);
          final acceptPid = await _backendPid(dbB);
          // The closure side runs on its own stack so its finalizer can
          // close the Request through the real status update.
          final closing = _Stack.build(
            dbA,
            dbAEnv,
            finalizer: _GatedClosingFinalizer(
              BeaconRepository(dbA),
              fromStatus: BeaconStatus.reviewOpen,
              gate: () async {},
            ),
          );
          // The accept queues for a test-held hierarchy lock first, then the
          // closure operation follows. With the child advisory lock taken
          // before the hierarchy lock the closure holds the child lock while
          // queued for hierarchy behind the accept, which in turn needs the
          // child lock once granted: a deadlock. With the right order the
          // closure queues for hierarchy before it takes anything else.
          await writer.execute('BEGIN');
          late Future<_Outcome> accepting;
          late Future<_Outcome> closureOp;
          try {
            await writer.execute(
              "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
            );
            accepting = _settle(
              b.invites.accept(actorUserId: _invitee, inviteId: s.invite),
            );
            await _waitForBlockedBackends(writer, [acceptPid], 1);
            closureOp = _settle(
              closeNow
                  ? closing.closure.closeNow(
                      authorId: _budder,
                      beaconId: s.child,
                    )
                  : closing.closure.reopen(
                      authorId: _budder,
                      beaconId: s.child,
                    ),
            );
            await _waitForBlockedBackends(writer, [acceptPid, closurePid], 2);
            await writer.execute('COMMIT');
          } finally {
            await writer.execute('ROLLBACK');
          }
          final outcomes = await Future.wait([accepting, closureOp]).timeout(
            _roundBudget,
            onTimeout: () => fail('did not finish in $_roundBudget'),
          );
          for (final outcome in outcomes) {
            expect(
              _isDeadlockOrTimeout(outcome.error),
              isFalse,
              reason: 'deadlock or timeout: ${outcome.error}',
            );
          }
          expect(outcomes[1].error, isNull, reason: 'the closure op succeeds');
          if (outcomes[0].error != null) {
            expect(outcomes[0].error, isA<ExceptionBase>());
          }
          expect(
            await _beaconStatus(writer, s.child),
            (closeNow ? BeaconStatus.closed : BeaconStatus.open).smallintValue,
          );
          await _expectInvariants(writer, 'closure op and invite accept');
        },
      );
    }

    for (final action in ['accept', 'decline', 'withdraw']) {
      test(
        'an offer $action queued behind a Request expiry finalization is '
        'rejected without side effects once the Request is closed',
        () async {
          await _seed(writer);
          final s = await buddedWithInvite();
          await _seedActiveOffer(writer, s.child, _invitee);
          await writer.execute(
            Sql.named(
              'INSERT INTO public.beacon_closure '
              '(beacon_id, epoch, status, opened_at, closes_at) VALUES '
              "(@b, 1, 0, now() - interval '2 days', now() - interval '1 hour')",
            ),
            parameters: {'b': s.child},
          );
          final sweepPid = await _backendPid(dbA);
          final actionPid = await _backendPid(dbB);
          final sweep = ClosureFinalizeSweepCase(
            unitOfWork: MutatingUnitOfWork(dbA),
            closureRepository: ClosureRepository(dbA),
            finalizer: _GatedClosingFinalizer(
              BeaconRepository(dbA),
              gate: () async {},
            ),
            env: dbAEnv,
            logger: Logger('OfferActionRevalidationPgTest'),
          );
          // The sweep queues for the test-held hierarchy lock first and
          // closes the Request (no acknowledged members) once it owns it;
          // the action already validated an open Request and an active offer
          // before it queued second, so it must revalidate after locking.
          await writer.execute('BEGIN');
          late Future<_Outcome> sweeping;
          late Future<_Outcome> acting;
          try {
            await writer.execute(
              "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
            );
            sweeping = _settle(sweep.run());
            await _waitForBlockedBackends(writer, [sweepPid], 1);
            acting = _settle(switch (action) {
              'accept' => b.coordination.acceptHelpOffer(
                beaconId: s.child,
                offerUserId: _invitee,
                actorUserId: _budder,
              ),
              'decline' => b.coordination.declineHelpOffer(
                beaconId: s.child,
                offerUserId: _invitee,
                actorUserId: _budder,
                reason: 'not needed',
              ),
              _ => b.helpOffers.withdraw(
                beaconId: s.child,
                userId: _invitee,
                withdrawReason: 'timing',
              ),
            });
            await _waitForBlockedBackends(writer, [sweepPid, actionPid], 2);
            await writer.execute('COMMIT');
          } finally {
            await writer.execute('ROLLBACK');
          }
          final outcomes = await Future.wait([sweeping, acting]).timeout(
            _roundBudget,
            onTimeout: () => fail('did not finish in $_roundBudget'),
          );
          expect(outcomes[0].error, isNull, reason: 'the sweep finalizes');
          expect(
            await _beaconStatus(writer, s.child),
            BeaconStatus.closed.smallintValue,
          );
          final error = outcomes[1].error;
          expect(error, isA<HelpOfferCoordinationException>());
          expect(
            (error! as HelpOfferCoordinationException).code,
            isA<HelpOfferCoordinationExceptionCodes>().having(
              (c) => c.exceptionCode,
              'exceptionCode',
              action == 'withdraw'
                  ? HelpOfferCoordinationExceptionCode.beaconWithdrawForbidden
                  : HelpOfferCoordinationExceptionCode.beaconNotOpen,
            ),
          );
          expect(await _offerStatus(writer, s.child, _invitee), 0);
          expect(await _isAdmitted(writer, s.child, _invitee), isFalse);
          expect(await _acknowledgementCount(writer, s.child, _invitee), 0);
          expect(await _declineEventCount(writer, s.child, _invitee), 0);
        },
      );
    }

    test(
      'author decline queued behind the helper withdrawing the same offer '
      'is rejected as not active, leaving no decline behind',
      () async {
        await _seed(writer);
        final s = await buddedWithInvite();
        await _seedActiveOffer(writer, s.child, _invitee);
        final pids = [await _backendPid(dbA), await _backendPid(dbB)];
        await writer.execute('BEGIN');
        late Future<_Outcome> withdraw;
        late Future<_Outcome> decline;
        try {
          await writer.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
          );
          withdraw = _settle(
            b.helpOffers.withdraw(
              beaconId: s.child,
              userId: _invitee,
              withdrawReason: 'timing',
            ),
          );
          await _waitForBlockedBackends(writer, pids, 1);
          decline = _settle(
            a.coordination.declineHelpOffer(
              beaconId: s.child,
              offerUserId: _invitee,
              actorUserId: _budder,
              reason: 'not needed',
            ),
          );
          await _waitForBlockedBackends(writer, pids, 2);
          await writer.execute('COMMIT');
        } finally {
          await writer.execute('ROLLBACK');
        }
        final outcomes = await Future.wait([withdraw, decline]).timeout(
          _roundBudget,
          onTimeout: () => fail('did not finish in $_roundBudget'),
        );
        expect(outcomes.first.error, isNull);
        final error = outcomes.last.error;
        expect(error, isA<HelpOfferCoordinationException>());
        expect(
          (error! as HelpOfferCoordinationException).code,
          isA<HelpOfferCoordinationExceptionCodes>().having(
            (c) => c.exceptionCode,
            'exceptionCode',
            HelpOfferCoordinationExceptionCode.helpOfferNotActive,
          ),
        );
        expect(await _declineEventCount(writer, s.child, _invitee), 0);
        expect(await _offerStatus(writer, s.child, _invitee), 1);
      },
    );

    for (final existingOffer in [true, false]) {
      test(
        'an invitee offering help takes the child advisory lock before the '
        'child row and the invite row '
        '(${existingOffer ? 'existing offer' : 'new offer'})',
        () async {
          await _seed(writer);
          final s = await buddedWithInvite();
          if (existingOffer) await _seedActiveOffer(writer, s.child, _invitee);
          // The test plays another unit of work that owns the child advisory
          // lock (a closure or admission step) and, in a second phase, the
          // child row. Phase 1: an offer that locked the child row or the
          // invite row before queueing for the advisory lock (wrong order)
          // would deadlock with it; one that queues first holds neither.
          // Phase 2: the advisory lock is released while the test keeps the
          // child row; the offer must now queue on the child row before
          // touching the invite row, so the invite row is still free.
          final pid = await _backendPid(dbA);
          final writerPid = await _writerBackendPid(writer);
          await writer.execute('BEGIN');
          Future<_Outcome>? offer;
          try {
            // Session-level, so it can be released before the transaction
            // (and the child row lock) ends; it conflicts with the offer's
            // transaction-level request for the same key.
            await writer.execute(
              r'SELECT pg_advisory_lock(hashtextextended($1, 4242))',
              parameters: [s.child],
            );
            offer = _settle(
              a.helpOffers.offerHelp(
                beaconId: s.child,
                userId: _invitee,
                message: 'On my way',
              ),
            );
            await _waitForAdvisoryWaiter(writer, pid, s.child);
            final childRow = await writer.execute(
              Sql.named(
                'SELECT id FROM public.beacon WHERE id = @b '
                'FOR UPDATE SKIP LOCKED',
              ),
              parameters: {'b': s.child},
            );
            expect(
              childRow,
              isNotEmpty,
              reason:
                  'the offer must not hold the child row while it waits for '
                  'the child advisory lock',
            );
            await _expectInviteRowFree(
              writer,
              s.invite,
              'the offer must not hold the invite row while it waits for '
              'the child advisory lock',
            );
            await writer.execute(
              r'SELECT pg_advisory_unlock(hashtextextended($1, 4242))',
              parameters: [s.child],
            );
            await _waitForRowLockWaiter(writer, pid, writerPid);
            await _expectInviteRowFree(
              writer,
              s.invite,
              'the offer must queue on the child row before it locks the '
              'invite row',
            );
            await writer.execute('COMMIT');
          } finally {
            await writer.execute('ROLLBACK');
            await writer.execute('SELECT pg_advisory_unlock_all()');
            // Let a failed probe's offer finish before the next test reseeds.
            await offer?.timeout(
              _roundBudget,
              onTimeout: () => fail('did not finish in $_roundBudget'),
            );
          }
          final outcome = await offer;
          expect(
            _isDeadlockOrTimeout(outcome.error),
            isFalse,
            reason: 'deadlock or timeout: ${outcome.error}',
          );
          expect(outcome.error, isNull);
          expect(
            await _inviteStatus(writer, s.invite),
            AuthorInviteStatus.accepted.code,
          );
          expect(await _isAdmitted(writer, s.child, _invitee), isTrue);
          await _expectInvariants(writer, 'offer through the invite');
        },
      );
    }

    for (final earlierInvite in [false, true]) {
      for (final existingOffer in [true, false]) {
        test(
          'an invitee offering help while the author creates the first invite '
          'is admitted through it and no ordinary offer obligation is raised '
          '(${earlierInvite ? 'after a withdrawn invite' : 'no earlier invite'}, '
          '${existingOffer ? 'existing offer' : 'new offer'})',
          () async {
            await _seed(writer);
            final String child;
            if (earlierInvite) {
              final s = await buddedWithInvite();
              await a.invites.withdraw(
                actorUserId: _budder,
                inviteId: s.invite,
              );
              child = s.child;
            } else {
              child = (await bud(a)).childBeaconId!;
            }
            expect(await _pendingInviteId(writer, child, _invitee), isNull);
            if (existingOffer) await _seedActiveOffer(writer, child, _invitee);
            // The author's create queues on the child row first, so it
            // commits before the offer gets the row; the offer looked for a
            // pending invite before that and found none, so it must look
            // again once it holds its locks.
            final createPid = await _backendPid(dbB);
            final offerPid = await _backendPid(dbA);
            final writerPid = await _writerBackendPid(writer);
            await writer.execute('BEGIN');
            Future<_Outcome>? create;
            Future<_Outcome>? offer;
            try {
              await writer.execute(
                Sql.named(
                  'SELECT id FROM public.beacon WHERE id = @b FOR UPDATE',
                ),
                parameters: {'b': child},
              );
              create = _settle(
                b.invites.create(
                  actorUserId: _budder,
                  beaconId: child,
                  inviteeId: _invitee,
                ),
              );
              await _waitForRowLockWaiter(writer, createPid, writerPid);
              offer = _settle(
                a.helpOffers.offerHelp(
                  beaconId: child,
                  userId: _invitee,
                  message: 'On my way',
                ),
              );
              await _waitForLockWaiter(writer, offerPid);
              await writer.execute('COMMIT');
            } finally {
              await writer.execute('ROLLBACK');
              await Future.wait([
                ?create,
                ?offer,
              ]).timeout(
                _roundBudget,
                onTimeout: () => fail('did not finish in $_roundBudget'),
              );
            }
            final outcomes = [await create, await offer];
            for (final outcome in outcomes) {
              expect(
                _isDeadlockOrTimeout(outcome.error),
                isFalse,
                reason: 'deadlock or timeout: ${outcome.error}',
              );
              expect(outcome.error, isNull);
            }
            expect(
              await _inviteStatuses(writer, child, _invitee),
              contains(AuthorInviteStatus.accepted.code),
            );
            expect(
              await _pendingInviteId(writer, child, _invitee),
              isNull,
              reason: 'the created invite is accepted by the offer',
            );
            expect(await _isAdmitted(writer, child, _invitee), isTrue);
            expect(
              await _helpOfferSubmittedCount(writer, child),
              0,
              reason:
                  'an admitted invitee raises no author-response obligation',
            );
            await _expectInvariants(writer, 'offer racing a new invite');
          },
        );
      }
    }

    test('later invite ∥ bud from the same Post (N5)', () async {
      await race<String>(
        setUpRound: () async {
          final first = await bud(a, commandId: 'cmd-c9-first');
          return first.childBeaconId!;
        },
        sides: [
          (child) => a.invites.create(
            actorUserId: _budder,
            beaconId: child,
            inviteeId: _invitee,
          ),
          (_) => bud(
            b,
            source: _budderMsg2,
            commandId: 'cmd-c9-second',
            invitees: const [_invitee],
          ),
        ],
        verify: (child, outcomes, round) async {
          expect(outcomes[0].error, isNull, reason: round);
          expect(outcomes[1].error, isNull, reason: round);
          final created =
              (outcomes[0].value! as AuthorInviteCreateResult).outcome;
          final budded =
              (outcomes[1].value! as PostBudResult).invitees.single.outcome;
          expect(
            {created, budded},
            {
              PostBudInviteOutcome.invited,
              PostBudInviteOutcome.alreadyInvited,
            },
            reason: '$round: exactly one path takes the N5 slot',
          );
          expect(
            await _inviteStatuses(writer, null, _invitee),
            [AuthorInviteStatus.pending.code],
            reason: round,
          );
        },
      );
    });
  });
}

/// Accept against a terminal transition of the child: exactly one wins. When
/// accept wins the child stays open with the invitee admitted; otherwise the
/// child is in [losingStatus] and the invite is [losingInviteStatus].
Future<void> _expectExactlyOneWins(
  Connection writer,
  String invite,
  String child,
  List<_Outcome> outcomes,
  String round, {
  required int losingStatus,
  required AuthorInviteStatus losingInviteStatus,
}) async {
  expect(
    outcomes.where((o) => o.error == null),
    hasLength(1),
    reason: '$round: exactly one side wins (${outcomes.map((o) => o.error)})',
  );
  final status = await _inviteStatus(writer, invite);
  final admitted = await _isAdmitted(writer, child, _invitee);
  if (outcomes[0].error == null) {
    expect(status, AuthorInviteStatus.accepted.code, reason: round);
    expect(admitted, isTrue, reason: round);
    expect(await _beaconStatus(writer, child), 0, reason: round);
  } else {
    expect(status, losingInviteStatus.code, reason: round);
    expect(admitted, isFalse, reason: round);
    expect(await _beaconStatus(writer, child), losingStatus, reason: round);
  }
}

/// I1: every non-author, non-steward admitted participant on an open-family
/// Request has an acknowledged commitment. I2: every such admission has both
/// confirmations (the helper's offer and the author's `useful`), and every
/// accepted invite is such an admission confirmed by its inviter. I6: at most
/// one pending invite per (inviter, invitee, source Post).
Future<void> _expectInvariants(Connection writer, String round) async {
  final i1 = await writer.execute('''
SELECT bp.beacon_id, bp.user_id
FROM public.beacon_participant bp
JOIN public.beacon b ON b.id = bp.beacon_id
WHERE b.kind = 0
  AND b.status IN (0, 7, 8)
  AND bp.room_access = 3
  AND bp.role <> 1
  AND bp.user_id <> b.user_id
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_commitment_event e
    WHERE e.beacon_id = bp.beacon_id AND e.user_id = bp.user_id
      AND e.kind = 1
  )
''');
  expect(i1, isEmpty, reason: '$round: I1 violated: $i1');

  final i2 = await writer.execute('''
SELECT bp.beacon_id, bp.user_id
FROM public.beacon_participant bp
JOIN public.beacon b ON b.id = bp.beacon_id
WHERE b.kind = 0
  AND bp.room_access = 3
  AND bp.role <> 1
  AND bp.user_id <> b.user_id
  AND (
    NOT EXISTS (
      SELECT 1 FROM public.beacon_help_offer o
      WHERE o.beacon_id = bp.beacon_id AND o.user_id = bp.user_id
    )
    OR NOT EXISTS (
      SELECT 1 FROM public.beacon_help_offer_coordination c
      WHERE c.offer_beacon_id = bp.beacon_id
        AND c.offer_user_id = bp.user_id
        AND c.response_type = 0
    )
  )
''');
  expect(i2, isEmpty, reason: '$round: I2 admission without confirmations');

  final i2Invites = await writer.execute('''
SELECT i.id
FROM public.beacon_author_invite i
WHERE i.status = 1
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_help_offer_coordination c
    WHERE c.offer_beacon_id = i.beacon_id
      AND c.offer_user_id = i.invitee_id
      AND c.author_user_id = i.inviter_id
      AND c.response_type = 0
  )
''');
  expect(i2Invites, isEmpty, reason: '$round: I2 accepted invite unconfirmed');

  final i6 = await writer.execute('''
SELECT inviter_id, invitee_id, source_post_id
FROM public.beacon_author_invite
WHERE status = 0
GROUP BY inviter_id, invitee_id, source_post_id
HAVING count(*) > 1
''');
  expect(i6, isEmpty, reason: '$round: I6 violated: $i6');
}

typedef _Budded = ({String child, String invite});

typedef _Outcome = ({Object? error, Object? value});

Future<_Outcome> _settle(Future<Object?> action) async {
  try {
    return (error: null, value: await action);
  } on Object catch (error) {
    return (error: error, value: null);
  }
}

bool _isDeadlockOrTimeout(Object? error) {
  if (error == null) return false;
  if (error is ServerException &&
      (error.code == _deadlockDetected || error.code == _queryCanceled)) {
    return true;
  }
  final text = '$error'.toLowerCase();
  return text.contains(_deadlockDetected) ||
      text.contains(_queryCanceled) ||
      text.contains('deadlock') ||
      text.contains('statement timeout');
}

Future<List<String>> _childrenOf(Connection writer, String parent) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT id FROM public.beacon WHERE parent_beacon_id = @p ORDER BY id',
    ),
    parameters: {'p': parent},
  );
  return [for (final r in rows) r.single! as String];
}

Future<int> _beaconStatus(Connection writer, String beacon) async {
  final rows = await writer.execute(
    Sql.named('SELECT status FROM public.beacon WHERE id = @b'),
    parameters: {'b': beacon},
  );
  return rows.single.single! as int;
}

Future<int> _inviteCount(Connection writer) async {
  final rows = await writer.execute(
    'SELECT count(*)::int FROM public.beacon_author_invite',
  );
  return rows.single.single! as int;
}

Future<int> _inviteStatus(Connection writer, String id) async {
  final rows = await writer.execute(
    Sql.named('SELECT status FROM public.beacon_author_invite WHERE id = @i'),
    parameters: {'i': id},
  );
  return rows.single.single! as int;
}

/// Statuses of [invitee]'s invites, on [child] or (null) on any beacon.
Future<List<int>> _inviteStatuses(
  Connection writer,
  String? child,
  String invitee,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT status FROM public.beacon_author_invite
WHERE invitee_id = @u AND (@b::text IS NULL OR beacon_id = @b::text)
ORDER BY status
'''),
    parameters: {'u': invitee, 'b': child},
  );
  return [for (final r in rows) r.single! as int];
}

Future<String?> _pendingInviteId(
  Connection writer,
  String child,
  String invitee,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT id FROM public.beacon_author_invite
WHERE beacon_id = @b AND invitee_id = @u AND status = 0
'''),
    parameters: {'b': child, 'u': invitee},
  );
  return rows.isEmpty ? null : rows.single.single! as String;
}

Future<Set<String>> _observers(Connection writer, String child) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT user_id FROM public.beacon_bud_observer WHERE beacon_id = @b',
    ),
    parameters: {'b': child},
  );
  return {for (final r in rows) r.single! as String};
}

Future<bool> _isAdmitted(Connection writer, String beacon, String user) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT 1 FROM public.beacon_participant
WHERE beacon_id = @b AND user_id = @u AND room_access = 3
'''),
    parameters: {'b': beacon, 'u': user},
  );
  return rows.isNotEmpty;
}

/// An active help offer plus its participant row, as left by an offer the
/// invitee made before the author's invite arrived.
Future<void> _seedActiveOffer(
  Connection writer,
  String beacon,
  String user,
) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, created_at)
VALUES (@b, @u, now())
ON CONFLICT DO NOTHING
'''),
    parameters: {'b': beacon, 'u': user},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access, created_at, updated_at)
VALUES ('Ppbc9offer01', @b, @u, 2, 0, 1, now(), now())
ON CONFLICT DO NOTHING
'''),
    parameters: {'b': beacon, 'u': user},
  );
}

/// Backend pids among [pids] waiting for the hierarchy lock (scoped to this
/// database, never cluster-wide).
Future<List<int>> _hierarchyWaiterPids(
  Connection writer,
  List<int> pids,
) async {
  final rows = await writer.execute(
    'SELECT DISTINCT l.pid FROM pg_locks l '
    "WHERE l.locktype = 'advisory' AND NOT l.granted AND l.objsubid = 1 "
    'AND ((l.classid::bigint << 32) | l.objid::bigint) = '
    "hashtextextended('tentura.beacon_hierarchy.v1', 0) "
    'AND l.pid IN (${pids.join(',')}) AND l.database = '
    '(SELECT oid FROM pg_database WHERE datname = current_database())',
  );
  return [for (final r in rows) r.single! as int];
}

/// Waits until [count] of the sessions with backend [pids] wait for the
/// hierarchy advisory lock.
///
/// `pg_locks` is cluster-wide, so waiters are limited to the participating
/// backends, this database's oid and the hierarchy lock key (an advisory
/// key is split over `classid`/`objid`). `pg_stat_activity` is avoided: its
/// snapshot is frozen for the observer's open transaction.
Future<void> _waitForBlockedBackends(
  Connection writer,
  List<int> pids,
  int count,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      'SELECT count(DISTINCT l.pid) FROM pg_locks l '
      "WHERE l.locktype = 'advisory' AND NOT l.granted "
      'AND l.objsubid = 1 '
      'AND ((l.classid::bigint << 32) | l.objid::bigint) = '
      "hashtextextended('tentura.beacon_hierarchy.v1', 0) "
      'AND l.pid IN (${pids.join(',')}) AND l.database = '
      '(SELECT oid FROM pg_database WHERE datname = current_database())',
    );
    if ((rows.single.single! as int) >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('fewer than $count of the sessions $pids blocked on the hierarchy lock');
}

/// Waits until the invitee session [inviteePid] is parked behind the sweep
/// session [sweepPid]: either waiting for the child advisory lock of
/// [beaconId], or waiting for the hierarchy lock while [sweepPid] holds it.
/// A wait for the hierarchy lock held by someone else does not count.
///
/// Scoped to this database and the two pids (never cluster-wide).
Future<void> _waitForInviteeParkedBehindSweep(
  Connection writer, {
  required int inviteePid,
  required int sweepPid,
  required String beaconId,
}) async {
  const hierarchyKey = "hashtextextended('tentura.beacon_hierarchy.v1', 0)";
  const key = '((l.classid::bigint << 32) | l.objid::bigint)';
  const inThisDb =
      'l.database = (SELECT oid FROM pg_database WHERE datname = current_database())';
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      Sql.named(
        'SELECT '
        '(SELECT count(*) FROM pg_locks l '
        "WHERE l.locktype = 'advisory' AND NOT l.granted AND l.objsubid = 1 "
        'AND l.pid = @invitee AND $inThisDb '
        'AND $key = hashtextextended(@b, 4242)) + '
        '(SELECT count(*) FROM pg_locks l '
        "WHERE l.locktype = 'advisory' AND NOT l.granted AND l.objsubid = 1 "
        'AND l.pid = @invitee AND $inThisDb AND $key = $hierarchyKey '
        'AND EXISTS (SELECT 1 FROM pg_locks h '
        "WHERE h.locktype = 'advisory' AND h.granted AND h.objsubid = 1 "
        'AND h.pid = @sweep AND h.database = l.database '
        'AND h.classid = l.classid AND h.objid = l.objid))',
      ),
      parameters: {'invitee': inviteePid, 'sweep': sweepPid, 'b': beaconId},
    );
    if ((rows.single.single! as int) >= 1) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('invitee $inviteePid never parked behind the sweep $sweepPid');
}

/// Waits until the session with backend [pid] waits for the child advisory
/// lock of [beaconId] (`hashtextextended(beaconId, 4242)`).
///
/// `pg_locks` is cluster-wide, so the wait is limited to the participating
/// backend, this database's oid and the lock key (an advisory key is split
/// over `classid`/`objid`).
Future<void> _waitForAdvisoryWaiter(
  Connection writer,
  int pid,
  String beaconId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      Sql.named(
        'SELECT count(*) FROM pg_locks l '
        "WHERE l.locktype = 'advisory' AND NOT l.granted "
        'AND l.objsubid = 1 '
        'AND ((l.classid::bigint << 32) | l.objid::bigint) = '
        'hashtextextended(@b, 4242) '
        'AND l.pid = @pid AND l.database = '
        '(SELECT oid FROM pg_database WHERE datname = current_database())',
      ),
      parameters: {'b': beaconId, 'pid': pid},
    );
    if ((rows.single.single! as int) >= 1) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('session $pid never blocked on the child advisory lock of $beaconId');
}

/// Fails unless the invite row [inviteId] is not locked by another session.
/// The probe runs in a savepoint, so its own row lock is released again.
Future<void> _expectInviteRowFree(
  Connection writer,
  String inviteId,
  String reason,
) async {
  await writer.execute('SAVEPOINT invite_probe');
  final rows = await writer.execute(
    Sql.named(
      'SELECT id FROM public.beacon_author_invite WHERE id = @i '
      'FOR UPDATE SKIP LOCKED',
    ),
    parameters: {'i': inviteId},
  );
  await writer.execute('ROLLBACK TO SAVEPOINT invite_probe');
  expect(rows, isNotEmpty, reason: reason);
}

/// Waits until the session with backend [pid] is blocked by the session
/// [blockerPid] without waiting for an advisory lock, i.e. on a row lock.
Future<void> _waitForRowLockWaiter(
  Connection writer,
  int pid,
  int blockerPid,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      Sql.named(
        'SELECT @blocker = ANY(pg_blocking_pids(@pid)) AND NOT EXISTS ( '
        "SELECT 1 FROM pg_locks l WHERE l.locktype = 'advisory' "
        'AND NOT l.granted AND l.pid = @pid)',
      ),
      parameters: {'pid': pid, 'blocker': blockerPid},
    );
    if (rows.single.single! as bool) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('session $pid never blocked on a row lock held by $blockerPid');
}

/// Waits until the backend [pid] is blocked on any lock (scoped to the pid).
Future<void> _waitForLockWaiter(Connection writer, int pid) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      Sql.named(
        'SELECT count(*) FROM pg_stat_activity '
        "WHERE pid = @pid AND wait_event_type = 'Lock'",
      ),
      parameters: {'pid': pid},
    );
    if ((rows.single.single! as int) > 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('session $pid never blocked on a lock');
}

/// Number of `helpOfferSubmitted` attention occurrences that mention [beacon].
Future<int> _helpOfferSubmittedCount(Connection writer, String beacon) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT count(*) FROM public.attention_occurrence '
      "WHERE event_type = 'helpOfferSubmitted' "
      "AND immutable_payload::text LIKE '%' || @b || '%'",
    ),
    parameters: {'b': beacon},
  );
  return rows.single.single! as int;
}

/// The backend pid of the test's own [writer] connection.
Future<int> _writerBackendPid(Connection writer) async {
  final rows = await writer.execute('SELECT pg_backend_pid()');
  return rows.single.single! as int;
}

/// The backend pid of [db]'s connection.
Future<int> _backendPid(TenturaDb db) async {
  final row = await db
      .customSelect('SELECT pg_backend_pid() AS pid')
      .getSingle();
  return row.read<int>('pid');
}

/// Number of `acknowledged` commitment events for [user] on [beacon].
Future<int> _acknowledgementCount(
  Connection writer,
  String beacon,
  String user,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT count(*) FROM public.beacon_commitment_event '
      'WHERE beacon_id = @b AND user_id = @u AND kind = 1',
    ),
    parameters: {'b': beacon, 'u': user},
  );
  return rows.single.single! as int;
}

/// Number of decline events recorded for [user] on [beacon].
Future<int> _declineEventCount(
  Connection writer,
  String beacon,
  String user,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT count(*) FROM public.beacon_help_offer_admission_event '
      'WHERE beacon_id = @b AND offer_user_id = @u AND action = 2',
    ),
    parameters: {'b': beacon, 'u': user},
  );
  return rows.single.single! as int;
}

Future<int> _offerStatus(Connection writer, String beacon, String user) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT status FROM public.beacon_help_offer '
      'WHERE beacon_id = @b AND user_id = @u',
    ),
    parameters: {'b': beacon, 'u': user},
  );
  return rows.single.single! as int;
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.trust_evidence,
  public.beacon_hierarchy_deliveries,
  public.beacon_hierarchy_events,
  public.attention_channel_delivery,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_child_commands,
  public.beacon_promotions,
  public.beacon_bud_observer,
  public.beacon_author_invite,
  public.post_first_response,
  public.user_availability,
  public.user_block,
  public.inbox_item,
  public.beacon_room_message,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('pbc9', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_postAuthor', '', '', 0, 1, 1, false, now())
''');
  // Forward edges admit the recipients as addressees (m0210).
  var n = 0;
  for (final recipient in [_budder, _budder2, _invitee, _other]) {
    n++;
    await writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, created_at)
VALUES ('Fpbc9e0$n', '$_post', '$_postAuthor', '$recipient',
        now() - interval '${60 - n} minutes')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  ('$_rootMsg', '$_post', '$_postAuthor', 'Who has a van?'),
  ('$_budderMsg', '$_post', '$_budder', 'I could organise the move'),
  ('$_budderMsg2', '$_post', '$_budder', 'And the boxes'),
  ('$_budder2Msg', '$_post', '$_budder2', 'I can lend a trolley')
''');
}

final class _Stack {
  _Stack({
    required this.buds,
    required this.invites,
    required this.beaconCase,
    required this.blocks,
    required this.posts,
    required this.helpOffers,
    required this.coordination,
    required this.closure,
  });

  final PostBudCase buds;
  final AuthorInviteCase invites;
  final BeaconCase beaconCase;
  final UserBlockCase blocks;
  final PostCase posts;
  final HelpOfferCase helpOffers;
  final CoordinationCase coordination;
  final ClosureCase closure;

  factory _Stack.build(
    TenturaDb db,
    Env env, {
    ClosureFinalizerPort? finalizer,
  }) {
    final logger = Logger('PostBudConcurrencyPgTest');
    final uow = MutatingUnitOfWork(db);
    final attention = TransactionalAttentionCase(
      uow,
      AttentionDispatchRepository(db, logger),
    );
    final settlement = AttentionSystemSettlementRepository(db);
    final room = BeaconRoomRepository(db);
    final helpOffers = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final beacons = BeaconRepository(db);
    final access = BeaconAccessRepository(db);
    final hierarchy = BeaconHierarchyRepository(db);
    final forwardEdges = ForwardEdgeRepository(db);
    final inbox = InboxRepository(db);
    final postLock = PostLockRepository(db);
    final witnessWindow = WitnessWindowRepository(db);
    final blockRepository = UserBlockRepository(
      env,
      db,
      witnessWindow: witnessWindow,
    );
    final users = UserRepository(
      env,
      db,
      _UnusedGenealogy(),
      InviteSeedPromptRepositoryMock(),
    );
    final coordinationRepository = CoordinationRepository(
      db,
      DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
      VoteUserFriendshipLookup(db),
      room,
    );
    final notificationContext = BeaconRoomNotificationContextRepository(
      room,
      db,
      helpOffers,
      commitments,
    );
    final intents = AttentionIntentCase(
      notificationContext,
      users,
      access,
      blockRepository,
    );
    final lifecycleEffects = BeaconLifecycleEffectsCase(
      BeaconHierarchyOutboxRepository(db),
      env: env,
      logger: logger,
    );
    final closure = ClosureCase(
      unitOfWork: uow,
      closureRepository: ClosureRepository(db),
      beaconRepository: beacons,
      commitmentRepository: commitments,
      helpOfferRepository: helpOffers,
      hierarchyRepository: hierarchy,
      lifecycleEffects: lifecycleEffects,
      attentionSystemSettlement: settlement,
      receipts: const NoopClosureReceipts(),
      finalizer: finalizer ?? _NoFinalizer(),
      env: env,
      logger: logger,
    );
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      helpOffers,
      env: env,
      logger: logger,
    );
    final capability = CapabilityEvidenceRepository(db);
    final authorInvites = AuthorInviteRepository(db);
    final postBud = PostBudRepository(db, _AllVisible());
    final forwardCase = ForwardCase(
      forwardEdges,
      ForwardAttributionRepository(db),
      helpOffers,
      inbox,
      capability,
      beacons,
      blockRepository,
      _AllVisible(),
      access,
      postLock: postLock,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    final anchorSweepPort = BudAnchorSweepRepository(db);
    final beaconCase = BeaconCase(
      beacons,
      _UnusedImages(),
      _UnusedImageGc(),
      _Tasks(),
      commitmentQuery,
      access,
      hierarchy,
      FakeBeaconChildCreatePort(),
      lifecycleEffects,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    return _Stack(
      closure: closure,
      coordination: CoordinationCase(
        beacons,
        helpOffers,
        coordinationRepository,
        room,
        blockRepository,
        commitments,
        commitmentQuery,
        hierarchy,
        attentionIntents: intents,
        attention: attention,
        attentionSystemSettlement: settlement,
        closureCase: closure,
        authorInvites: authorInvites,
        guard: FakeBeaconAccessGuard(),
        env: env,
        logger: logger,
      ),
      helpOffers: HelpOfferCase(
        helpOffers,
        beacons,
        commitments,
        inbox,
        CapabilityCase(
          PersonCapabilityEventRepository(db),
          env: env,
          logger: logger,
        ),
        FakeBeaconAccessGuard(),
        roomRepository: room,
        attentionIntents: intents,
        attention: attention,
        attentionSystemSettlement: settlement,
        closureCase: closure,
        authorInvites: authorInvites,
        coordinationRepository: coordinationRepository,
        env: env,
        logger: logger,
      ),
      buds: PostBudCase(
        BeaconChildCreateCase(
          beacons,
          hierarchy,
          BeaconHierarchyCommandRepository(db),
          access,
          notificationContext,
          attentionIntents: intents,
          attention: attention,
          postLock: postLock,
          postBud: postBud,
          env: env,
          logger: logger,
        ),
        postBud,
        forwardEdges,
        inbox,
        intents,
        PostCloseOperation(beacons),
        BudAnchorSweepCase(
          anchorSweepPort,
          AnchorInheritOperation(
            ConstellationAnchorRepository(db),
            anchorSweepPort,
          ),
          env: env,
          logger: logger,
        ),
      ),
      invites: AuthorInviteCase(
        attention,
        intents,
        settlement,
        AdmissionOperation(
          helpOffers,
          coordinationRepository,
          commitments,
          closure,
          settlement,
        ),
        authorInvites,
        postBud,
        beacons,
        closure,
        forwardEdges,
        inbox,
        blockRepository,
        commitments,
        forwardCase,
      ),
      beaconCase: beaconCase,
      blocks: UserBlockCase(
        uow,
        blockRepository,
        helpOffers,
        forwardEdges,
        UserContactRepository(db),
        users,
        beacons,
        commitments,
        inbox,
        capability,
        hierarchy,
        roomRepository: BeaconRoomRepository(db),
        trustLedger: TrustLedgerRepository(db),
        witnessWindow: witnessWindow,
        closureCase: closure,
        authorInvites: authorInvites,
        attentionSystemSettlement: settlement,
        env: env,
        logger: logger,
      ),
      posts: PostCase(
        beaconCase: beaconCase,
        forwardCase: forwardCase,
        roomCase: _UnusedRoomCase(),
        beaconRepository: beacons,
        postLock: postLock,
        attention: attention,
      ),
    );
  }
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _NoFinalizer extends Fake implements ClosureFinalizerPort {}

/// Closes the Request with the production status update after [gate].
final class _GatedClosingFinalizer implements ClosureFinalizerPort {
  _GatedClosingFinalizer(
    this._beacons, {
    required this.gate,
    this.fromStatus = BeaconStatus.open,
  });

  final BeaconRepository _beacons;
  final BeaconStatus fromStatus;
  final Future<void> Function() gate;

  @override
  Future<void> finalize({
    required String beaconId,
    required int epoch,
    required FinalizeReason reason,
  }) async {
    await gate();
    await _beacons.recordBeaconStatusTransition(
      beaconId: beaconId,
      fromStatus: fromStatus,
      toStatus: BeaconStatus.closed,
      reason: BeaconLifecycleChangeReason.closureExpired,
      actorId: null,
    );
  }
}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

/// `PostCase.leave` never reaches the room case.
final class _UnusedRoomCase extends Fake implements BeaconRoomCase {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}

final class _AllVisible extends Fake implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.toSet();
}
