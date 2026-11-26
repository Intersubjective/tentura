@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 2))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/port/phantom_merge_wake_port.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/domain/use_case/phantom_merge_case.dart';
import 'package:tentura_server/domain/use_case/user_availability_case.dart';
import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/owner_graph_contention.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/session_database_di_harness.dart';

const _owner = 'Uforwardown01';
const _joiner = 'Uforwardusr01';
const _author = 'Uforwardaut01';
const _note = 'Could you bring a spare shovel?';

typedef _Row = Map<String, Object?>;

Matcher _hasFields(_Row expected) => allOf([
  for (final field in expected.entries) containsPair(field.key, field.value),
]);
typedef _Pending = ({String id, String request, String person, String invite});

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INVITE_MERGE_DELIVERY_TEST_DB',
    defaultNamePrefix: 'tentura_test_invite_merge_delivery',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  group('Delivery of Requests shared with someone before they joined', () {
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

    test(
      'the invite merge claims only pending shares for its own person',
      () async {
        final first = await fixture.pending();
        final second = await fixture.pending(person: first.person);
        expect(second.invite, first.invite);
        final earlier = await fixture.pending(person: first.person);
        final olderMerge = await fixture.pastMerge(first.person);
        final earlierEdge = await fixture.edge(
          earlier.request,
          _owner,
          _joiner,
        );
        await fixture.setEarlierDelivery(earlier, olderMerge, earlierEdge);
        final unrelated = await fixture.pending();
        final earlierBefore = await fixture.forwardRow(earlier);
        final unrelatedBefore = await fixture.forwardRow(unrelated);

        await fixture.captureAtMergeCommit();
        await fixture.accept(first);
        final merge = await fixture.runMerge(first);

        for (final share in [first, second]) {
          expect(
            await fixture.commitSnapshot(share),
            _hasFields({
              'state': 'claimed',
              'merge_id': merge,
              'recipient_id': _joiner,
              'forward_edge_id': null,
              'resolved_at': null,
            }),
          );
          await fixture.expectDelivered(share, merge);
        }
        expect(await fixture.commitSnapshot(earlier), earlierBefore);
        expect(await fixture.forwardRow(earlier), earlierBefore);
        expect(await fixture.commitSnapshot(unrelated), unrelatedBefore);
        expect(await fixture.forwardRow(unrelated), unrelatedBefore);
        expect(await fixture.edgesToJoiner(unrelated.request), isEmpty);
        expect(await fixture.relayReceipts(unrelated.request), isEmpty);
      },
    );

    test(
      'delivery gives the joiner an active edge and one receipt with the saved note',
      () async {
        final share = await fixture.pending();
        expect(await fixture.edgesToJoiner(share.request), isEmpty);
        expect(await fixture.relayReceipts(share.request), isEmpty);

        await fixture.accept(share);
        final merge = await fixture.runMerge(share);

        await fixture.expectDelivered(share, merge);
        expect(await fixture.relayReceipts(share.request), [
          _hasFields({
            'account_id': _joiner,
            'beacon_id': share.request,
            'actor_user_id': _owner,
            'excerpt': _note,
          }),
        ]);
        expect(await fixture.canRead(share.request, _joiner), isTrue);
      },
    );

    test(
      'delivery adds watching only when the sender has no active help offer',
      () async {
        final withoutOffer = await fixture.pending();
        final request = await fixture.request(author: _author);
        await fixture.edge(request, _author, _owner);
        final withOffer = await fixture.pending(
          person: withoutOffer.person,
          request: request,
        );
        await fixture.addActiveOffer(request);
        expect(await fixture.watching(withoutOffer.request), isEmpty);
        expect(await fixture.watching(withOffer.request), isEmpty);

        await fixture.accept(withoutOffer);
        final merge = await fixture.runMerge(withoutOffer);

        await fixture.expectDelivered(withoutOffer, merge);
        await fixture.expectDelivered(withOffer, merge);
        expect(await fixture.watching(withoutOffer.request), hasLength(1));
        expect(await fixture.watching(withOffer.request), isEmpty);
      },
    );

    test(
      'onward delivery preserves the inbound parent and ordinary forward attribution',
      () async {
        final request = await fixture.request(author: _author);
        final parent = await fixture.edge(request, _author, _owner);
        final share = await fixture.pending(request: request);
        expect(
          (await fixture.forwardRow(share))['parent_forward_edge_id'],
          parent,
        );

        final comparison = await fixture.request(author: _author);
        final comparisonParent = await fixture.edge(
          comparison,
          _author,
          _owner,
        );
        await fixture.accept(share);
        final ordinary = await fixture.forward(
          comparison,
          parent: comparisonParent,
        );
        expect(ordinary, isNotEmpty);
        final ordinaryBatch = ordinary.single['batch_id']! as String;
        final ordinaryAttribution = (await fixture.attribution(
          ordinaryBatch,
        )).single;
        expect(ordinaryAttribution['parent_forward_edge_id'], comparisonParent);

        final merge = await fixture.runMerge(share);

        final edge = await fixture.expectDelivered(share, merge);
        expect(edge['parent_edge_id'], parent);
        expect(await fixture.attribution(edge['batch_id']! as String), [
          {...ordinaryAttribution, 'parent_forward_edge_id': parent},
        ]);
      },
    );

    test(
      'an existing active forward satisfies the share without notifying the joiner again',
      () async {
        final share = await fixture.pending();
        await fixture.connectBeforeInvite();
        final existing = (await fixture.forward(
          share.request,
          note: 'Already shared',
        )).single;
        final receiptsBefore = await fixture.relayReceipts(share.request);
        expect(receiptsBefore, hasLength(1));

        await fixture.accept(share);
        final merge = await fixture.runMerge(share);

        await fixture.expectDelivered(share, merge, note: 'Already shared');
        expect(await fixture.edgesToJoiner(share.request), [existing]);
        expect(await fixture.relayReceipts(share.request), receiptsBefore);
      },
    );

    test(
      'delivery lapses while the joiner has paused incoming forwards',
      () async {
        final share = await fixture.pending();
        await fixture.accept(share);
        final today = getIt<UserAvailabilityCase>().todayUtcFrom(
          DateTime.now(),
        );
        await getIt<UserAvailabilityCase>().pause(
          userId: _joiner,
          resumeOn: today.add(const Duration(days: 7)),
        );

        final merge = await fixture.runMerge(share);

        await fixture.expectLapsed(share, merge);
      },
    );

    test(
      'a closed Request lapses and another Request from the invite still arrives',
      () async {
        final closed = await fixture.pending();
        final open = await fixture.pending(person: closed.person);
        await fixture.close(closed.request);
        await fixture.accept(closed);
        await fixture.captureAtMergeCommit();

        final merge = await fixture.runMerge(closed);

        await fixture.expectLapsed(closed, merge);
        await fixture.expectDelivered(open, merge);
        expect((await fixture.commitSnapshot(closed))['merge_id'], merge);
        expect(await fixture.relayReceipts(open.request), hasLength(1));
      },
    );

    test(
      'delivery lapses when the Request no longer permits onward forwarding',
      () async {
        final request = await fixture.request(author: _author);
        await fixture.edge(request, _author, _owner);
        final share = await fixture.pending(request: request);
        await fixture.disallowOnwardForwarding(request);
        expect(await fixture.canRead(request, _owner), isTrue);
        await fixture.accept(share);

        final merge = await fixture.runMerge(share);

        await fixture.expectLapsed(share, merge);
      },
    );

    test('delivery lapses when the sender loses content access', () async {
      final request = await fixture.request(author: _author);
      final parent = await fixture.edge(request, _author, _owner);
      final share = await fixture.pending(request: request);
      await fixture.block(_author, _owner);
      expect(await fixture.canRead(request, _owner), isFalse);
      expect(await fixture.isEdgeActive(parent), isTrue);
      await fixture.accept(share);

      final merge = await fixture.runMerge(share);

      await fixture.expectLapsed(share, merge);
    });

    test(
      'delivery lapses when the sender and joiner block each other after linking',
      () async {
        final share = await fixture.pending();
        await fixture.accept(share);
        // A block before the merge guard would skip the merge. Put the block
        // at the commit boundary to exercise the delivery guard instead.
        await fixture.captureAtMergeCommit(
          change: '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (NEW.owner_id, NEW.user_id, NEW.user_id),
       (NEW.user_id, NEW.owner_id, NEW.owner_id);
''',
        );

        final merge = await fixture.runMerge(share);

        await fixture.expectLapsed(share, merge);
      },
    );

    test(
      'delivery lapses when its inbound parent is cancelled even if the sender still has access',
      () async {
        final request = await fixture.request(author: _author);
        final parent = await fixture.edge(request, _author, _owner);
        final share = await fixture.pending(request: request);
        expect(
          (await fixture.forwardRow(share))['parent_forward_edge_id'],
          parent,
        );
        expect(
          await getIt<ForwardCase>().cancelForward(
            edgeId: parent,
            senderId: _author,
          ),
          isTrue,
        );
        await fixture.addActiveOffer(request);
        expect(await fixture.canRead(request, _owner), isTrue);
        expect(await fixture.isEdgeActive(parent), isFalse);
        await fixture.accept(share);

        final merge = await fixture.runMerge(share);

        await fixture.expectLapsed(share, merge);
      },
    );

    test(
      'delivery lapses when the joiner previously dismissed the Request',
      () async {
        final share = await fixture.pending();
        await fixture.dismissForJoiner(share.request);
        await fixture.accept(share);

        final merge = await fixture.runMerge(share);

        await fixture.expectLapsed(share, merge);
      },
    );

    for (final returnedToPending in [true, false]) {
      test(
        returnedToPending
            ? 'delivery leaves a share returned to pending by undo untouched'
            : 'delivery leaves a share claimed by a superseded merge untouched',
        () async {
          final skipped = await fixture.pending();
          final control = await fixture.pending(person: skipped.person);
          final olderMerge = returnedToPending
              ? null
              : await fixture.pastMerge(skipped.person);
          final change = returnedToPending
              ? "state = 'pending', merge_id = NULL, recipient_id = NULL"
              : "merge_id = '$olderMerge'";
          // Simulate only the row reset performed by undo, or a stale claim.
          // The separate live share proves that the worker reached delivery.
          await fixture.captureAtMergeCommit(
            change:
                '''
UPDATE public.phantom_pending_forward SET $change
WHERE id = '${skipped.id}' AND state = 'claimed';
''',
          );
          await fixture.accept(skipped);
          final merge = await fixture.runMerge(skipped);

          await fixture.expectDelivered(control, merge);
          expect(
            await fixture.commitSnapshot(skipped, beforeChange: true),
            _hasFields({
              'state': 'claimed',
              'merge_id': merge,
              'recipient_id': _joiner,
            }),
          );
          final beforeDelivery = await fixture.commitSnapshot(skipped);
          expect(
            beforeDelivery,
            _hasFields({
              'state': returnedToPending ? 'pending' : 'claimed',
              'merge_id': olderMerge,
              'recipient_id': returnedToPending ? null : _joiner,
              'forward_edge_id': null,
              'lapse_reason': null,
              'resolved_at': null,
            }),
          );
          expect(await fixture.forwardRow(skipped), beforeDelivery);
          expect(await fixture.edgesToJoiner(skipped.request), isEmpty);
          expect(await fixture.relayReceipts(skipped.request), isEmpty);
        },
      );
    }

    test(
      'delivery leaves terminal shares for the same merge unchanged',
      () async {
        final delivered = await fixture.pending();
        final lapsed = await fixture.pending(person: delivered.person);
        final live = await fixture.pending(person: delivered.person);
        await fixture.connectBeforeInvite();
        final edge = (await fixture.forward(delivered.request)).single;
        final receiptsBefore = await fixture.relayReceipts(delivered.request);
        expect(receiptsBefore, hasLength(1));
        // Model a prior attempt resolving these two claims before dispatch.
        // Leave the lapsed Request open so replay would create a visible edge.
        await fixture.captureAtMergeCommit(
          change:
              '''
UPDATE public.phantom_pending_forward
SET state = 'delivered', resolved_at = now(), forward_edge_id = '${edge['id']}'
WHERE id = '${delivered.id}' AND state = 'claimed';
UPDATE public.phantom_pending_forward
SET state = 'lapsed', resolved_at = now(), lapse_reason = 'recorded lapse'
WHERE id = '${lapsed.id}' AND state = 'claimed';
''',
        );
        await fixture.accept(live);
        final merge = await fixture.runMerge(live);

        await fixture.expectDelivered(live, merge);
        final deliveredBefore = await fixture.commitSnapshot(delivered);
        final lapsedBefore = await fixture.commitSnapshot(lapsed);
        expect(
          deliveredBefore,
          _hasFields({'state': 'delivered', 'merge_id': merge}),
        );
        expect(
          lapsedBefore,
          _hasFields({'state': 'lapsed', 'merge_id': merge}),
        );

        expect(await fixture.forwardRow(delivered), deliveredBefore);
        expect(await fixture.forwardRow(lapsed), lapsedBefore);
        expect(await fixture.edgesToJoiner(delivered.request), [edge]);
        expect(await fixture.relayReceipts(delivered.request), receiptsBefore);
        expect(await fixture.edgesToJoiner(lapsed.request), isEmpty);
        expect(await fixture.relayReceipts(lapsed.request), isEmpty);
      },
    );
  }, skip: skip);
}

final class _Fixture {
  const _Fixture(this._writer);

  final Connection _writer;

  Future<Result> sql(String query, [Map<String, Object?> args = const {}]) =>
      _writer.execute(Sql.named(query), parameters: args);

  Future<List<_Row>> rows(
    String query, [
    Map<String, Object?> args = const {},
  ]) async => (await sql(query, args)).map((row) => row.toColumnMap()).toList();

  Future<void> reset() async {
    await sql('TRUNCATE public."user", public.attention_occurrence CASCADE');
    for (final (index, user) in [_owner, _joiner, _author].indexed) {
      await sql(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@user, @user, @key)
''',
        {'user': user, 'key': pgTestPublicKey('inviteDelivery', index + 1)},
      );
    }
  }

  Future<String> request({String author = _owner}) async =>
      (await sql(
            '''
INSERT INTO public.beacon
  (user_id, title, description, status, is_discoverable, published_at)
VALUES (@author, 'Help with the garden', '', @status, false, now())
RETURNING id
''',
            {'author': author, 'status': BeaconStatus.open.smallintValue},
          )).single.single!
          as String;

  Future<_Pending> pending({String? person, String? request}) async {
    final phantoms = getIt<PhantomCase>();
    final target =
        person ?? await phantoms.create(ownerId: _owner, name: 'Avery');
    final beacon = request ?? await this.request();
    final invite = await phantoms.forwardRequest(
      ownerId: _owner,
      phantomId: target,
      beaconId: beacon,
      note: _note,
    );
    final row = (await rows(
      '''
SELECT * FROM public.phantom_pending_forward
WHERE phantom_id = @person AND beacon_id = @beacon
''',
      {'person': target, 'beacon': beacon},
    )).single;
    expect(
      row,
      _hasFields({
        'state': 'pending',
        'note': _note,
        'sender_id': _owner,
        'merge_id': null,
        'recipient_id': null,
      }),
    );
    return (
      id: row['id']! as String,
      request: beacon,
      person: target,
      invite: invite,
    );
  }

  Future<void> accept(_Pending share) async {
    expect(
      await getIt<InvitationCase>().acceptAsExisting(
        code: share.invite,
        userId: _joiner,
      ),
      InviteAcceptance.accepted,
    );
    expect(
      await rows(
        '''
SELECT state, user_id FROM public.phantom_merge_job WHERE invitation_id = @invite
''',
        {'invite': share.invite},
      ),
      [
        {'state': 'queued', 'user_id': _joiner},
      ],
    );
  }

  Future<String> runMerge(_Pending share) async {
    // The same entry point is awaited by the production worker.
    await getIt<PhantomMergeCase>().runDue(
      leaseOwner: 'invite-delivery-test-worker',
      clock: DateTime.timestamp,
    );
    final merged = (await rows(
      '''
SELECT p.current_merge_id, p.merged_user_id, m.id, m.undone_at,
       j.state, j.last_error
FROM public.phantom p
JOIN public.phantom_merge_job j ON j.phantom_id = p.id
LEFT JOIN public.phantom_merge m ON m.id = p.current_merge_id
WHERE p.id = @person AND j.invitation_id = @invite
''',
      {'person': share.person, 'invite': share.invite},
    )).single;
    expect(
      merged,
      _hasFields({
        'state': 'done',
        'last_error': null,
        'merged_user_id': _joiner,
        'current_merge_id': isA<String>(),
        'id': merged['current_merge_id'],
        'undone_at': null,
      }),
      reason: 'The accepted invite must still be merged.',
    );
    return merged['current_merge_id']! as String;
  }

  Future<_Row> expectDelivered(
    _Pending share,
    String merge, {
    String note = _note,
  }) async {
    final row = await forwardRow(share);
    expect(
      row,
      _hasFields({
        'state': 'delivered',
        'merge_id': merge,
        'recipient_id': _joiner,
        'forward_edge_id': isA<String>(),
        'resolved_at': isA<DateTime>(),
        'lapse_reason': null,
      }),
    );
    final edges = await edgesToJoiner(share.request);
    expect(edges, [
      _hasFields({
        'id': row['forward_edge_id'],
        'beacon_id': row['beacon_id'],
        'sender_id': row['sender_id'],
        'recipient_id': _joiner,
        'cancelled_at': null,
        'note': note,
      }),
    ]);
    return edges.single;
  }

  Future<void> expectLapsed(_Pending share, String merge) async {
    expect(
      await forwardRow(share),
      _hasFields({
        'state': 'lapsed',
        'merge_id': merge,
        'recipient_id': _joiner,
        'resolved_at': isA<DateTime>(),
        'lapse_reason': isNotEmpty,
        'forward_edge_id': null,
      }),
    );
    expect(await edgesToJoiner(share.request), isEmpty);
    expect(await relayReceipts(share.request), isEmpty);
  }

  Future<_Row> forwardRow(_Pending share) async => (await rows(
    'SELECT * FROM public.phantom_pending_forward WHERE id = @id',
    {'id': share.id},
  )).single;

  Future<List<_Row>> edgesToJoiner(String request) => rows(
    '''
SELECT id, beacon_id, sender_id, recipient_id, cancelled_at, note,
       parent_edge_id, batch_id
FROM public.beacon_forward_edge
WHERE beacon_id = @request AND recipient_id = @user
ORDER BY id
''',
    {'request': request, 'user': _joiner},
  );

  Future<List<_Row>> relayReceipts(String request) => rows(
    '''
SELECT o.id, o.actor_user_id, o.immutable_payload ->> 'beaconId' AS beacon_id,
       r.account_id, r.role_facts ->> 'excerpt' AS excerpt
FROM public.attention_occurrence o
JOIN public.attention_occurrence_recipient r ON r.occurrence_id = o.id
WHERE o.event_type = 'relayReceived'
  AND o.immutable_payload ->> 'beaconId' = @request
  AND r.account_id = @user
ORDER BY o.id
''',
    {'request': request, 'user': _joiner},
  );

  Future<List<_Row>> watching(String request) => rows(
    '''
SELECT status FROM public.inbox_item
WHERE user_id = @owner AND beacon_id = @request AND status = 1
''',
    {'owner': _owner, 'request': request},
  );

  Future<String> edge(String request, String sender, String recipient) async =>
      (await sql(
            '''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@request, @sender, @recipient) RETURNING id
''',
            {'request': request, 'sender': sender, 'recipient': recipient},
          )).single.single!
          as String;

  Future<bool> isEdgeActive(String edgeId) async =>
      (await sql(
            'SELECT cancelled_at IS NULL FROM public.beacon_forward_edge WHERE id = @id',
            {'id': edgeId},
          )).single.single!
          as bool;

  Future<List<_Row>> forward(
    String request, {
    String? parent,
    String note = _note,
  }) async {
    final result = await getIt<ForwardCase>().forward(
      senderId: _owner,
      beaconId: request,
      recipientIds: [_joiner],
      parentEdgeId: parent,
      sharedNote: note,
    );
    expect(result.deliveredRecipientIds, [_joiner]);
    return edgesToJoiner(request);
  }

  Future<List<_Row>> attribution(String batch) => rows(
    '''
SELECT parent_forward_edge_id, attribution_weight, attribution_method
FROM public.forward_decision_attribution
WHERE child_forward_batch_id = @batch
''',
    {'batch': batch},
  );

  Future<bool> canRead(String request, String viewer) async =>
      (await sql(
            'SELECT public.beacon_can_read_content(@request, @viewer)',
            {'request': request, 'viewer': viewer},
          )).single.single!
          as bool;

  Future<void> connectBeforeInvite() => sql(
    '''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@owner, @user, 1), (@user, @owner, 1)
''',
    {'owner': _owner, 'user': _joiner},
  );

  Future<void> addActiveOffer(String request) => sql(
    '''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message)
VALUES (@request, @owner, 'I can help')
''',
    {'request': request, 'owner': _owner},
  );

  Future<void> block(String blocker, String blocked) => sql(
    '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocked)
''',
    {'blocker': blocker, 'blocked': blocked},
  );

  Future<void> close(String request) => sql(
    'UPDATE public.beacon SET status = @closed WHERE id = @request',
    {'closed': BeaconStatus.closed.smallintValue, 'request': request},
  );

  Future<void> disallowOnwardForwarding(String request) async {
    // As in the Request invite recording tests, exercise the defensive policy
    // gate on a legacy-shaped fixture: today's schema reserves this value for Posts.
    const constraint = 'beacon_forward_policy_ck';
    final definition =
        (await sql('''
SELECT pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'public.beacon'::regclass AND conname = '$constraint'
''')).single.single!
            as String;
    await sql('ALTER TABLE public.beacon DROP CONSTRAINT $constraint');
    addTearDown(() async {
      await sql('UPDATE public.beacon SET forward_policy = 1 WHERE id = @id', {
        'id': request,
      });
      await sql(
        'ALTER TABLE public.beacon ADD CONSTRAINT $constraint $definition',
      );
    });
    const trigger = 'beacon_kind_policy_guard_trg';
    await _writer.runTx((tx) async {
      await tx.execute('ALTER TABLE public.beacon DISABLE TRIGGER $trigger');
      await tx.execute(
        Sql.named('UPDATE public.beacon SET forward_policy = 0 WHERE id = @id'),
        parameters: {'id': request},
      );
      await tx.execute('ALTER TABLE public.beacon ENABLE TRIGGER $trigger');
    });
  }

  Future<void> dismissForJoiner(String request) => sql(
    '''
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES (@user, @request, 2)
''',
    {'user': _joiner, 'request': request},
  );

  Future<String> pastMerge(String person) async {
    final id = generateId('PM');
    await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.phantom_merge
  (id, phantom_id, owner_id, user_id, origin, undo, undone_at)
VALUES (@id, @person, @owner, @user, 2, '{}'::jsonb, now())
'''),
      parameters: {
        'id': id,
        'person': person,
        'owner': _owner,
        'user': _joiner,
      },
    );
    return id;
  }

  Future<void> setEarlierDelivery(
    _Pending share,
    String merge,
    String edgeId,
  ) => _writer.executeWithOwnerScopes(
    [_owner],
    Sql.named('''
UPDATE public.phantom_pending_forward
SET state = 'delivered', merge_id = @merge, recipient_id = @user,
    forward_edge_id = @edge, resolved_at = now()
WHERE id = @id
'''),
    parameters: {
      'id': share.id,
      'merge': merge,
      'user': _joiner,
      'edge': edgeId,
    },
  );

  Future<void> captureAtMergeCommit({String change = ''}) async {
    await sql('''
CREATE TABLE test_merge_commit_forwards AS
SELECT p.*, false AS before_change
FROM public.phantom_pending_forward p WITH NO DATA
''');
    addTearDown(() => sql('DROP TABLE test_merge_commit_forwards'));
    await sql('''
CREATE FUNCTION test_capture_merge_commit() RETURNS trigger LANGUAGE plpgsql AS \$\$
BEGIN
  INSERT INTO test_merge_commit_forwards
    SELECT p.*, true FROM public.phantom_pending_forward p;
  $change
  INSERT INTO test_merge_commit_forwards
    SELECT p.*, false FROM public.phantom_pending_forward p;
  RETURN NEW;
END;
\$\$
''');
    addTearDown(() => sql('DROP FUNCTION test_capture_merge_commit() CASCADE'));
    await sql('''
CREATE CONSTRAINT TRIGGER test_capture_merge_commit
AFTER UPDATE ON public.phantom_merge_job
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
WHEN (OLD.state = 'queued' AND NEW.state = 'done')
EXECUTE FUNCTION test_capture_merge_commit()
''');
  }

  Future<_Row> commitSnapshot(
    _Pending share, {
    bool beforeChange = false,
  }) async {
    final snapshots = await rows(
      'SELECT * FROM test_merge_commit_forwards WHERE id = @id AND before_change = @before',
      {'id': share.id, 'before': beforeChange},
    );
    return snapshots.single..remove('before_change');
  }
}
