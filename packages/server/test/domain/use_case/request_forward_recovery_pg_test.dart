@Tags(['pg', 'multi-connection'])
library;

import 'dart:async';
// The VM runner supports mirrors, which the Flutter workspace analyzer hides.
// ignore: uri_does_not_exist
import 'dart:mirrors' as vm;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/phantom_pending_forward.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/phantom_merge_repository_port.dart';
import 'package:tentura_server/domain/port/phantom_merge_wake_port.dart';
import 'package:tentura_server/domain/port/phantom_pending_forward_repository_port.dart';
import 'package:tentura_server/domain/port/phantom_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/domain/use_case/phantom_forward_delivery_case.dart';
import 'package:tentura_server/domain/use_case/phantom_merge_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/owner_graph_contention.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';
import '../../support/session_database_di_harness.dart';

const _sender = 'UrecoverySndr';
const _joiner = 'UrecoveryJoin';
const _oldRecipient = 'UrecoveryPrev';
const _senderName = 'Vadim';
const _note = 'Can you help on Saturday?';
const _forwardWriteGate = 78127001;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_RECOVERY_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_recovery',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  group('Recovering Request forwards after invite acceptance', () {
    late _Fixture fixture;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      await enforceOwnerScope(session);
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      getIt.registerSingleton<PhantomMergeWakePort>(
        const PhantomMergeWakePort.disabled(),
      );
      await configureSessionDatabaseTestGraph(target.databaseEnv);
      fixture = _Fixture(session.writer);
    });

    setUp(() => fixture.reset());

    group('Overlapping delivery and Request changes', () {
      for (final undoFirst in [true, false]) {
        test(
          undoFirst
              ? 'undo restores the pending forward before delivery can send it'
              : 'undo preserves a forward and receipt delivered first',
          () async {
            final request = await fixture.prepareForward();
            final claim = (await fixture.acceptInviteWithoutDelivery()).single;
            Future<void> undo() async {
              expect(
                await getIt<PhantomMergeCase>().unmerge(
                  ownerId: _sender,
                  phantomId: fixture.person,
                  mergeId: claim.mergeId,
                ),
                isTrue,
              );
            }

            Future<void> deliver() =>
                getIt<PhantomForwardDeliveryCase>().deliver([claim]);

            await fixture.overlapWrites(
              target.databaseEnv,
              pauseOn: 'UPDATE OF state ON public.phantom_pending_forward',
              when: undoFirst
                  ? "OLD.state = 'claimed' AND NEW.state = 'pending'"
                  : "OLD.state = 'claimed' AND NEW.state = 'delivered'",
              first: undoFirst ? undo : deliver,
              second: undoFirst ? deliver : undo,
            );

            expect(await fixture.currentMerge(), isNull);
            if (undoFirst) {
              final row = await fixture.readForward(claim.id);
              expect(row.state, PhantomPendingForwardState.pending);
              expect(row.mergeId, isNull);
              expect(row.recipientId, isNull);
              expect(row.forwardEdgeId, isNull);
              expect(row.lapseReason, isNull);
              expect(await fixture.forwardEdges(request), isEmpty);
              expect(await fixture.joinerReceipts(claim), isEmpty);
            } else {
              await fixture.expectDelivered(claim);
              expect(await fixture.joinerReceipts(claim), ['relayReceived']);
            }
          },
        );
      }

      for (final closeFirst in [true, false]) {
        test(
          closeFirst
              ? 'closing first replaces delivery with one lapsed joiner card'
              : 'closing after delivery preserves the forward without a lapsed card',
          () async {
            final request = await fixture.prepareForward();
            final claim = (await fixture.acceptInviteWithoutDelivery()).single;
            Future<void> close() => getIt<ClosureCase>().close(
              authorId: _sender,
              beaconId: request,
            );

            Future<void> deliver() =>
                getIt<PhantomForwardDeliveryCase>().deliver([claim]);

            await fixture.overlapWrites(
              target.databaseEnv,
              pauseOn: closeFirst
                  ? 'UPDATE OF status ON public.beacon'
                  : 'UPDATE OF state ON public.phantom_pending_forward',
              when: closeFirst
                  ? 'NEW.status = ${BeaconStatus.closed.smallintValue}'
                  : "OLD.state = 'claimed' AND NEW.state = 'delivered'",
              first: closeFirst ? close : deliver,
              second: closeFirst ? deliver : close,
            );

            expect(await fixture.requestStatus(request), BeaconStatus.closed);
            if (closeFirst) {
              final row = await fixture.readForward(claim.id);
              expect(row.state, PhantomPendingForwardState.lapsed);
              expect(row.lapseReason, 'forward_no_longer_allowed');
              expect(row.forwardEdgeId, isNull);
              expect(row.resolvedAt, isNotNull);
              expect(await fixture.forwardEdges(request), isEmpty);
              expect(await fixture.joinerReceipts(claim), [
                'requestForwardLapsed',
              ]);
              final cards = await fixture.lapsedJoinerCards();
              expect(cards, hasLength(1));
              expect(cards.single.actorUserId, _sender);
              expect(
                cards.single.destinationKind,
                AttentionDestinationKind.safeTerminal,
              );
              expect(
                cards.single.presentationPayload['eventType'],
                'requestForwardLapsed',
              );
            } else {
              await fixture.expectDelivered(claim);
              expect(await fixture.joinerReceipts(claim), ['relayReceived']);
              expect(await fixture.lapsedJoinerCards(), isEmpty);
            }
          },
        );
      }

      test('overlapping sweeps send a claimed forward only once', () async {
        await fixture.prepareForward();
        final claim = (await fixture.acceptInviteWithoutDelivery()).single;
        final delivery = getIt<PhantomForwardDeliveryCase>();

        await fixture.overlapWrites(
          target.databaseEnv,
          pauseOn: 'UPDATE OF state ON public.phantom_pending_forward',
          when: "OLD.state = 'claimed' AND NEW.state = 'delivered'",
          first: delivery.sweep,
          second: delivery.sweep,
        );

        final delivered = await fixture.expectDelivered(claim);
        final resolvedAt = await fixture.storedResolutionTime(claim.id);
        expect(resolvedAt, isNotNull);
        final receipts = await fixture.joinerReceipts(claim);
        expect(receipts, ['relayReceived']);

        await _expectNoDeliveryErrors(
          () =>
              expectLater(delivery.sweep().timeout(kCompletionWait), completes),
        );

        expect(await fixture.expectDelivered(claim), delivered);
        expect(await fixture.storedResolutionTime(claim.id), resolvedAt);
        expect(await fixture.joinerReceipts(claim), receipts);
      });
    });

    test(
      'a missed delivery gives the joiner access through the saved forward',
      () async {
        final request = await fixture.prepareForward();
        final claim = (await fixture.acceptInviteWithoutDelivery()).single;
        expect(await fixture.currentMerge(), claim.mergeId);
        expect(await fixture.forwardEdges(request), isEmpty);
        expect(await fixture.canRead(request), isFalse);

        await _sweep();

        await fixture.expectDelivered(claim);
        expect(await fixture.canRead(request), isTrue);
      },
    );

    test(
      'a claim for a replaced merge lapses without forwarding to anyone',
      () async {
        final request = await fixture.prepareForward();
        final claim = (await fixture.acceptInviteWithoutDelivery()).single;
        final staleMerge = await fixture.moveClaimToPreviousMerge(claim.id);
        expect(await fixture.currentMerge(), claim.mergeId);
        expect(staleMerge, isNot(claim.mergeId));
        final stale = await fixture.readForward(claim.id);
        expect(stale.state, PhantomPendingForwardState.claimed);
        expect(stale.mergeId, staleMerge);
        expect(stale.recipientId, _oldRecipient);

        await _sweep();

        expect(await fixture.forwardEdges(request), isEmpty);
        await fixture.expectRecipientGone(claim.id);
      },
    );

    test(
      'an erased recipient frees the claimed slot without a joiner card',
      () async {
        final request = await fixture.prepareForward();
        final claim = (await fixture.acceptInviteWithoutDelivery()).single;
        expect(await getIt<UserCase>().deleteById(id: _joiner), isTrue);
        final erased = await fixture.readForward(claim.id);
        expect(erased.state, PhantomPendingForwardState.claimed);
        expect(erased.mergeId, isNull);
        expect(erased.recipientId, isNull);
        expect(await fixture.currentMerge(), isNull);
        final eventsBefore = await fixture.attentionEvents();
        await expectLater(
          fixture.insertPending(request),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'SQLSTATE', '23505'),
          ),
        );

        await _sweep();

        expect(await fixture.forwardEdges(request), isEmpty);
        expect(await fixture.attentionEvents(), eventsBefore);
        await fixture.expectRecipientGone(claim.id);
        final newId = await fixture.insertPending(request);
        expect(
          (await fixture.readForward(newId)).state,
          PhantomPendingForwardState.pending,
        );
      },
    );

    test(
      'a recovery pass preserves cancelled deliveries, terminal lapses and forwards restored by unmerge',
      () async {
        final cancelledRequest = await fixture.prepareForward();
        final lapsedRequest = await fixture.prepareForward();
        final recoverableRequest = await fixture.prepareForward();
        final claims = await fixture.acceptInviteWithoutDelivery();
        final cancelled = claims.singleWhere(
          (c) => c.beaconId == cancelledRequest,
        );
        final lapsed = claims.singleWhere((c) => c.beaconId == lapsedRequest);
        final recoverable = claims.singleWhere(
          (c) => c.beaconId == recoverableRequest,
        );

        await getIt<PhantomForwardDeliveryCase>().deliver([cancelled]);
        final delivered = await fixture.expectDelivered(cancelled);
        expect(
          await getIt<ForwardCase>().cancelForward(
            edgeId: delivered.forwardEdgeId!,
            senderId: _sender,
          ),
          isTrue,
        );
        final cancelledEdges = await fixture.forwardEdges(cancelledRequest);
        expect(cancelledEdges.single['cancelled_at'], isA<DateTime>());

        // Start with a terminal lapse on an open Request, so a retry could
        // otherwise forward it under the same conditions as the live claim.
        await fixture.seedTerminalLapse(lapsed);
        final terminal = await fixture.readForward(lapsed.id);
        expect(terminal.state, PhantomPendingForwardState.lapsed);
        expect(terminal.lapseReason, 'forward_no_longer_allowed');
        expect(terminal.resolvedAt, isNotNull);

        final pendingPerson = await fixture.createMapEntry();
        final pendingRequest = await fixture.prepareForward(
          person: pendingPerson,
        );
        final undoneClaim = (await fixture.acceptInviteWithoutDelivery(
          person: pendingPerson,
          recipient: _oldRecipient,
        )).single;
        expect(
          await getIt<PhantomMergeCase>().unmerge(
            ownerId: _sender,
            phantomId: pendingPerson,
            mergeId: undoneClaim.mergeId,
          ),
          isTrue,
        );
        expect(await fixture.currentMerge(person: pendingPerson), isNull);
        final pending = await fixture.readForward(undoneClaim.id);
        expect(pending.state, PhantomPendingForwardState.pending);
        expect(pending.mergeId, isNull);
        expect(pending.recipientId, isNull);
        expect(pending.forwardEdgeId, isNull);

        await _sweep();

        expect(await fixture.readForward(cancelled.id), delivered);
        expect(await fixture.forwardEdges(cancelledRequest), cancelledEdges);
        expect(await fixture.readForward(lapsed.id), terminal);
        expect(await fixture.forwardEdges(lapsedRequest), isEmpty);
        expect(await fixture.readForward(pending.id), pending);
        expect(await fixture.forwardEdges(pendingRequest), isEmpty);
        await fixture.expectDelivered(recoverable);
      },
    );

    for (final alreadyConnected in [false, true]) {
      test(
        alreadyConnected
            ? 'a closed Request card confirms the connection for an already connected joiner'
            : 'a closed Request card tells the joiner about their new connection',
        () async {
          if (alreadyConnected) await fixture.seedMutualTrust(_joiner);
          expect(await fixture.joinerIsConnected(), alreadyConnected);
          final request = await fixture.prepareForward();
          final claim = (await fixture.acceptInviteWithoutDelivery()).single;
          expect(await fixture.joinerIsConnected(), isTrue);
          await getIt<ClosureCase>().close(
            authorId: _sender,
            beaconId: request,
          );
          final eventsBefore = await fixture.attentionEvents();

          await _sweep();

          final lapsed = await fixture.readForward(claim.id);
          final eventsAdded = (await fixture.attentionEvents()).difference(
            eventsBefore,
          );
          expect(
            (state: lapsed.state, newEvents: eventsAdded.length),
            (state: PhantomPendingForwardState.lapsed, newEvents: 1),
            reason:
                'The sweep should lapse the claim and record one joiner card.',
          );
          expect(lapsed.lapseReason, 'forward_no_longer_allowed');
          expect(lapsed.resolvedAt, isNotNull);
          expect(await fixture.forwardEdges(request), isEmpty);
          final event = eventsAdded.single;
          expect(event.actor, _sender);
          expect(event.account, _joiner);

          final english = await fixture.renderCard(event, request, 'en');
          final russian = await fixture.renderCard(event, request, 'ru');
          expect(
            english.sentence,
            "Vadim sent you a request; it has since closed. You're connected with Vadim.",
          );
          expect(
            russian.sentence,
            allOf(contains(_senderName), contains('запрос')),
          );
          final internalWords = RegExp(
            'phantom|placeholder|фантом|плейсхолдер',
            caseSensitive: false,
          );
          for (final copy in [english, russian]) {
            expect(copy.headline, isNot(matches(internalWords)));
            expect(copy.sentence, isNot(matches(internalWords)));
          }

          await _sweep();

          expect(await fixture.readForward(claim.id), lapsed);
          expect((await fixture.attentionEvents()).difference(eventsBefore), {
            event,
          });
        },
      );
    }
  }, skip: skip);
}

// Keep the red baseline compilable until the retry entry point exists.
// Assertions inspect database effects, so an absent or empty sweep stays red.
Future<void> _sweep() async {
  final delivery = vm.reflect(getIt<PhantomForwardDeliveryCase>());
  if (!delivery.type.instanceMembers.containsKey(#sweep)) return;
  final Object? sweep = delivery.getField(#sweep).reflectee;
  if (sweep is! Future<void> Function()) {
    fail('The delivery sweep must be callable without supplying claim IDs.');
  }
  await sweep();
}

typedef _AttentionEvent = ({String id, String? actor, String? account});

Future<void> _expectNoDeliveryErrors(Future<void> Function() run) async {
  final failures = <LogRecord>[];
  final rootLogger = Logger.root;
  final previousLevel = rootLogger.level;
  rootLogger.level = Level.SEVERE;
  final subscription = rootLogger.onRecord
      .where(
        (record) =>
            record.level == Level.SEVERE &&
            record.message.startsWith('Could not deliver pending forward'),
      )
      .listen(failures.add);
  try {
    await run();
  } finally {
    await subscription.cancel();
    rootLogger.level = previousLevel;
  }
  expect(
    failures.map((record) => '${record.message}: ${record.error}'),
    isEmpty,
    reason: 'Delivery must finish without logging a swallowed error.',
  );
}

final class _Fixture {
  _Fixture(this.writer);

  final Connection writer;
  late String person;
  final _invites = <String, String>{};

  Future<Result> _sql(
    String statement, [
    Map<String, Object?> parameters = const {},
  ]) => writer.execute(Sql.named(statement), parameters: parameters);

  Future<void> reset() async {
    await writer.execute(
      'TRUNCATE public."user", public.attention_occurrence CASCADE',
    );
    for (final (index, id) in [_sender, _joiner, _oldRecipient].indexed) {
      await _sql(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
''',
        {
          'id': id,
          'name': id == _sender ? _senderName : id,
          'key': pgTestPublicKey('forwardrecovery', index + 1),
        },
      );
    }
    person = await createMapEntry();
    _invites.clear();
  }

  Future<String> createMapEntry() =>
      getIt<PhantomCase>().create(ownerId: _sender, name: 'Neighbour');

  Future<String> prepareForward({String? person}) async {
    final row = await _sql(
      '''
INSERT INTO public.beacon (
  user_id, title, description, status, kind, is_discoverable, published_at
)
VALUES (@sender, 'Help with the garden', 'Saturday morning', 0, 0, false, now())
RETURNING id
''',
      {'sender': _sender},
    );
    final request = row.single.single! as String;
    final mapEntry = person ?? this.person;
    final code = await getIt<PhantomCase>().forwardRequest(
      ownerId: _sender,
      phantomId: mapEntry,
      beaconId: request,
      note: _note,
    );
    _invites[mapEntry] = code;
    return request;
  }

  Future<List<PhantomForwardClaim>> acceptInviteWithoutDelivery({
    String? person,
    String recipient = _joiner,
  }) async {
    final mapEntry = person ?? this.person;
    final code = _invites[mapEntry];
    if (code == null) fail('No invite was created for this map entry.');
    expect(
      await getIt<InvitationCase>().acceptAsExisting(
        code: code,
        userId: recipient,
      ),
      InviteAcceptance.accepted,
    );
    final interruptedDelivery = _InterruptedDeliveryTransaction();
    final merge = PhantomMergeCase(
      getIt<OwnerGraphTransactionPort>(),
      getIt<PhantomRepositoryPort>(),
      getIt<PhantomMergeRepositoryPort>(),
      getIt<UserBlockRepositoryPort>(),
      getIt<PhantomPendingForwardRepositoryPort>(),
      PhantomForwardDeliveryCase(
        interruptedDelivery,
        getIt<PostLockPort>(),
        getIt<PhantomPendingForwardRepositoryPort>(),
        getIt<TransactionalAttentionCase>(),
        getIt<ForwardCase>(),
        Logger('Interrupted post-commit delivery'),
      ),
      Logger('Request forward recovery test'),
    );
    await merge.runDue(leaseOwner: 'test-worker', clock: DateTime.timestamp);

    final rows = await _sql(
      '''
SELECT id, sender_id, beacon_id, parent_forward_edge_id, merge_id, recipient_id
FROM public.phantom_pending_forward
WHERE phantom_id = @person AND state = 'claimed'
ORDER BY id
''',
      {'person': mapEntry},
    );
    expect(rows, isNotEmpty);
    expect(interruptedDelivery.attempts, rows.length);
    final current = await currentMerge(person: mapEntry);
    expect(current, isNotNull);
    for (final row in rows) {
      expect(row[4], current);
      expect(row[5], recipient);
    }
    return [
      for (final row in rows.map((row) => row.toColumnMap()))
        (
          id: row['id']! as String,
          senderId: row['sender_id']! as String,
          beaconId: row['beacon_id']! as String,
          parentForwardEdgeId: row['parent_forward_edge_id'] as String?,
          mergeId: row['merge_id']! as String,
        ),
    ];
  }

  Future<String?> currentMerge({String? person}) async =>
      (await _sql(
            'SELECT current_merge_id FROM public.phantom WHERE id = @person',
            {'person': person ?? this.person},
          )).single.single
          as String?;

  Future<String> moveClaimToPreviousMerge(String id) async {
    final oldMerge = generateId('PM');
    await writer.executeWithOwnerScopes(
      [_sender],
      Sql.named('''
WITH previous_merge AS (
  INSERT INTO public.phantom_merge
    (id, phantom_id, owner_id, user_id, origin, undo, created_at, undone_at)
  VALUES (@oldMerge, @person, @sender, @oldRecipient, 2, '{}'::jsonb,
          now() - interval '2 days', now() - interval '1 day')
  RETURNING id
)
UPDATE public.phantom_pending_forward
SET merge_id = (SELECT id FROM previous_merge), recipient_id = @oldRecipient
WHERE id = @id
'''),
      parameters: {
        'id': id,
        'person': person,
        'sender': _sender,
        'oldMerge': oldMerge,
        'oldRecipient': _oldRecipient,
      },
    );
    await seedMutualTrust(_oldRecipient);
    return oldMerge;
  }

  Future<void> seedMutualTrust(String recipient) => _sql(
    '''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@sender, @recipient, 1), (@recipient, @sender, 1)
''',
    {'sender': _sender, 'recipient': recipient},
  );

  Future<bool> joinerIsConnected() =>
      getIt<VoteUserFriendshipLookupPort>().isReciprocalSubscribe(
        viewerId: _joiner,
        peerId: _sender,
      );

  Future<String> insertPending(String request) async {
    final rows = await writer.executeWithOwnerScopes(
      [_sender],
      Sql.named('''
INSERT INTO public.phantom_pending_forward (id, phantom_id, sender_id, beacon_id, note)
VALUES (@id, @person, @sender, @request, @note)
RETURNING id
'''),
      parameters: {
        'id': generateId('PF'),
        'person': person,
        'sender': _sender,
        'request': request,
        'note': _note,
      },
    );
    return rows.single.single! as String;
  }

  Future<PhantomPendingForward> readForward(String id) async {
    final row = await getIt<PhantomPendingForwardRepositoryPort>().findById(
      senderId: _sender,
      id: id,
    );
    expect(row, isNotNull);
    return row!;
  }

  Future<void> expectRecipientGone(String id) async {
    final row = await readForward(id);
    expect(row.state, PhantomPendingForwardState.lapsed);
    expect(row.lapseReason, 'recipient_gone');
    expect(row.resolvedAt, isNotNull);
    expect(row.forwardEdgeId, isNull);
  }

  Future<PhantomPendingForward> expectDelivered(
    PhantomForwardClaim claim,
  ) async {
    final row = await readForward(claim.id);
    expect(row.state, PhantomPendingForwardState.delivered);
    expect(row.resolvedAt, isNotNull);
    expect(row.forwardEdgeId, isNotNull);
    expect(await forwardEdges(claim.beaconId), [
      {
        'id': row.forwardEdgeId,
        'sender_id': _sender,
        'recipient_id': _joiner,
        'cancelled_at': null,
      },
    ]);
    return row;
  }

  Future<void> seedTerminalLapse(PhantomForwardClaim claim) =>
      getIt<OwnerGraphTransactionPort>().run(
        {_sender},
        _sender,
        (scope) => getIt<PhantomPendingForwardRepositoryPort>().resolve(
          scope,
          claim,
          PhantomForwardLapsed.forwardNoLongerAllowed,
        ),
      );

  Future<List<Map<String, Object?>>> forwardEdges(String request) async => [
    for (final row in await _sql(
      '''
SELECT id, sender_id, recipient_id, cancelled_at
FROM public.beacon_forward_edge WHERE beacon_id = @request ORDER BY id
''',
      {'request': request},
    ))
      row.toColumnMap(),
  ];

  Future<BeaconStatus> requestStatus(String request) async {
    final rows = await _sql(
      'SELECT status FROM public.beacon WHERE id = @request',
      {'request': request},
    );
    return BeaconStatus.fromSmallint(rows.single.single! as int);
  }

  Future<DateTime?> storedResolutionTime(String id) async {
    final rows = await _sql(
      'SELECT resolved_at FROM public.phantom_pending_forward WHERE id = @id',
      {'id': id},
    );
    return rows.single.single as DateTime?;
  }

  Future<List<String>> joinerReceipts(PhantomForwardClaim claim) async => [
    for (final row in await _sql(
      '''
SELECT event.event_type
FROM public.notification_outbox receipt
JOIN public.attention_occurrence event ON event.id = receipt.occurrence_id
WHERE receipt.account_id = @joiner
  AND ((receipt.beacon_id = @request AND event.event_type = 'relayReceived')
    OR receipt.presentation_key = 'request_forward_lapsed')
ORDER BY receipt.id
''',
      {'joiner': _joiner, 'request': claim.beaconId},
    ))
      row.single! as String,
  ];

  Future<Iterable<AttentionReceipt>> lapsedJoinerCards() async {
    final activity = await getIt<AttentionQueryPort>().attentionFeed(
      accountId: _joiner,
      view: AttentionFeedView.unread,
      surface: AttentionSurface.activity,
    );
    return activity.page.items.where(
      (item) => item.presentationKey == kRequestForwardLapsedPresentationKey,
    );
  }

  Future<void> overlapWrites(
    Env env, {
    required String pauseOn,
    required String when,
    required Future<void> Function() first,
    required Future<void> Function() second,
  }) async {
    // Stop the first real write after it has acquired its business locks.
    // Release it only once Postgres confirms the second caller is waiting.
    await writer.execute('''
CREATE FUNCTION public.test_pause_forward_write() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  PERFORM pg_advisory_xact_lock($_forwardWriteGate);
  RETURN NEW;
END;
\$\$;
CREATE TRIGGER test_pause_forward_write BEFORE $pauseOn FOR EACH ROW
WHEN ($when) EXECUTE FUNCTION public.test_pause_forward_write();
''', queryMode: QueryMode.simple);
    addTearDown(
      () => writer.execute(
        'DROP FUNCTION public.test_pause_forward_write() CASCADE',
      ),
    );
    final gate = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    addTearDown(gate.close);

    await _expectNoDeliveryErrors(() async {
      final calls = <Future<void>>[];
      try {
        await gate.runTx((tx) async {
          final holder =
              (await tx.execute(
                    'SELECT pg_backend_pid(), pg_advisory_xact_lock($_forwardWriteGate)',
                  )).single.first!
                  as int;
          // Handle early errors while we observe the locks. The original
          // futures are checked once the gate transaction releases its lock.
          final firstCall = first()..ignore();
          calls.add(firstCall);
          final firstBackend = await _waitForBlockedWriter(holder, firstCall);
          final secondCall = second()..ignore();
          calls.add(secondCall);
          await _waitForBlockedWriter(firstBackend, secondCall);
        });
      } on Object {
        await Future.wait(calls).timeout(kCompletionWait);
        rethrow;
      }
      expect(calls, hasLength(2));
      await expectLater(
        Future.wait(calls).timeout(kCompletionWait),
        completes,
        reason:
            'Both callers must finish successfully after releasing the lock.',
      );
    });
    final states = await _sql(
      'SELECT state FROM public.phantom_pending_forward',
    );
    expect(states, hasLength(1));
    expect(states.single.single, isIn(['pending', 'delivered', 'lapsed']));
  }

  Future<int> _waitForBlockedWriter(int blocker, Future<void> operation) async {
    var finished = false;
    operation.whenComplete(() => finished = true).ignore();
    final clock = Stopwatch()..start();
    while (!finished && clock.elapsed < kStableStateWait) {
      final rows = await _sql(
        '''
SELECT pid FROM pg_stat_activity
WHERE datname = current_database() AND @blocker = ANY(pg_blocking_pids(pid))
''',
        {'blocker': blocker},
      );
      if (rows.isNotEmpty) return rows.single.single! as int;
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    if (finished) {
      await operation;
      fail('The caller returned while the competing transaction was paused.');
    }
    fail('The caller did not reach the lock held by backend $blocker.');
  }

  Future<bool> canRead(String request) =>
      getIt<BeaconAccessGuard>().canReadContent(
        beaconId: request,
        viewerId: _joiner,
      );

  Future<Set<_AttentionEvent>> attentionEvents() async => {
    for (final row in await _sql(
      '''
SELECT event.id, event.actor_user_id, recipient.account_id
FROM public.attention_occurrence event
LEFT JOIN public.attention_occurrence_recipient recipient ON recipient.occurrence_id = event.id
''',
    ))
      (
        id: row[0]! as String,
        actor: row[1] as String?,
        account: row[2] as String?,
      ),
  };

  Future<NotificationCopy> renderCard(
    _AttentionEvent event,
    String request,
    String locale,
  ) async {
    final receipts = await _sql(
      '''
SELECT presentation_key, presentation_payload, kind
FROM public.notification_outbox
WHERE occurrence_id = @event AND account_id = @joiner
''',
      {'event': event.id, 'joiner': _joiner},
    );
    expect(receipts, hasLength(1));
    final receipt = receipts.single.toColumnMap();
    final identity = (await getIt<NotificationIdentityPort>().resolve(_joiner, [
      IdentityRequest(beaconId: request, actorId: event.actor),
    ])).single;
    return const NotificationCopyRenderer().render(
      presentationKey: receipt['presentation_key']! as String,
      kind: NotificationKind.values.byName(receipt['kind']! as String),
      facts: (receipt['presentation_payload']! as Map).cast<String, Object?>(),
      identity: identity,
      locale: locale,
      tzOffsetMinutes: 0,
      now: DateTime.timestamp(),
    );
  }
}

// Simulate a worker that stops after the merge commits and before it opens a
// delivery transaction. The merge, claim, and all later forwards use real PG.
final class _InterruptedDeliveryTransaction
    implements OwnerGraphTransactionPort {
  int attempts = 0;

  @override
  Future<T> run<T>(
    Set<String> ownerIds,
    String actorUserId,
    Future<T> Function(OwnerGraphScope scope) body,
  ) async {
    attempts++;
    throw StateError('Post-commit delivery was interrupted');
  }

  @override
  Future<T> runRepeatableRead<T>(
    String ownerId,
    String actorUserId,
    Future<T> Function(OwnerGraphScope scope) body, {
    int maxAttempts = 3,
  }) => throw UnsupportedError('The delivery does not use read-only scopes');
}
