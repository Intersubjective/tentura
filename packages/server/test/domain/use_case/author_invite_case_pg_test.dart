@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart'
    show migrateDbSchema;
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dismissible_sql.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/author_invite_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/post_bud_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_contact_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/admission_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/author_invite_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/contact_resolution_sweep_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/admission_row_set.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/user_erasure_test_stack.dart';

/// Budding C4 (Arch §5): the author-invite lifecycle with real repositories
/// and real attention dispatch.
///
/// `_child` is a Request budded by `_author` from `_post` (author
/// `_postAuthor`). Its snapshot observers are `_postAuthor`, `_warm` (a first
/// responder), `_cold` (forward-visible to `_author`), `_hidden` (not
/// visible), `_paused` (availability-paused) and `_helper`; `_late` joined the
/// Post after the bud and is not an observer.
const _postAuthor = 'Uai4postauth';
const _author = 'Uai4author01';
const _warm = 'Uai4warm0001';
const _cold = 'Uai4cold0001';
const _hidden = 'Uai4hidden01';
const _paused = 'Uai4paused01';
const _helper = 'Uai4helper01';
const _late = 'Uai4late0001';
const _users = [
  _postAuthor,
  _author,
  _warm,
  _cold,
  _hidden,
  _paused,
  _helper,
  _late,
];
const _observers = [_postAuthor, _warm, _cold, _hidden, _paused, _helper];

const _post = 'Bai4post0001';
const _child = 'Bai4child001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_AUTHOR_INVITE_CASE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_author_invite_case',
  );
  final repairTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_AUTHOR_INVITE_REPAIR_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_author_invite_repair',
  );
  final pgSkip = await pgSkipReason(target) ?? await pgSkipReason(repairTarget);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('invites produced by the unconfirmed-committer repair', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late _Stack s;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: repairTarget,
        lastInclusiveVersion: '0247',
      );
      writer = session.writer;
      await _seed(writer);
      // `_cold` has no inbound edge at all, `_warm` has an ordinary one;
      // both were admitted to the room without ever acknowledging.
      await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$_child', '$_postAuthor', '$_warm')
''');
      for (final user in [_cold, _warm]) {
        await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$_child', '$user', 2, 3)
''');
      }
      await migrateDbSchema(writer);
      database = openDisposablePgDatabase(repairTarget);
      s = _Stack.build(database, repairTarget.databaseEnv);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<String> pendingInviteId(String user) async =>
        (await writer.execute(
              'SELECT id FROM public.beacon_author_invite '
              "WHERE beacon_id = '$_child' AND invitee_id = '$user' "
              'AND status = 0',
            )).single.single!
            as String;

    for (final user in [_cold, _warm]) {
      test('$user can read the Request and sees the pinned row with the '
          'repair invite id', () async {
        final canRead = await writer.execute(
          Sql.named('SELECT public.beacon_can_read_content(@b, @u)'),
          parameters: {'b': _child, 'u': user},
        );
        expect(canRead.single.single, isTrue);

        final offers = await AttentionRepository(
          database,
        ).activityOffers(accountId: user);
        expect(offers.items.map((i) => i.beaconId), [_child]);
        expect(offers.items.single.inviteId, await pendingInviteId(user));
      });

      test('$user accepting the repair invite becomes a helper with an '
          'acknowledged event', () async {
        final accepted = await s.invites.accept(
          actorUserId: user,
          inviteId: await pendingInviteId(user),
        );

        expect(accepted.status, AuthorInviteStatus.accepted);
        final rows = await collectAdmissionRowSet(
          writer,
          beaconId: _child,
          helperId: user,
        );
        expect(
          rows,
          contains(startsWith('beacon_participant|user=$user|role=2|')),
        );
        expect(
          rows,
          contains(
            'beacon_commitment_event|user=$user|actor=$_author|kind=1',
          ),
        );
      });
    }
  });

  group('AuthorInviteCase', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late _Stack s;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      s = _Stack.build(database, target.databaseEnv);
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<AuthorInviteCreateResult> invite(
      String invitee, {
      String actor = _author,
      String? note,
    }) => s.invites.create(
      actorUserId: actor,
      beaconId: _child,
      inviteeId: invitee,
      note: note,
    );

    Future<String> invited(String invitee, {String? note}) async {
      final result = await invite(invitee, note: note);
      expect(result.outcome, PostBudInviteOutcome.invited, reason: invitee);
      return result.inviteId!;
    }

    Future<List<String>> rowSet(String helper) =>
        collectAdmissionRowSet(writer, beaconId: _child, helperId: helper);

    /// Pins the invite as expired with its receipt cleared, its contact
    /// resolved without evidence, and no noisy evidence after the sweep (I8).
    Future<void> expectExpired(String inviteId, String invitee) async {
      final row = await _invite(writer, inviteId);
      expect(row.status, AuthorInviteStatus.expired.code);
      final receipts = await _receipts(writer, kind: 'authorInviteReceived');
      expect(
        receipts.where((r) => r.account == invitee).map((r) => r.cleared),
        everyElement(isTrue),
      );
      final contact = await _contact(writer, row.forwardEdgeId!);
      expect(contact.resolvedAt, isNotNull);
      expect(contact.outcome, isNull);
      await writer.execute('''
UPDATE public.beacon_forward_edge
SET contact_deadline_at = now() - interval '1 hour'
WHERE id = '${row.forwardEdgeId}'
''');
      await s.sweep.run();
      expect((await _contact(writer, row.forwardEdgeId!)).outcome, isNull);
      expect(await _contactEvidence(writer), isEmpty);
    }

    group('create (later invites)', () {
      test('a warm observer: edge, exempt flag, pinned row, receipt', () async {
        final id = await invited(_warm, note: '  You have a van  ');

        final row = await _invite(writer, id);
        expect(row.status, AuthorInviteStatus.pending.code);
        expect(row.inviter, _author);
        expect(row.invitee, _warm);
        expect(row.sourcePost, _post);
        expect(row.warm, isTrue);
        expect(row.note, 'You have a van');

        final edge = await _edge(writer, row.forwardEdgeId!);
        expect(edge.sender, _author);
        expect(edge.recipient, _warm);
        expect(edge.note, '', reason: 'the invite note stays on the invite');
        expect(edge.exempt, isTrue);

        expect(await _eligiblePinned(writer, _warm), contains(_child));
        final receipts = await _receipts(writer);
        expect(receipts.map((r) => (r.account, r.kind)), [
          (_warm, 'authorInviteReceived'),
        ]);
        expect(receipts.single.sourceEventKey, 'author_invite:$id');
      });

      test('a cold visible observer gets a non-exempt edge', () async {
        final id = await invited(_cold);
        final row = await _invite(writer, id);
        expect(row.warm, isFalse);
        expect((await _edge(writer, row.forwardEdgeId!)).exempt, isFalse);
      });

      test('ineligible targets are outcomes, not errors', () async {
        await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_helper', '$_author', '$_helper')
''');
        await invited(_warm);

        expect((await invite(_late)).outcome, PostBudInviteOutcome.notEligible);
        expect(
          (await invite(_hidden)).outcome,
          PostBudInviteOutcome.notEligible,
        );
        expect(
          (await invite(_author)).outcome,
          PostBudInviteOutcome.notEligible,
        );
        expect(
          (await invite(_paused)).outcome,
          PostBudInviteOutcome.recipientPaused,
        );
        expect((await invite(_helper)).outcome, PostBudInviteOutcome.blocked);
        expect(
          (await invite(_warm)).outcome,
          PostBudInviteOutcome.alreadyInvited,
        );
        expect(await _inviteCount(writer), 1);
      });

      test('only the Request author may invite', () async {
        await expectLater(
          invite(_cold, actor: _warm),
          throwsA(isA<UnauthorizedException>()),
        );
        expect(await _inviteCount(writer), 0);
      });

      test(
        'a warm invite that reuses an ordinary edge makes it exempt',
        () async {
          final ordinary = await s.forward(_author, _warm);
          expect((await _edge(writer, ordinary)).exempt, isFalse);

          final row = await _invite(writer, await invited(_warm));

          expect(row.forwardEdgeId, ordinary);
          expect((await _edge(writer, ordinary)).exempt, isTrue);
        },
      );
    });

    group('accept', () {
      test(
        'writes the same admission rows as offer + author accept (I7)',
        () async {
          await s.forward(_author, _cold);
          await s.offerHelp(_cold);
          await s.coordination.acceptHelpOffer(
            beaconId: _child,
            offerUserId: _cold,
            actorUserId: _author,
          );
          final viaOffer = await rowSet(_cold);
          expect(viaOffer, isNotEmpty);

          await _seed(writer);
          final id = await invited(_cold);
          final accepted = await s.invites.accept(
            actorUserId: _cold,
            inviteId: id,
          );

          expect(accepted.status, AuthorInviteStatus.accepted);
          expect(await rowSet(_cold), viaOffer);
          final receipts = await _receipts(writer);
          expect(
            receipts.where((r) => r.kind == 'helpOfferSubmitted'),
            isEmpty,
            reason: 'no author obligation for an invite accept',
          );
          expect(
            receipts
                .where((r) => r.kind == 'authorInviteAccepted')
                .map(
                  (r) => r.account,
                ),
            [_author],
          );
          expect(
            receipts
                .where((r) => r.kind == 'authorInviteReceived')
                .single
                .cleared,
            isTrue,
          );
        },
      );

      test('a repair invite without a source Post is accepted into a helper '
          'with an acknowledged event', () async {
        await writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, contact_sweep_exempt)
VALUES ('Fai4repair001', '$_child', '$_author', '$_cold', true)
''');
        await writer.execute('''
INSERT INTO public.beacon_author_invite
  (id, beacon_id, inviter_id, invitee_id, forward_edge_id, warm)
VALUES ('BIai4repair01', '$_child', '$_author', '$_cold', 'Fai4repair001',
        true)
''');

        final accepted = await s.invites.accept(
          actorUserId: _cold,
          inviteId: 'BIai4repair01',
        );

        expect(accepted.status, AuthorInviteStatus.accepted);
        final rows = await rowSet(_cold);
        expect(
          rows,
          contains(startsWith('beacon_participant|user=$_cold|role=2|')),
        );
        expect(
          rows,
          contains('beacon_commitment_event|user=$_cold|actor=$_author|kind=1'),
        );
      });

      test('a repeated accept is idempotent', () async {
        final id = await invited(_warm);
        await s.invites.accept(actorUserId: _warm, inviteId: id);
        final rows = await rowSet(_warm);
        final receipts = await _receipts(writer);

        final again = await s.invites.accept(actorUserId: _warm, inviteId: id);

        expect(again.status, AuthorInviteStatus.accepted);
        expect(await rowSet(_warm), rows);
        expect(await _receipts(writer), receipts);
      });

      test('only the invitee can accept', () async {
        final id = await invited(_warm);
        await expectLater(
          s.invites.accept(actorUserId: _cold, inviteId: id),
          throwsA(isA<AuthorInviteNotFoundException>()),
        );
        await expectLater(
          s.invites.accept(actorUserId: _warm, inviteId: 'BImissing0000'),
          throwsA(isA<AuthorInviteNotFoundException>()),
        );
      });

      test('after accept, Cancel and Delete are refused', () async {
        final id = await invited(_cold);
        await s.invites.accept(actorUserId: _cold, inviteId: id);

        await expectLater(
          s.beaconCase.beaconCancel(beaconId: _child, userId: _author),
          throwsA(isA<EvaluationException>()),
        );
        await expectLater(
          s.beaconCase.deleteById(beaconId: _child, userId: _author),
          throwsA(isA<EvaluationException>()),
        );
        expect(await _status(writer, _child), BeaconStatus.open.smallintValue);
      });
    });

    group('decline', () {
      test('declines the inbox row with no evidence', () async {
        final id = await invited(_cold);
        final row = await _invite(writer, id);

        final declined = await s.invites.decline(
          actorUserId: _cold,
          inviteId: id,
        );

        expect(declined.status, AuthorInviteStatus.declined);
        expect(await _inboxStatus(writer, _cold), 2);
        final contact = await _contact(writer, row.forwardEdgeId!);
        expect(contact.outcome, 2);
        expect(await _contactEvidence(writer), isEmpty);
        expect(await _trustEvidenceFor(writer, _cold), isEmpty);
        final receipts = await _receipts(writer);
        expect(
          receipts
              .where((r) => r.kind == 'authorInviteReceived')
              .single
              .cleared,
          isTrue,
        );
        expect(
          receipts
              .where((r) => r.kind == 'authorInviteDeclined')
              .map(
                (r) => r.account,
              ),
          [_author],
        );
        await expectLater(
          s.invites.accept(actorUserId: _cold, inviteId: id),
          throwsA(isA<AuthorInviteNotPendingException>()),
        );
      });

      test('a later invite after a decline re-pins the inbox row', () async {
        final first = await invited(_cold);
        await s.invites.decline(actorUserId: _cold, inviteId: first);
        expect(await _eligiblePinned(writer, _cold), isNot(contains(_child)));

        final second = await invited(_cold);

        expect(second, isNot(first));
        expect(await _inboxStatus(writer, _cold), 0);
        expect(await _eligiblePinned(writer, _cold), contains(_child));
      });
    });

    group('withdraw', () {
      test('an unread edge is cancelled', () async {
        final id = await invited(_cold);
        final row = await _invite(writer, id);

        final withdrawn = await s.invites.withdraw(
          actorUserId: _author,
          inviteId: id,
        );

        expect(withdrawn.status, AuthorInviteStatus.withdrawn);
        expect((await _edge(writer, row.forwardEdgeId!)).cancelled, isTrue);
        expect(
          (await _receipts(
            writer,
            kind: 'authorInviteReceived',
          )).single.cleared,
          isTrue,
        );
      });

      test(
        'a read edge stays, and the invite can no longer be accepted',
        () async {
          final id = await invited(_cold);
          final row = await _invite(writer, id);
          await writer.execute('''
UPDATE public.beacon_forward_edge SET recipient_read_at = now()
WHERE id = '${row.forwardEdgeId}'
''');

          await s.invites.withdraw(actorUserId: _author, inviteId: id);

          final edge = await _edge(writer, row.forwardEdgeId!);
          expect(edge.cancelled, isFalse);
          final contact = await _contact(writer, row.forwardEdgeId!);
          expect(contact.resolvedAt, isNotNull);
          expect(contact.outcome, isNull);
          expect(
            (await _receipts(
              writer,
              kind: 'authorInviteReceived',
            )).single.cleared,
            isTrue,
          );
          await expectLater(
            s.invites.accept(actorUserId: _cold, inviteId: id),
            throwsA(isA<AuthorInviteNotPendingException>()),
          );
          expect(await rowSet(_cold), isEmpty);
        },
      );

      test('only the inviter can withdraw', () async {
        final id = await invited(_cold);
        await expectLater(
          s.invites.withdraw(actorUserId: _cold, inviteId: id),
          throwsA(isA<AuthorInviteNotFoundException>()),
        );
      });
    });

    group('supersede', () {
      test(
        'offerHelp by a pending invitee admits through the invite',
        () async {
          final id = await invited(_warm);

          await s.offerHelp(_warm, message: 'On my way');

          final row = await _invite(writer, id);
          expect(row.status, AuthorInviteStatus.accepted.code);
          expect(await _roomAccess(writer, _warm), 3);
          final receipts = await _receipts(writer);
          expect(
            receipts.where((r) => r.kind == 'helpOfferSubmitted'),
            isEmpty,
            reason: 'supersede creates no author obligation',
          );
          expect(
            receipts
                .where((r) => r.kind == 'authorInviteAccepted')
                .map(
                  (r) => r.account,
                ),
            [_author],
          );
          expect(
            receipts
                .where((r) => r.kind == 'authorInviteReceived')
                .single
                .cleared,
            isTrue,
          );
          expect(await _offerMessage(writer, _warm), 'On my way');
        },
      );

      test('re-offering after an earlier offer admits through a later invite '
          'without a second offered event', () async {
        await s.offerHelp(_warm, message: 'First');
        expect(await _offerMessage(writer, _warm), 'First');
        expect(
          await _inviteCount(writer),
          0,
          reason: 'the offer predates any invitation',
        );

        final id = await invited(_warm);
        expect(
          (await _invite(writer, id)).status,
          AuthorInviteStatus.pending.code,
          reason: 'the invite arrives while the offer is already active',
        );
        expect(
          await _roomAccess(writer, _warm),
          isNull,
          reason: 'an ordinary offer alone does not admit',
        );

        expect(
          (await AttentionRepository(database).activityOffers(
            accountId: _warm,
          )).items.where((i) => i.beaconId == _child).map((i) => i.inviteId),
          [id],
          reason: 'the pending invite card stays actionable before re-offering',
        );

        await s.offerHelp(_warm, message: 'Second');

        expect(
          (await _invite(writer, id)).status,
          AuthorInviteStatus.accepted.code,
        );
        expect(await _roomAccess(writer, _warm), 3);
        expect(await _offerMessage(writer, _warm), 'Second');
        final events = await rowSet(_warm);
        expect(
          events.where(
            (r) => r.startsWith('beacon_commitment_event|user=$_warm|'),
          ),
          [
            'beacon_commitment_event|user=$_warm|actor=$_warm|kind=0',
            'beacon_commitment_event|user=$_warm|actor=$_author|kind=1',
          ],
          reason: 'one offered event, then the author acknowledgement',
        );
        final receipts = await _receipts(writer);
        expect(
          receipts
              .where((r) => r.kind == 'authorInviteAccepted')
              .map((r) => r.account),
          [_author],
        );
        expect(
          receipts
              .where((r) => r.kind == 'authorInviteReceived')
              .single
              .cleared,
          isTrue,
        );

        // Client projection: no pending invite card is left behind.
        expect(await s.invites.myPendingInvites(actorUserId: _warm), isEmpty);
        expect(
          (await AttentionRepository(
            database,
          ).activityOffers(accountId: _warm)).items.where(
            (i) => i.inviteId != null,
          ),
          isEmpty,
        );
      });

      test('an existing offer does not hide a later pending invite from the '
          'pinned For-you zone', () async {
        await s.offerHelp(_warm);
        expect(await _offerMessage(writer, _warm), isNotNull);
        expect(await _inviteCount(writer), 0);

        final id = await invited(_warm);
        expect(
          (await _invite(writer, id)).status,
          AuthorInviteStatus.pending.code,
        );

        final offers = await AttentionRepository(
          database,
        ).activityOffers(accountId: _warm);
        expect(
          offers.items
              .where((i) => i.beaconId == _child)
              .map((i) => i.inviteId),
          [id],
        );
      });

      test(
        'the author accepting an ordinary offer supersedes the invite',
        () async {
          await s.forward(_author, _cold);
          await s.offerHelp(_cold);
          final id = await invited(_cold);

          await s.coordination.acceptHelpOffer(
            beaconId: _child,
            offerUserId: _cold,
            actorUserId: _author,
          );

          expect(
            (await _invite(writer, id)).status,
            AuthorInviteStatus.superseded.code,
          );
          expect(
            (await _receipts(
              writer,
              kind: 'authorInviteReceived',
            )).single.cleared,
            isTrue,
          );
        },
      );
    });

    group('review and expiry', () {
      Future<void> admitHelper() async {
        await s.forward(_author, _helper);
        await s.offerHelp(_helper);
        await s.coordination.acceptHelpOffer(
          beaconId: _child,
          offerUserId: _helper,
          actorUserId: _author,
        );
      }

      test(
        'review (0 → 5) keeps the invite pending; accept in review is refused',
        () async {
          await admitHelper();
          final id = await invited(_warm);

          await s.closure.close(authorId: _author, beaconId: _child);
          expect(
            await _status(writer, _child),
            BeaconStatus.reviewOpen.smallintValue,
          );
          expect(
            (await _invite(writer, id)).status,
            AuthorInviteStatus.pending.code,
          );
          expect(
            (await _receipts(
              writer,
              kind: 'authorInviteReceived',
            )).single.cleared,
            isFalse,
          );
          await expectLater(
            s.invites.accept(actorUserId: _warm, inviteId: id),
            throwsA(isA<AuthorInviteRequestNotOpenException>()),
          );
          expect(await rowSet(_warm), isEmpty);
          expect(
            (await _invite(writer, id)).status,
            AuthorInviteStatus.pending.code,
          );
        },
      );

      test(
        '0 → 5 → 7 keeps the invite pending; accept in review is refused, '
        'accept after reopen succeeds',
        () async {
          await admitHelper();
          final id = await invited(_warm);
          expect(
            await _inboxStatus(writer, _warm),
            0,
            reason: 'the invitee never touched the pinned inbox row',
          );

          await s.closure.close(authorId: _author, beaconId: _child);
          expect(
            await _status(writer, _child),
            BeaconStatus.reviewOpen.smallintValue,
          );
          expect(await _inboxStatus(writer, _warm), 3);
          await expectLater(
            s.invites.accept(actorUserId: _warm, inviteId: id),
            throwsA(isA<AuthorInviteRequestNotOpenException>()),
          );

          await s.closure.reopen(authorId: _author, beaconId: _child);
          expect(
            await _status(writer, _child),
            BeaconStatus.needsMoreHelp.smallintValue,
          );
          expect(
            await _inboxStatus(writer, _warm),
            0,
            reason: 'reopen reverts the review tombstone',
          );
          expect(
            (await _invite(writer, id)).status,
            AuthorInviteStatus.pending.code,
          );

          final accepted = await s.invites.accept(
            actorUserId: _warm,
            inviteId: id,
          );
          expect(accepted.status, AuthorInviteStatus.accepted);
          expect(await rowSet(_warm), isNotEmpty);
        },
      );

      test('closure close with no members expires invites', () async {
        final id = await invited(_cold);
        await s.closure.close(authorId: _author, beaconId: _child);
        expect(
          await _status(writer, _child),
          BeaconStatus.closed.smallintValue,
        );
        await expectExpired(id, _cold);
      });

      test('closure finalize (review → closed) expires invites', () async {
        await admitHelper();
        final id = await invited(_cold);
        await s.closure.close(authorId: _author, beaconId: _child);
        expect(
          (await _invite(writer, id)).status,
          AuthorInviteStatus.pending.code,
        );

        // The status write `ClosureFinalizeCase` makes.
        await s.uow.run(
          actorUserId: _author,
          action: () => s.beacons.recordBeaconStatusTransition(
            beaconId: _child,
            fromStatus: BeaconStatus.reviewOpen,
            toStatus: BeaconStatus.closed,
            reason: BeaconLifecycleChangeReason.closureExpired,
            actorId: null,
          ),
        );
        await expectExpired(id, _cold);
      });

      test(
        'cancel expires invites; accept after cancel writes no rows',
        () async {
          final id = await invited(_cold);
          await s.beaconCase.beaconCancel(beaconId: _child, userId: _author);
          expect(
            await _status(writer, _child),
            BeaconStatus.cancelled.smallintValue,
          );
          await expectExpired(id, _cold);

          await expectLater(
            s.invites.accept(actorUserId: _cold, inviteId: id),
            throwsA(isA<AuthorInviteNotPendingException>()),
          );
          expect(await rowSet(_cold), isEmpty);
        },
      );

      test('delete expires invites', () async {
        final id = await invited(_cold);
        await s.beaconCase.deleteById(beaconId: _child, userId: _author);
        expect(
          await _status(writer, _child),
          BeaconStatus.deleted.smallintValue,
        );
        await expectExpired(id, _cold);
      });

      test('account erasure of the author clears the receipts', () async {
        await invited(_cold);
        await s.erasure.deleteById(id: _author);

        expect(await _inviteCount(writer), 0, reason: 'inviter cascade');
        final receipts = await _receipts(writer, kind: 'authorInviteReceived');
        expect(receipts.map((r) => r.cleared), everyElement(isTrue));
        expect(await _contactEvidence(writer), isEmpty);
      });
    });

    test('a block between the pair withdraws the pending invite', () async {
      final id = await invited(_warm);

      await s.blocks.block(
        blockerId: _warm,
        blockedId: _author,
        cascadeMode: 0,
      );

      expect(
        (await _invite(writer, id)).status,
        AuthorInviteStatus.withdrawn.code,
      );
      expect(
        (await _receipts(writer, kind: 'authorInviteReceived')).single.cleared,
        isTrue,
      );
    });

    group('approval credit across the Post (C7)', () {
      // The Post chain: Post author → _cold → _warm.
      Future<void> chainToWarm({String via = _cold}) async {
        await _postEdge(writer, 'Fai4p1', _postAuthor, via, minutesAgo: 120);
        await _postEdge(
          writer,
          'Fai4p2',
          via,
          _warm,
          minutesAgo: 60,
          parent: 'Fai4p1',
        );
      }

      test('accept credits the sender of the recorded Post arrival', () async {
        await chainToWarm();
        final id = await invited(_warm);
        expect((await _invite(writer, id)).arrival, 'Fai4p2');

        await s.invites.accept(actorUserId: _warm, inviteId: id);

        expect(await _approvals(writer), [(_warm, _cold, 'Fai4p2')]);
      });

      test('offerHelp by a pending invitee credits the Post arrival', () async {
        await chainToWarm();
        await invited(_warm);

        await s.offerHelp(_warm);

        expect(await _approvals(writer), [(_warm, _cold, 'Fai4p2')]);
      });

      test('the budder as the Post arrival sender earns nothing', () async {
        await chainToWarm(via: _author);
        final id = await invited(_warm);

        await s.invites.accept(actorUserId: _warm, inviteId: id);

        expect(await _approvals(writer), isEmpty);
      });

      test('the Post author (no arrival) earns no approval credit', () async {
        final id = await invited(_postAuthor);
        expect((await _invite(writer, id)).arrival, isNull);

        await s.invites.accept(actorUserId: _postAuthor, inviteId: id);

        expect(await _approvals(writer), isEmpty);
      });

      test('a superseded invite does not use the Post arrival', () async {
        await _postEdge(writer, 'Fai4p1', _postAuthor, _warm, minutesAgo: 120);
        await _postEdge(
          writer,
          'Fai4p2',
          _warm,
          _cold,
          minutesAgo: 60,
          parent: 'Fai4p1',
        );
        await s.forward(_author, _cold);
        await s.offerHelp(_cold);
        final id = await invited(_cold);
        expect((await _invite(writer, id)).arrival, 'Fai4p2');

        await s.coordination.acceptHelpOffer(
          beaconId: _child,
          offerUserId: _cold,
          actorUserId: _author,
        );

        expect(
          (await _invite(writer, id)).status,
          AuthorInviteStatus.superseded.code,
        );
        expect(await _approvals(writer), isEmpty);
      });

      test('kill switch off: no cross-beacon approval credit', () async {
        final off = _Stack.build(
          database,
          target.databaseEnv,
          budRouteCredit: false,
        );
        await chainToWarm();
        final id = (await off.invites.create(
          actorUserId: _author,
          beaconId: _child,
          inviteeId: _warm,
        )).inviteId!;

        await off.invites.accept(actorUserId: _warm, inviteId: id);

        expect(await _approvals(writer), isEmpty);
      });
    });

    group('read projections (C6)', () {
      test('the invitee sees their own pending invite and note', () async {
        final id = await invited(_warm, note: 'You have a van');
        await invited(_cold);

        final mine = await s.invites.myPendingInvites(actorUserId: _warm);
        expect(mine, hasLength(1));
        final pending = mine.single;
        expect(pending.inviteId, id);
        expect(pending.beaconId, _child);
        expect(pending.beaconTitle, 'Move the piano');
        expect(pending.inviterId, _author);
        expect(pending.sourcePostId, _post);
        expect(pending.note, 'You have a van');
        expect(pending.createdAt, isNotNull);

        await s.invites.decline(actorUserId: _warm, inviteId: id);
        expect(await s.invites.myPendingInvites(actorUserId: _warm), isEmpty);
        expect(
          await s.invites.myPendingInvites(actorUserId: _author),
          isEmpty,
          reason: 'the inviter is not an invitee',
        );
      });

      test('the author sees every invite on their child', () async {
        final warmId = await invited(_warm, note: 'van');
        final coldId = await invited(_cold);
        await s.invites.decline(actorUserId: _cold, inviteId: coldId);

        final all = await s.invites.beaconInvites(
          actorUserId: _author,
          beaconId: _child,
        );
        expect(
          {for (final i in all) i.id: (i.inviteeId, i.status, i.note)},
          {
            warmId: (_warm, AuthorInviteStatus.pending, 'van'),
            coldId: (_cold, AuthorInviteStatus.declined, null),
          },
        );
        expect(all.map((i) => i.createdAt), everyElement(isNotNull));
      });

      test('an observer, an invitee or anyone else gets nothing', () async {
        await invited(_warm, note: 'van');

        for (final viewer in [_warm, _cold, _postAuthor, _late]) {
          expect(
            await s.invites.beaconInvites(
              actorUserId: viewer,
              beaconId: _child,
            ),
            isEmpty,
            reason: viewer,
          );
        }
      });

      test('the pinned For-you row carries the invite and folds its '
          'receipt', () async {
        final id = await invited(_warm);
        await s.forward(_author, _cold);
        final attention = AttentionRepository(database);

        final warmOffers = await attention.activityOffers(accountId: _warm);
        expect(warmOffers.items.map((i) => i.beaconId), [_child]);
        final row = warmOffers.items.single;
        expect(row.inviteId, id);
        expect(row.eventTotal, 0, reason: 'the receipt is the card itself');
        expect(row.eventsPreview, isEmpty);

        final feed = await attention.attentionFeed(
          accountId: _warm,
          view: AttentionFeedView.all,
          surface: AttentionSurface.activity,
        );
        expect(
          feed.page.items.where((r) => r.beaconId == _child),
          isEmpty,
          reason: 'no second card for the same Request',
        );

        final coldOffers = await attention.activityOffers(accountId: _cold);
        expect(coldOffers.items.single.beaconId, _child);
        expect(coldOffers.items.single.inviteId, isNull);

        await s.invites.decline(actorUserId: _warm, inviteId: id);
        expect(
          (await attention.activityOffers(accountId: _warm)).items,
          isEmpty,
        );
      });
    });

    group('People tab (D4)', () {
      test('the author sees the snapshot observers, a blocked one '
          'hidden', () async {
        expect(
          await s.invites.budObservers(actorUserId: _author, beaconId: _child),
          [..._observers]..sort(),
        );

        await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_cold', '$_author', '$_cold')
''');
        expect(
          await s.invites.budObservers(actorUserId: _author, beaconId: _child),
          ([..._observers]..remove(_cold))..sort(),
        );
      });

      test(
        'an observer, the Post author or anyone else gets nothing',
        () async {
          for (final viewer in [_warm, _postAuthor, _late]) {
            expect(
              await s.invites.budObservers(
                actorUserId: viewer,
                beaconId: _child,
              ),
              isEmpty,
              reason: viewer,
            );
          }
          expect(
            await s.invites.budObservers(
              actorUserId: _postAuthor,
              beaconId: _post,
            ),
            isEmpty,
            reason: 'a Post has no observers',
          );
        },
      );

      test('the parent reference marks a readable Post parent', () async {
        final hierarchy = BeaconHierarchyRepository(database);
        final reference = await hierarchy.loadParentReference(
          childBeaconId: _child,
          viewerId: _postAuthor,
        );
        expect(reference.state, BeaconParentReferenceState.available);
        expect(reference.beaconId, _post);
        expect(reference.isPost, isTrue);

        final outsider = await hierarchy.loadParentReference(
          childBeaconId: _child,
          viewerId: _late,
        );
        expect(outsider.state, BeaconParentReferenceState.none);
        expect(outsider.isPost, isFalse);
      });
    });
  });
}

typedef _InviteRow = ({
  String inviter,
  String invitee,
  String? sourcePost,
  String? forwardEdgeId,
  bool warm,
  String? note,
  int status,
  String? arrival,
});

Future<_InviteRow> _invite(Connection writer, String id) async {
  final r = (await writer.execute(
    Sql.named(
      'SELECT inviter_id, invitee_id, source_post_id, forward_edge_id, warm, '
      'note, status, arrival_post_edge_id '
      'FROM public.beacon_author_invite WHERE id = @id',
    ),
    parameters: {'id': id},
  )).single;
  return (
    inviter: r[0]! as String,
    invitee: r[1]! as String,
    sourcePost: r[2] as String?,
    forwardEdgeId: r[3] as String?,
    warm: r[4]! as bool,
    note: r[5] as String?,
    status: r[6]! as int,
    arrival: r[7] as String?,
  );
}

Future<int> _inviteCount(Connection writer) async =>
    (await writer.execute(
          'SELECT count(*)::int FROM public.beacon_author_invite',
        )).single.single!
        as int;

typedef _EdgeRow = ({
  String sender,
  String recipient,
  String note,
  bool exempt,
  bool cancelled,
});

Future<_EdgeRow> _edge(Connection writer, String id) async {
  final r = (await writer.execute(
    Sql.named(
      'SELECT sender_id, recipient_id, note, contact_sweep_exempt, '
      'cancelled_at IS NOT NULL FROM public.beacon_forward_edge WHERE id = @id',
    ),
    parameters: {'id': id},
  )).single;
  return (
    sender: r[0]! as String,
    recipient: r[1]! as String,
    note: r[2]! as String,
    exempt: r[3]! as bool,
    cancelled: r[4]! as bool,
  );
}

Future<({int? outcome, DateTime? resolvedAt})> _contact(
  Connection writer,
  String edge,
) async {
  final row = (await writer.execute(
    Sql.named(
      'SELECT contact_outcome, contact_resolved_at '
      'FROM public.beacon_forward_edge WHERE id = @id',
    ),
    parameters: {'id': edge},
  )).single;
  return (outcome: row[0] as int?, resolvedAt: row[1] as DateTime?);
}

Future<List<String>> _contactEvidence(Connection writer) async {
  final rows = await writer.execute(
    'SELECT source_key FROM public.trust_evidence '
    "WHERE source_key LIKE 'contact:%:noisy' AND retracted_at IS NULL "
    'ORDER BY source_key',
  );
  return [for (final r in rows) r.single! as String];
}

Future<List<String>> _trustEvidenceFor(Connection writer, String user) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT source_key FROM public.trust_evidence '
      'WHERE subject_user_id = @u OR object_user_id = @u ORDER BY source_key',
    ),
    parameters: {'u': user},
  );
  return [for (final r in rows) r.single! as String];
}

/// Live stream-2 approval rows: (helper, credited sender, arrival edge).
Future<List<(String, String, String?)>> _approvals(Connection writer) async {
  final rows = await writer.execute('''
SELECT subject_user_id, object_user_id, metadata->>'arrival_edge_id'
FROM public.trust_evidence
WHERE source_key LIKE 'approval:%' AND retracted_at IS NULL
ORDER BY source_key
''');
  return [
    for (final r in rows) (r[0]! as String, r[1]! as String, r[2] as String?),
  ];
}

/// A forward edge [sender] → [recipient] on the Post, [minutesAgo] old.
Future<void> _postEdge(
  Connection writer,
  String id,
  String sender,
  String recipient, {
  required int minutesAgo,
  String? parent,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, parent_edge_id, created_at)
VALUES (@id, @post, @sender, @recipient, @parent,
        now() - make_interval(mins => @age))
'''),
  parameters: {
    'id': id,
    'post': _post,
    'sender': sender,
    'recipient': recipient,
    'parent': parent,
    'age': minutesAgo,
  },
);

Future<int?> _inboxStatus(Connection writer, String user) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT status FROM public.inbox_item '
      'WHERE user_id = @u AND beacon_id = @b',
    ),
    parameters: {'u': user, 'b': _child},
  );
  return rows.isEmpty ? null : rows.single.single as int?;
}

Future<Set<String>> _eligiblePinned(Connection writer, String viewer) async {
  final rows = await writer.execute(
    'WITH ${AttentionDismissibleSql.prelude} '
    'SELECT beacon_id FROM eligible_pinned',
    parameters: [viewer],
  );
  return {for (final r in rows) r[0]! as String};
}

Future<int> _status(Connection writer, String beacon) async =>
    (await writer.execute(
          Sql.named('SELECT status FROM public.beacon WHERE id = @b'),
          parameters: {'b': beacon},
        )).single.single!
        as int;

Future<int?> _roomAccess(Connection writer, String user) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT room_access FROM public.beacon_participant '
      'WHERE beacon_id = @b AND user_id = @u',
    ),
    parameters: {'b': _child, 'u': user},
  );
  return rows.isEmpty ? null : rows.single.single as int?;
}

Future<String?> _offerMessage(Connection writer, String user) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT message FROM public.beacon_help_offer '
      'WHERE beacon_id = @b AND user_id = @u',
    ),
    parameters: {'b': _child, 'u': user},
  );
  return rows.isEmpty ? null : rows.single.single as String?;
}

typedef _Receipt = ({
  String account,
  String kind,
  String sourceEventKey,
  bool cleared,
});

Future<List<_Receipt>> _receipts(Connection writer, {String? kind}) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT account_id, kind, source_event_key, cleared_at IS NOT NULL '
      'FROM public.notification_outbox '
      'WHERE beacon_id = @b AND (@k::text IS NULL OR kind = @k::text) '
      'ORDER BY account_id, kind, source_event_key',
    ),
    parameters: {'b': _child, 'k': kind},
  );
  return [
    for (final r in rows)
      (
        account: r[0]! as String,
        kind: r[1]! as String,
        sourceEventKey: r[2]! as String,
        cleared: r[3]! as bool,
      ),
  ];
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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('ai4', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_postAuthor', '', '', 0, 1, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, parent_beacon_id,
   is_discoverable, published_at)
VALUES ('$_child', '$_author', 'Move the piano', 'Saturday', 0, '$_post',
        false, now())
''');
  for (final observer in _observers) {
    await writer.execute('''
INSERT INTO public.beacon_bud_observer (beacon_id, user_id)
VALUES ('$_child', '$observer')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('Rai4warm0001', '$_post', '$_warm', 'I have a van')
''');
  await writer.execute('''
INSERT INTO public.post_first_response
  (beacon_id, user_id, source_kind, source_id)
VALUES ('$_post', '$_warm', 1, 'Rai4warm0001')
''');
  await writer.execute('''
INSERT INTO public.user_availability (user_id, resume_on)
VALUES ('$_paused', public.utc_today() + 3)
''');
}

final class _Stack {
  _Stack({
    required this.uow,
    required this.beacons,
    required this.invites,
    required this.helpOffers,
    required this.coordination,
    required this.closure,
    required this.beaconCase,
    required this.blocks,
    required this.erasure,
    required this.sweep,
    required this.forwardEdges,
  });

  final MutatingUnitOfWork uow;
  final BeaconRepository beacons;
  final AuthorInviteCase invites;
  final HelpOfferCase helpOffers;
  final CoordinationCase coordination;
  final ClosureCase closure;
  final BeaconCase beaconCase;
  final UserBlockCase blocks;
  final UserErasureCase erasure;
  final ContactResolutionSweepCase sweep;
  final ForwardEdgeRepository forwardEdges;

  /// An ordinary forward [sender] → [recipient] on the child; returns the
  /// edge id.
  Future<String> forward(String sender, String recipient) async {
    final batch = await forwardEdges.createBatch(
      beaconId: _child,
      senderId: sender,
      recipientIds: [recipient],
      batchId: 'Xai4${recipient.substring(4)}',
      noteForRecipient: (_) => 'ordinary',
    );
    return batch.createdEdges.single.edgeId;
  }

  Future<void> offerHelp(String user, {String message = ''}) =>
      helpOffers.offerHelp(beaconId: _child, userId: user, message: message);

  /// [budRouteCredit] is the closure's `TRUST_BUD_ROUTE_CREDIT_ENABLED`.
  factory _Stack.build(TenturaDb db, Env env, {bool budRouteCredit = true}) {
    final logger = Logger('AuthorInviteCasePgTest');
    final closureEnv = budRouteCredit
        ? env
        : Env(environment: Environment.test, trustBudRouteCreditEnabled: false);
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
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        room,
        db,
        helpOffers,
        commitments,
      ),
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
      finalizer: _NoFinalizer(),
      env: closureEnv,
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
    final postLock = PostLockRepository(db);
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
    final invites = AuthorInviteCase(
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
      PostBudRepository(db, _Visibility({_cold, _helper})),
      beacons,
      closure,
      forwardEdges,
      inbox,
      blockRepository,
      commitments,
      forwardCase,
    );
    return _Stack(
      uow: uow,
      beacons: beacons,
      forwardEdges: forwardEdges,
      invites: invites,
      closure: closure,
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
        guard: FakeBeaconAccessGuard(),
        closureCase: closure,
        authorInvites: authorInvites,
        env: env,
        logger: logger,
      ),
      beaconCase: BeaconCase(
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
      ),
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
      erasure: buildUserErasureTestStack(
        db: db,
        userRepository: users,
        lifecycleEffects: lifecycleEffects,
        attention: attention,
      ).erasureCase,
      sweep: ContactResolutionSweepCase(
        unitOfWork: uow,
        forwardEdgeRepository: forwardEdges,
        trustLedger: TrustLedgerRepository(db),
        env: env,
        logger: logger,
      ),
    );
  }
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _NoFinalizer extends Fake implements ClosureFinalizerPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

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

/// Forward visibility of the Request author: only [visible] peers pass.
final class _Visibility extends Fake implements PersonVisibilityRepositoryPort {
  _Visibility(this.visible);

  final Set<String> visible;

  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.where(visible.contains).toSet();
}
