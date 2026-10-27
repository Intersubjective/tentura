@Tags(['pg'])
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/invitation_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_contact_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/entity/forward_delivery_result.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/fake_user_block_repository.dart';

/// Post mutations take one lock sequence (hierarchy scope → per-request
/// advisory lock → beacon row) and re-check every mutable fact after it, so a
/// block committed while a forward is in flight is honoured and the two paths
/// can never deadlock. See `docs/plans/post-and-constellation-composer-plan.md`
/// §4.10.
const _author = 'Upostlockauth1';
const _recipient = 'Upostlockrcpt1';
const _bystander = 'Upostlockbyst1';
const _post = 'Bpostlockpost1';
const _mediaImage = 'd2990de0-1100-4000-8000-000000000001';

const _statusOpen = 0;
const _statusDraft = 3;
const _deadlockDetected = '40P01';
const _rounds = 20;
const _roundBudget = Duration(seconds: 10);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_LOCK_ORDER_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_lock',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Post lock order', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    // Drift keeps a single pooled connection per TenturaDb, so the two sides
    // of every race use separate databases to really run concurrently.
    late TenturaDb forwardDb;
    late TenturaDb blockDb;
    late _Stack forwardStack;
    late _Stack blockStack;
    late _UploadedImages uploadedImages;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      forwardDb = openDisposablePgDatabase(target);
      blockDb = openDisposablePgDatabase(target);
      uploadedImages = _UploadedImages(writer);
      forwardStack = _buildStack(
        forwardDb,
        target.databaseEnv,
        images: uploadedImages,
      );
      blockStack = _buildStack(blockDb, target.databaseEnv);
    });

    setUp(() async {
      await _resetFixture(writer);
      uploadedImages.objects.clear();
    });

    tearDownAll(() async {
      await blockDb.close();
      await tearDownDisposablePgWriter(session: session, drift: forwardDb);
    });

    group('lock helper', () {
      test(
        'waits for the global hierarchy lock held by another transaction',
        () async {
          final holder = await _openConnection(target);
          addTearDown(holder.close);
          await holder.execute('BEGIN');
          await holder.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
          );

          final acquired = _track(
            forwardStack.uow.run(
              actorUserId: _author,
              action: () => forwardStack.postLock.lockForPostMutation(_post),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 600));
          expect(acquired.isDone, isFalse, reason: 'lock is still held');

          await holder.execute('COMMIT');
          await acquired.future.timeout(_roundBudget);
        },
      );

      test('waits for the per-request advisory lock', () async {
        final holder = await _openConnection(target);
        addTearDown(holder.close);
        await holder.execute('BEGIN');
        await holder.execute(
          "SELECT pg_advisory_xact_lock(hashtextextended('$_post', 4242))",
        );

        final acquired = _track(
          forwardStack.uow.run(
            actorUserId: _author,
            action: () => forwardStack.postLock.lockForPostMutation(_post),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(acquired.isDone, isFalse, reason: 'lock is still held');

        await holder.execute('COMMIT');
        await acquired.future.timeout(_roundBudget);
      });

      test('waits for a row lock on the beacon', () async {
        final holder = await _openConnection(target);
        addTearDown(holder.close);
        await holder.execute('BEGIN');
        await holder.execute(
          "SELECT 1 FROM public.beacon WHERE id = '$_post' FOR UPDATE",
        );

        final acquired = _track(
          forwardStack.uow.run(
            actorUserId: _author,
            action: () => forwardStack.postLock.lockForPostMutation(_post),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(acquired.isDone, isFalse, reason: 'row lock is still held');

        await holder.execute('COMMIT');
        await acquired.future.timeout(_roundBudget);
      });

      test('returns promptly when nothing else holds a lock', () async {
        await forwardStack.uow
            .run<void>(
              actorUserId: _author,
              action: () => forwardStack.postLock.lockForPostMutation(_post),
            )
            .timeout(_roundBudget);
      });
    });

    group('forward of a Post', () {
      test('an open Post forwards to a recipient', () async {
        final result = await forwardStack.forwardCase.forward(
          senderId: _author,
          beaconId: _post,
          recipientIds: const [_recipient],
        );
        expect(result.deliveredRecipientIds, [_recipient]);
        expect(await _edgeCount(writer, _post, _recipient, liveOnly: true), 1);
        expect(await _isAdmitted(writer, _post, _recipient), isTrue);
      });

      test('an open Post permits invitation creation', () async {
        final invitation = await forwardStack.invitationCase.create(
          userId: _author,
          addresseeName: 'Newcomer',
          beaconId: _post,
        );
        expect(invitation.beaconId, _post);
      });

      test('an open Post permits its author to open forwarding', () async {
        await writer.execute("DELETE FROM public.beacon WHERE id = '$_post'");
        await writer.execute(
          "INSERT INTO public.beacon (id, user_id, title, description, status, kind, is_discoverable, published_at, forward_policy) VALUES ('$_post', '$_author', '', '', 0, 1, false, now(), 0)",
        );
        expect(
          await forwardStack.beaconCase.openForwarding(
            authorId: _author,
            id: _post,
          ),
          isTrue,
        );
        expect(
          (await writer.execute(
            "SELECT forward_policy FROM public.beacon WHERE id = '$_post'",
          )).single.single,
          1,
        );
      });

      for (final sender in [_author, _recipient]) {
        test(
          'expired Post refuses forward by ${sender == _author ? 'author' : 'member'}',
          () async {
            await writer.execute(
              "UPDATE public.beacon SET forward_policy = 1 WHERE id = '$_post'",
            );
            if (sender == _recipient) {
              await forwardStack.forwardCase.forward(
                senderId: _author,
                beaconId: _post,
                recipientIds: const [_recipient],
              );
            }
            await writer.execute(
              "UPDATE public.beacon SET expires_at = now() - interval '1 second' WHERE id = '$_post'",
            );
            final outcome = await _settle(
              forwardStack.forwardCase.forward(
                senderId: sender,
                beaconId: _post,
                recipientIds: const [_bystander],
              ),
            );
            expect(outcome.error, isA<ExceptionBase>());
            expect(
              await _edgeCount(writer, _post, _bystander, liveOnly: false),
              0,
            );
            expect(await _isAdmitted(writer, _post, _bystander), isFalse);
          },
        );
      }

      test('expired Post refuses opening forwarding', () async {
        await writer.execute(
          "DELETE FROM public.beacon WHERE id = '$_post'",
        );
        await writer.execute(
          "INSERT INTO public.beacon (id, user_id, title, description, status, kind, is_discoverable, published_at, forward_policy, expires_at) VALUES ('$_post', '$_author', '', '', 0, 1, false, now(), 0, now() - interval '1 second')",
        );
        final outcome = await _settle(
          forwardStack.beaconCase.openForwarding(authorId: _author, id: _post),
        );
        expect(outcome.error, isA<ExceptionBase>());
        expect(
          (await writer.execute(
            "SELECT forward_policy FROM public.beacon WHERE id = '$_post'",
          )).single.single,
          0,
        );
      });

      test('expired Post refuses creating an invitation', () async {
        await writer.execute(
          "UPDATE public.beacon SET expires_at = now() - interval '1 second' WHERE id = '$_post'",
        );
        final outcome = await _settle(
          forwardStack.invitationCase.create(
            userId: _author,
            addresseeName: 'Newcomer',
            beaconId: _post,
          ),
        );
        expect(outcome.error, isA<ExceptionBase>());
        expect(
          (await writer.execute(
            "SELECT count(*) FROM public.invitation WHERE beacon_id = '$_post'",
          )).single.single,
          0,
        );
      });

      for (final existing in [false, true]) {
        test(
          'expired Post refuses invitation acceptance ${existing ? 'by an existing account' : 'through accept'}',
          () async {
            const invitation = 'Iexpiredinvite1';
            await writer.execute(
              "INSERT INTO public.invitation (id, user_id, beacon_id) VALUES ('$invitation', '$_author', '$_post')",
            );
            await writer.execute(
              "UPDATE public.beacon SET expires_at = now() - interval '1 second' WHERE id = '$_post'",
            );
            final outcome = await _settle(
              existing
                  ? forwardStack.invitationCase.acceptAsExisting(
                      code: invitation,
                      userId: _recipient,
                    )
                  : forwardStack.invitationCase.accept(
                      invitationId: invitation,
                      userId: _recipient,
                    ),
            );
            expect(outcome.error, isA<ExceptionBase>());
            expect(
              await _edgeCount(writer, _post, _recipient, liveOnly: false),
              0,
            );
            expect(await _isAdmitted(writer, _post, _recipient), isFalse);
            expect(
              (await writer.execute(
                "SELECT count(*) FROM public.beacon_participant WHERE beacon_id = '$_post' AND user_id = '$_recipient'",
              )).single.single,
              0,
            );
            expect(
              (await writer.execute(
                "SELECT invited_id FROM public.invitation WHERE id = '$invitation'",
              )).single.single,
              isNull,
            );
          },
        );
      }

      test('expired Post refuses staging an image', () async {
        await writer.execute(
          "UPDATE public.beacon SET expires_at = now() - interval '1 second' WHERE id = '$_post'",
        );
        final outcome = await _settle(
          forwardStack.beaconCase.beaconStageImage(
            beaconId: _post,
            userId: _author,
            imageBytes: const Stream.empty(),
          ),
        );
        expect(
          uploadedImages.objects,
          isEmpty,
          reason: 'no uploaded object remains',
        );
        expect(
          (await writer.execute(
            "SELECT count(*) FROM public.image WHERE id = '$_mediaImage'",
          )).single.single,
          0,
          reason: 'no uploaded image row remains',
        );
        expect(outcome.error, isA<ExceptionBase>());
        expect(
          (await writer.execute(
            "SELECT count(*) FROM public.beacon_image_stage WHERE beacon_id = '$_post'",
          )).single.single,
          0,
        );
        expect(
          (await writer.execute(
            "SELECT count(*) FROM public.beacon_image WHERE beacon_id = '$_post'",
          )).single.single,
          0,
        );
      });

      test('expired Post refuses reconciling media', () async {
        await writer.execute(
          "INSERT INTO public.image (id, author_id) VALUES ('$_mediaImage', '$_author')",
        );
        await writer.execute(
          "INSERT INTO public.beacon_image_stage (image_id, beacon_id, staged_at) VALUES ('$_mediaImage', '$_post', now())",
        );
        await writer.execute(
          "UPDATE public.beacon SET expires_at = now() - interval '1 second' WHERE id = '$_post'",
        );
        final outcome = await _settle(
          forwardStack.beaconCase.beaconSetMedia(
            beaconId: _post,
            userId: _author,
            imageIds: const [],
            coverSource: 1,
          ),
        );
        expect(outcome.error, isA<ExceptionBase>());
        expect(
          (await writer.execute(
            "SELECT count(*) FROM public.beacon_image WHERE beacon_id = '$_post'",
          )).single.single,
          0,
        );
        expect(
          (await writer.execute(
            "SELECT count(*) FROM public.beacon_image_stage WHERE beacon_id = '$_post'",
          )).single.single,
          1,
        );
      });

      test(
        'a block committed after the beacon read but before the lock stops '
        'the forward from admitting the blocked recipient',
        () async {
          final reachedBarrier = Completer<void>();
          final resume = Completer<void>();
          forwardStack.forwardCase.beforeLockForTest = () async {
            reachedBarrier.complete();
            await resume.future;
          };
          addTearDown(() => forwardStack.forwardCase.beforeLockForTest = null);

          final forward = _settle(
            forwardStack.forwardCase.forward(
              senderId: _author,
              beaconId: _post,
              recipientIds: const [_recipient],
            ),
          );
          await reachedBarrier.future.timeout(_roundBudget);

          await blockStack.blockCase.block(
            blockerId: _recipient,
            blockedId: _author,
            cascadeMode: 0,
          );
          resume.complete();
          final outcome = await forward.timeout(_roundBudget);

          // The repo has no dedicated block exception; a block surfaces to the
          // sender as the same authorization failure the other recipient
          // checks raise.
          expect(
            outcome.error,
            isA<UnauthorizedException>().having(
              (e) => e.code.codeNumber,
              'code',
              const AuthExceptionCodes(
                AuthExceptionCode.authUnauthorizedException,
              ).codeNumber,
            ),
            reason:
                'a forward that resumed after the block must be rejected, not '
                'silently drop the recipient (result: '
                '${outcome.result?.deliveredRecipientIds})',
          );
          expect(_isDeadlock(outcome.error), isFalse);
          expect(
            await _edgeCount(writer, _post, _recipient, liveOnly: false),
            0,
            reason: 'no edge row of any state may be created for the recipient',
          );
          expect(await _isAdmitted(writer, _post, _recipient), isFalse);
        },
      );

      test(
        'a forward racing a block never deadlocks and never leaves the '
        'blocked recipient admitted',
        () async {
          for (var round = 0; round < _rounds; round++) {
            await _resetFixture(writer);

            final forward = _settle(
              forwardStack.forwardCase.forward(
                senderId: _author,
                beaconId: _post,
                recipientIds: const [_recipient],
              ),
            );
            final block = _settle(
              blockStack.blockCase.block(
                blockerId: _recipient,
                blockedId: _author,
                cascadeMode: 0,
              ),
            );
            final outcomes =
                await Future.wait([
                  forward,
                  block,
                ]).timeout(
                  _roundBudget,
                  onTimeout: () => fail('round $round did not finish in 10 s'),
                );

            for (final outcome in outcomes) {
              expect(
                _isDeadlock(outcome.error),
                isFalse,
                reason: 'round $round: deadlock_detected: ${outcome.error}',
              );
            }

            final forwardOutcome = outcomes[0];
            if (forwardOutcome.error != null) {
              expect(
                forwardOutcome.error,
                isA<ExceptionBase>(),
                reason:
                    'round $round: a forward that loses to the block fails '
                    'with a domain exception',
              );
              expect(
                await _edgeCount(writer, _post, _recipient, liveOnly: false),
                0,
                reason: 'round $round: a failed forward leaves no edge',
              );
            } else {
              final delivered =
                  forwardOutcome.result?.deliveredRecipientIds ??
                  const <String>[];
              expect(
                await _edgeCount(writer, _post, _recipient, liveOnly: false),
                delivered.contains(_recipient) ? 1 : 0,
                reason:
                    'round $round: a successful forward names the recipient '
                    'exactly when an edge was created for it',
              );
              expect(
                await _liveEdgeCount(writer, _post, _recipient),
                0,
                reason: 'round $round: the edge must be cancelled by the block',
              );
            }
            expect(
              await _isAdmitted(writer, _post, _recipient),
              isFalse,
              reason: 'round $round: blocked recipient must not stay admitted',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'an unrelated recipient is still admitted by the Post forward',
        () async {
          final result = await forwardStack.forwardCase.forward(
            senderId: _author,
            beaconId: _post,
            recipientIds: const [_bystander],
          );

          expect(result.deliveredRecipientIds, [_bystander]);
          expect(await _isAdmitted(writer, _post, _bystander), isTrue);
        },
      );
    });

    group('publish of a Post', () {
      test(
        'a publish racing a block never deadlocks and never leaves the '
        'blocked recipient admitted',
        () async {
          for (var round = 0; round < _rounds; round++) {
            await _resetFixture(writer);
            await _makeDraft(writer);

            final publish = _settle(
              forwardStack.postCase.publish(
                authorId: _author,
                beaconId: _post,
                body: 'Hello there',
                mentionUserIds: const [],
                mentionOffsets: const [],
                mentionLengths: const [],
                recipientIds: const [_recipient],
                notes: const {},
                forwardPolicy: BeaconForwardPolicyValue.closed,
              ),
            );
            final block = _settle(
              blockStack.blockCase.block(
                blockerId: _recipient,
                blockedId: _author,
                cascadeMode: 0,
              ),
            );
            final outcomes = await _raceRound(round, [publish, block]);
            expect(
              outcomes[1].error,
              isNull,
              reason: 'round $round: the block must succeed',
            );

            final publishOutcome = outcomes[0];
            if (publishOutcome.error != null) {
              expect(
                publishOutcome.error,
                isA<ExceptionBase>(),
                reason:
                    'round $round: a publish that loses to the block fails '
                    'with a domain exception',
              );
              expect(
                await _edgeCount(writer, _post, _recipient, liveOnly: false),
                0,
                reason: 'round $round: a failed publish leaves no edge',
              );
            } else {
              expect(
                await _edgeCount(writer, _post, _recipient, liveOnly: false),
                1,
                reason: 'round $round: a successful publish created B\'s edge',
              );
              expect(
                await _liveEdgeCount(writer, _post, _recipient),
                0,
                reason: 'round $round: the edge must be cancelled by the block',
              );
            }
            expect(
              await _isAdmitted(writer, _post, _recipient),
              isFalse,
              reason: 'round $round: blocked recipient must not stay admitted',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });

    group('cancelling forward edges', () {
      test(
        'two inbound edges cancelled in parallel leave the addressee without '
        'room access',
        () async {
          for (var round = 0; round < _rounds; round++) {
            await _resetFixture(writer);
            final authorEdge = await _insertEdge(writer, _author, _recipient);
            final bystanderEdge = await _insertEdge(
              writer,
              _bystander,
              _recipient,
            );
            expect(await _isAdmitted(writer, _post, _recipient), isTrue);

            final outcomes = await _raceRound(round, [
              _settle(
                forwardStack.forwardCase.cancelForward(
                  edgeId: authorEdge,
                  senderId: _author,
                ),
              ),
              _settle(
                blockStack.forwardCase.cancelForward(
                  edgeId: bystanderEdge,
                  senderId: _bystander,
                ),
              ),
            ]);

            for (final outcome in outcomes) {
              expect(
                outcome.error,
                isNull,
                reason: 'round $round: cancel must not throw',
              );
              expect(
                outcome.value,
                isTrue,
                reason: 'round $round: cancelForward must report success',
              );
            }
            expect(
              await _liveEdgeCount(writer, _post, _recipient),
              0,
              reason: 'round $round: both edges are cancelled',
            );
            expect(
              await _roomAccess(writer, _post, _recipient),
              0,
              reason: 'round $round: no live edge left, so no room access',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });

    group('cancelling a forward edge while the addressee leaves', () {
      test(
        'a cancellation queued behind a leave on the hierarchy lock does not '
        'take the edge first: the leave wins and the cancellation is refused',
        () async {
          for (var round = 0; round < _rounds; round++) {
            await _resetFixture(writer);
            final edgeId = await _insertEdge(writer, _author, _recipient);
            await writer.execute("""
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES ('$_recipient', '$_post', 1)
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = 1
""");
            expect(await _isAdmitted(writer, _post, _recipient), isTrue);

            final cancelPid = await _backendPid(forwardDb);
            final leavePid = await _backendPid(blockDb);
            // The writer holds the hierarchy scope while the leave and then
            // the cancellation queue behind it, so on release the leave gets
            // the hierarchy first: the interleaving of the deadlock.
            await writer.execute('BEGIN');
            late final Future<_Outcome> leave;
            late final Future<_Outcome> cancel;
            try {
              await writer.execute(
                'SELECT pg_advisory_xact_lock(hashtextextended('
                "'tentura.beacon_hierarchy.v1', 0))",
              );
              leave = _settle(
                blockStack.postCase.leave(userId: _recipient, beaconId: _post),
              );
              await _waitForHierarchyWaiter(writer, leavePid);
              cancel = _settle(
                forwardStack.forwardCase.cancelForward(
                  edgeId: edgeId,
                  senderId: _author,
                ),
              );
              await _waitForHierarchyWaiter(writer, cancelPid);
            } finally {
              await writer.execute('COMMIT');
            }

            final outcomes = await Future.wait([leave, cancel]).timeout(
              _roundBudget,
              onTimeout: () => fail('round $round did not finish'),
            );
            expect(
              outcomes[0].error,
              isNull,
              reason: 'round $round: the leave must succeed',
            );
            expect(
              outcomes[1].error,
              isNull,
              reason: 'round $round: the cancellation must not fail',
            );
            // The leave committed first and declined the delivery, so the
            // cancellation, re-checking after it holds its locks, is refused
            // and leaves the edge alone.
            expect(
              outcomes[1].value,
              isFalse,
              reason: 'round $round: a declined delivery cannot be cancelled',
            );
            expect(
              await _liveEdgeCount(writer, _post, _recipient),
              1,
              reason: 'round $round: the refused cancellation keeps the edge',
            );
            expect(
              await _roomAccess(writer, _post, _recipient),
              RoomAccessBits.left,
              reason: 'round $round: the addressee stays out of the room',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });

    group('leave of a Post', () {
      test(
        'a forward to the addressee racing their leave never deadlocks and '
        'leaves them out of the room',
        () async {
          for (var round = 0; round < _rounds; round++) {
            await _resetFixture(writer);
            await _insertEdge(writer, _bystander, _recipient);
            await writer.execute("""
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES ('$_recipient', '$_post', 0)
ON CONFLICT (user_id, beacon_id) DO NOTHING
""");
            expect(await _isAdmitted(writer, _post, _recipient), isTrue);

            final forward = _settle(
              forwardStack.forwardCase.forward(
                senderId: _author,
                beaconId: _post,
                recipientIds: const [_recipient],
              ),
            );
            final leave = _settle(
              blockStack.postCase.leave(
                userId: _recipient,
                beaconId: _post,
              ),
            );
            final outcomes = await _raceRound(round, [forward, leave]);

            expect(
              outcomes[1].error,
              isNull,
              reason: 'round $round: the leave must succeed',
            );
            for (final (side, outcome) in [
              ('forward', outcomes[0]),
              ('leave', outcomes[1]),
            ]) {
              expect(
                _isDeadlock(outcome.error),
                isFalse,
                reason:
                    'round $round: the $side side must not fail with '
                    '$_deadlockDetected deadlock_detected: ${outcome.error}',
              );
            }
            final forwardError = outcomes[0].error;
            if (forwardError != null) {
              // A forward that loses to the leave may be refused, but only
              // with a specific domain exception: an unspecified failure is
              // how a swallowed database error (deadlock, serialization)
              // would surface.
              expect(
                forwardError,
                isA<ExceptionBase>().having(
                  (e) => e,
                  'not an unspecified failure',
                  isNot(isA<UnspecifiedException>()),
                ),
                reason:
                    'round $round: a refused forward fails with a specific '
                    'domain exception: $forwardError',
              );
            }
            expect(
              await _roomAccess(writer, _post, _recipient),
              RoomAccessBits.left,
              reason:
                  'round $round: a forward arriving before or after the leave '
                  'must not readmit the addressee',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });

    group('invite accept of a Post', () {
      test(
        'an accept racing a block never deadlocks and leaves no admitted row',
        () async {
          for (var round = 0; round < _rounds; round++) {
            await _resetFixture(writer);
            final invitationId =
                'Ilockorder${round.toString().padLeft(3, '0')}';
            await writer.execute('''
INSERT INTO public.invitation (id, user_id, beacon_id)
VALUES ('$invitationId', '$_author', '$_post')
''');

            final accept = _settle(
              forwardStack.invitationCase.acceptAsExisting(
                code: invitationId,
                userId: _recipient,
              ),
            );
            final block = _settle(
              blockStack.blockCase.block(
                blockerId: _recipient,
                blockedId: _author,
                cascadeMode: 0,
              ),
            );
            final outcomes = await _raceRound(round, [accept, block]);
            expect(
              outcomes[1].error,
              isNull,
              reason: 'round $round: the block must succeed',
            );

            if (outcomes[0].error != null) {
              expect(
                outcomes[0].error,
                isA<ExceptionBase>(),
                reason:
                    'round $round: an accept that loses to the block fails '
                    'with a domain exception',
              );
            }
            expect(
              await _liveEdgeCount(writer, _post, _recipient),
              0,
              reason: 'round $round: no live edge may survive the block',
            );
            expect(
              await _isAdmitted(writer, _post, _recipient),
              isFalse,
              reason: 'round $round: blocked invitee must not stay admitted',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });
  });
}

_Tracked _track(Future<void> future) => _Tracked(future);

final class _Tracked {
  _Tracked(Future<void> future) {
    this.future = future.whenComplete(() => isDone = true);
  }

  late final Future<void> future;
  bool isDone = false;
}

typedef _Outcome = ({
  Object? error,
  ForwardDeliveryResult? result,
  Object? value,
});

Future<_Outcome> _settle(Future<Object?> action) async {
  try {
    final value = await action;
    return (
      error: null,
      result: value is ForwardDeliveryResult ? value : null,
      value: value,
    );
  } on Object catch (error) {
    return (error: error, result: null, value: null);
  }
}

Future<Connection> _openConnection(DisposablePgTarget target) =>
    Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );

/// Awaits both sides of a race, failing if a side deadlocks or the round
/// exceeds its time budget.
Future<List<_Outcome>> _raceRound(
  int round,
  List<Future<_Outcome>> sides,
) async {
  final outcomes = await Future.wait(sides).timeout(
    _roundBudget,
    onTimeout: () => fail('round $round did not finish in 10 s'),
  );
  for (final outcome in outcomes) {
    expect(
      _isDeadlock(outcome.error),
      isFalse,
      reason: 'round $round: deadlock_detected: ${outcome.error}',
    );
  }
  return outcomes;
}

Future<void> _makeDraft(Connection writer) => writer.execute(
  'UPDATE public.beacon SET status = $_statusDraft, published_at = NULL '
  "WHERE id = '$_post'",
);

Future<String> _insertEdge(
  Connection writer,
  String senderId,
  String recipientId,
) async {
  final id = 'F${senderId.substring(senderId.length - 10)}';
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('$id', '$_post', '$senderId', '$recipientId')
''');
  return id;
}

Future<int?> _roomAccess(
  Connection writer,
  String beaconId,
  String userId,
) async =>
    (await writer.execute('''
SELECT room_access FROM public.beacon_participant
WHERE beacon_id = '$beaconId' AND user_id = '$userId'
''')).singleOrNull?.single
        as int?;

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.invitation,
  public.user_block,
  public.user_block_intent,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_author, _recipient, _bystander]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at)
VALUES ('$_post', '$_author', '', '', $_statusOpen, 1, false, now())
''');
}

/// SQLSTATE `40P01`, however the driver or drift wrapped it.
bool _isDeadlock(Object? error) {
  if (error == null) return false;
  if (error is ServerException && error.code == _deadlockDetected) return true;
  final text = '$error'.toLowerCase();
  return text.contains(_deadlockDetected.toLowerCase()) ||
      text.contains('deadlock');
}

Future<int> _liveEdgeCount(
  Connection writer,
  String beaconId,
  String recipientId,
) => _edgeCount(writer, beaconId, recipientId, liveOnly: true);

Future<int> _edgeCount(
  Connection writer,
  String beaconId,
  String recipientId, {
  required bool liveOnly,
}) async =>
    (await writer.execute('''
SELECT count(*) FROM public.beacon_forward_edge
WHERE beacon_id = '$beaconId' AND recipient_id = '$recipientId'
  ${liveOnly ? 'AND cancelled_at IS NULL' : ''}
''')).single.single!
        as int;

Future<bool> _isAdmitted(
  Connection writer,
  String beaconId,
  String userId,
) async => (await writer.execute('''
SELECT 1 FROM public.beacon_participant
WHERE beacon_id = '$beaconId' AND user_id = '$userId'
  AND room_access = ${RoomAccessBits.admitted}
''')).isNotEmpty;

final class _Stack {
  const _Stack({
    required this.forwardCase,
    required this.blockCase,
    required this.postCase,
    required this.beaconCase,
    required this.invitationCase,
    required this.postLock,
    required this.uow,
  });

  final ForwardCase forwardCase;
  final UserBlockCase blockCase;
  final PostCase postCase;
  final BeaconCase beaconCase;
  final InvitationCase invitationCase;
  final PostLockPort postLock;
  final MutatingUnitOfWork uow;
}

_Stack _buildStack(TenturaDb db, Env env, {ImageRepositoryPort? images}) {
  final logger = Logger('PostLockOrderPgTest');
  final uow = MutatingUnitOfWork(db);
  final postLock = PostLockRepository(db);
  final hierarchy = BeaconHierarchyRepository(db);
  final beacons = BeaconRepository(db);
  final helpOffers = HelpOfferRepository(db);
  final inbox = InboxRepository(db);
  final capability = CapabilityEvidenceRepository(db);
  final forwardEdges = ForwardEdgeRepository(db);
  final witnessWindow = WitnessWindowRepository(db);
  final blocks = UserBlockRepository(
    env,
    db,
    witnessWindow: witnessWindow,
  );
  final users = UserRepository(
    env,
    db,
    _NoopInviteGenealogyRepository(),
    InviteSeedPromptRepositoryMock(),
  );
  final attention = TransactionalAttentionCase(
    uow,
    AttentionDispatchRepository(db, logger),
  );
  final roomRepository = BeaconRoomRepository(db);
  final commitments = CommitmentRepository(db);
  final access = BeaconAccessRepository(db);
  final intents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      roomRepository,
      db,
      helpOffers,
      commitments,
    ),
    users,
    FakeBeaconAccessGuard(),
    FakeUserBlockRepository(),
  );
  final imageRepo = images ?? _UnusedImages();
  final tasks = _Tasks();
  final forwardCase = ForwardCase(
    forwardEdges,
    ForwardAttributionRepository(db),
    helpOffers,
    inbox,
    capability,
    beacons,
    blocks,
    _AllVisiblePeers(),
    access,
    postLock: postLock,
    attentionIntents: intents,
    attention: attention,
    env: env,
    logger: logger,
  );
  final roomCase = BeaconRoomCase(
    roomRepository,
    CoordinationItemRepository(db),
    _UnusedFactCards(),
    imageRepo,
    tasks,
    _Storage(),
    _UnusedPolling(),
    _Quota(),
    blocks,
    uow,
    hierarchy,
    const ProductionDiscussionProductPolicy(),
    attentionIntents: intents,
    attention: attention,
    env: env,
    logger: logger,
  );
  final beaconCase = BeaconCase(
    beacons,
    imageRepo,
    _UnusedImageGc(),
    tasks,
    CommitmentQueryCase(commitments, helpOffers, env: env, logger: logger),
    access,
    hierarchy,
    FakeBeaconChildCreatePort(),
    BeaconLifecycleEffectsCase(
      BeaconHierarchyOutboxRepository(db),
      env: env,
      logger: logger,
    ),
    attentionIntents: intents,
    attention: attention,
    env: env,
    logger: logger,
  );

  return _Stack(
    uow: uow,
    postLock: postLock,
    forwardCase: forwardCase,
    beaconCase: beaconCase,
    postCase: PostCase(
      beaconCase: beaconCase,
      forwardCase: forwardCase,
      roomCase: roomCase,
      beaconRepository: beacons,
      postLock: postLock,
      attention: attention,
    ),
    invitationCase: InvitationCase(
      InvitationRepository(db),
      users,
      beacons,
      VoteUserFriendshipLookup(db),
      UserContactRepository(db),
      FakeBeaconAccessGuard(),
      forwardEdges,
      blocks,
      postLock: postLock,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    ),
    blockCase: UserBlockCase(
      uow,
      blocks,
      helpOffers,
      forwardEdges,
      UserContactRepository(db),
      users,
      beacons,
      CommitmentRepository(db),
      inbox,
      capability,
      hierarchy,
      roomRepository: BeaconRoomRepository(db),
      trustLedger: TrustLedgerRepository(db),
      witnessWindow: witnessWindow,
      env: env,
      logger: logger,
    ),
  );
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

class _UnusedImages extends Fake implements ImageRepositoryPort {
  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async => _mediaImage;

  @override
  Future<List<String>> listOwnedIds({required String authorId}) async => [
    _mediaImage,
  ];

  @override
  Future<void> compensateOrphanedUpload({
    required String imageId,
    required String authorId,
  }) async {}

  @override
  Future<int> deleteOwnedRow({
    required String imageId,
    required String authorId,
  }) async => 1;
}

final class _UploadedImages extends _UnusedImages {
  _UploadedImages(this.writer);
  final Connection writer;
  final objects = <String>{};

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async {
    await bytes.drain<void>();
    await writer.execute(
      Sql.named(
        'INSERT INTO public.image (id, author_id) VALUES (@id, @author)',
      ),
      parameters: {'id': _mediaImage, 'author': authorId},
    );
    objects.add(_mediaImage);
    return _mediaImage;
  }

  @override
  Future<void> compensateOrphanedUpload({
    required String imageId,
    required String authorId,
  }) async {
    await writer.execute(
      Sql.named(
        'DELETE FROM public.image WHERE id = @id AND author_id = @author',
      ),
      parameters: {'id': imageId, 'author': authorId},
    );
    objects.remove(imageId);
  }
}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {
  @override
  Future<void> enqueue({
    required String imageId,
    required String authorId,
  }) async {}
}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedPolling extends Fake implements PollingRepositoryPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}

final class _Storage extends Fake implements RemoteStoragePort {
  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    return path;
  }
}

final class _Quota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}

final class _AllVisiblePeers extends Fake
    implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.toSet();
}

Future<int> _backendPid(TenturaDb db) async {
  final row = await db
      .customSelect('SELECT pg_backend_pid() AS pid')
      .getSingle();
  return row.read<int>('pid');
}

/// Waits until backend [pid] waits for the hierarchy advisory lock. Scoped to
/// this database, that key and that pid (`pg_locks` is cluster-wide).
Future<void> _waitForHierarchyWaiter(Connection writer, int pid) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      'SELECT 1 FROM pg_locks l '
      "WHERE l.locktype = 'advisory' AND NOT l.granted AND l.objsubid = 1 "
      'AND ((l.classid::bigint << 32) | l.objid::bigint) = '
      "hashtextextended('tentura.beacon_hierarchy.v1', 0) "
      'AND l.pid = $pid AND l.database = '
      '(SELECT oid FROM pg_database WHERE datname = current_database())',
    );
    if (rows.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('backend $pid never waited for the hierarchy lock');
}
