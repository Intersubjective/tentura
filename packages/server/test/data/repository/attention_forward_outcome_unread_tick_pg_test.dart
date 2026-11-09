@Tags(['pg', 'mr', 'repo-files'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/attention_axis_contract.dart';
import '../../support/disposable_pg_target.dart';

/// A forward row the viewer received sits in the Activity stream as a
/// synthetic `inbox:<beaconId>` row. When somebody else relabels it to an
/// outcome (the author closes or deletes the Request before the viewer
/// answered), the row moves up to the moment of the relabel and carries one
/// unread tick until the viewer marks it seen. The viewer's own decisions
/// (watching, not interested) never tick.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_OUTCOME_TICK_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_outcome_tick',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('forward row outcome tick', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository stream;
    late AttentionAckRepository ack;
    late BeaconRepository beacons;
    late InboxRepository inbox;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      stream = AttentionRepository(database);
      ack = AttentionAckRepository(database);
      beacons = BeaconRepository(database);
      inbox = InboxRepository(database);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> resetFixture() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_help_offer,
  public.inbox_item,
  public.attention_request_state,
  public.beacon_forward_edge,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_viewerId, _authorId, _otherRecipientId]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @authorId, 'Outcome tick', 'A Request forwarded to the viewer', 0)
'''),
        parameters: {'id': _requestId, 'authorId': _authorId},
      );
      for (final recipient in [_viewerId, _otherRecipientId]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (@edgeId, @beaconId, @authorId, @recipientId, now(), NULL)
ON CONFLICT DO NOTHING
'''),
          parameters: {
            'edgeId': 'FE$_requestId$recipient',
            'beaconId': _requestId,
            'authorId': _authorId,
            'recipientId': recipient,
          },
        );
        // Pending forward, received well before anything in this test.
        await writer.execute(
          Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@u, @b, 0, 1, CAST(@at AS timestamptz), '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET
  status = 0,
  forward_count = 1,
  latest_forward_at = EXCLUDED.latest_forward_at
'''),
          parameters: {'u': recipient, 'b': _requestId, 'at': _forwardedAt},
        );
        await writer.execute(
          Sql.named('''
UPDATE public.attention_request_state
SET first_entry_at = CAST(@at AS timestamptz)
WHERE account_id = @u AND beacon_id = @b
'''),
          parameters: {'u': recipient, 'b': _requestId, 'at': _forwardedAt},
        );
      }
      // An Activity row that entered after the forward and before any
      // relabel: the yardstick for "moves up".
      await writer.execute(
        Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'connections', 'inviteAccepted', 'normal',
  'Invite', 'Body', '/profile', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @sourceEventKey,
  'profile', 'invite_accepted', '{"eventType":"inviteAccepted"}'::jsonb,
  'standard', 'profile'
)
'''),
        parameters: {
          'id': _middleReceiptId,
          'accountId': _viewerId,
          'dedupKey': 'dedup-$_middleReceiptId',
          'createdAt': _middleReceiptAt,
          'sourceEventKey': 'source-$_middleReceiptId',
        },
      );
    }

    setUp(resetFixture);

    // --- the paths that relabel a forward row ------------------------------

    /// The author closes the Request before the viewer answered: every
    /// pending recipient's row becomes `closedBeforeResponse`.
    Future<void> authorClosesRequest() => database.withMutatingUser(
      _authorId,
      () => beacons.recordBeaconStatusTransition(
        beaconId: _requestId,
        fromStatus: BeaconStatus.open,
        toStatus: BeaconStatus.closed,
        reason: BeaconLifecycleChangeReason.directClose,
        actorId: _authorId,
      ),
    );

    /// The author then deletes the closed Request: the row becomes
    /// `deletedBeforeResponse`.
    Future<void> authorDeletesClosedRequest() => database.withMutatingUser(
      _authorId,
      () => beacons.recordBeaconStatusTransition(
        beaconId: _requestId,
        fromStatus: BeaconStatus.closed,
        toStatus: BeaconStatus.deleted,
        reason: BeaconLifecycleChangeReason.deleted,
        actorId: _authorId,
      ),
    );

    /// The viewer answers the forward themselves (1 = watching,
    /// 2 = not interested).
    Future<void> viewerAnswers(int status) => database.withMutatingUser(
      _viewerId,
      () => inbox.setStatus(
        userId: _viewerId,
        beaconId: _requestId,
        status: status,
        rejectionMessage: '',
      ),
    );

    /// The viewer offers help: the row reads `helping` without any relabel.
    Future<void> viewerOffersHelp() => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (@b, @u, 'offer', 0, now(), now())
'''),
      parameters: {'b': _requestId, 'u': _viewerId},
    );

    Future<void> viewerMarksSeen(List<String> ids) =>
        ack.markSeen(accountId: _viewerId, ids: ids);

    // --- what the viewer sees ---------------------------------------------

    Future<List<AttentionReceipt>> activityPage() async {
      final feed = await stream.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      return feed.page.items;
    }

    Future<AttentionReceipt> forwardRow() async {
      final rows = (await activityPage())
          .where((item) => item.id == 'inbox:$_requestId')
          .toList();
      expect(
        rows,
        hasLength(1),
        reason: 'the viewer has exactly one forward row for the Request',
      );
      return rows.single;
    }

    Future<_OutcomeMarker> outcomeMarker(String userId) async {
      final rows = await writer.execute(
        Sql.named('''
SELECT outcome_changed_at, outcome_changed_by, outcome_seen_at
FROM public.inbox_item
WHERE user_id = @u AND beacon_id = @b
'''),
        parameters: {'u': userId, 'b': _requestId},
      );
      final row = rows.single;
      return _OutcomeMarker(
        changedAt: (row[0] as DateTime?)?.toUtc(),
        changedBy: row[1] as String?,
        seenAt: (row[2] as DateTime?)?.toUtc(),
      );
    }

    test(
      'a Request closed by its author records who relabelled the forward row',
      () async {
        await authorClosesRequest();

        for (final recipient in [_viewerId, _otherRecipientId]) {
          final marker = await outcomeMarker(recipient);
          expect(marker.changedAt, isNotNull, reason: recipient);
          expect(marker.changedBy, _authorId, reason: recipient);
          expect(marker.seenAt, isNull, reason: recipient);
        }
      },
    );

    test(
      'a forward row relabelled by somebody else moves up to the relabel and '
      'reads as unseen',
      () async {
        await authorClosesRequest();
        final marker = await outcomeMarker(_viewerId);
        final page = await activityPage();
        final row = await forwardRow();

        expect(row.itemKind, AttentionItemKind.forward);
        expect(row.forwardOutcome, 'closedBeforeResponse');
        expect(marker.changedAt, isNotNull);
        expect(
          row.createdAt.toUtc().isAtSameMomentAs(marker.changedAt!),
          isTrue,
          reason:
              'position must be outcome_changed_at (${marker.changedAt}), '
              'got ${row.createdAt.toUtc()}',
        );
        expect(
          row.createdAt.toUtc().isAfter(DateTime.parse(_forwardedAt)),
          isTrue,
          reason: 'the relabel is later than the forward entered',
        );
        expect(
          row.seenAt,
          isNull,
          reason: 'a relabel by another user is one unread tick',
        );

        final ids = [for (final item in page) item.id];
        expect(ids, contains(_middleReceiptId));
        expect(
          ids.indexOf('inbox:$_requestId'),
          lessThan(ids.indexOf(_middleReceiptId)),
          reason:
              'the relabelled row is ordered above an Activity row that '
              'entered between the forward and the relabel',
        );
      },
    );

    for (final (status, word) in [(1, 'watching'), (2, 'notInterested')]) {
      test(
        'the viewer marking a forward as $word adds no unread tick',
        () async {
          await viewerAnswers(status);

          final marker = await outcomeMarker(_viewerId);
          expect(
            marker.changedBy,
            _viewerId,
            reason: "the viewer's own answer is recorded as theirs",
          );

          final row = await forwardRow();
          expect(row.forwardOutcome, word);
          expect(
            row.seenAt,
            isNotNull,
            reason: "the viewer's own relabel never reads as unseen",
          );
        },
      );
    }

    test(
      'marking the relabelled row seen clears the tick and keeps its position',
      () async {
        await authorClosesRequest();
        final changedAt = (await outcomeMarker(_viewerId)).changedAt;
        expect(changedAt, isNotNull);

        await viewerMarksSeen(['inbox:$_requestId']);

        final marker = await outcomeMarker(_viewerId);
        expect(marker.seenAt, isNotNull);
        expect(
          marker.seenAt!.isBefore(changedAt!),
          isFalse,
          reason: 'outcome_seen_at is at or after outcome_changed_at',
        );

        final row = await forwardRow();
        expect(row.seenAt, isNotNull, reason: 'the tick is cleared');
        expect(
          row.createdAt.toUtc().isAtSameMomentAs(changedAt),
          isTrue,
          reason: 'marking seen does not move the row back down',
        );
      },
    );

    test(
      'marking a forward row seen touches only the viewer and still marks '
      'receipts passed alongside it',
      () async {
        await authorClosesRequest();

        await viewerMarksSeen(['inbox:$_requestId', _middleReceiptId]);

        expect((await outcomeMarker(_viewerId)).seenAt, isNotNull);
        expect(
          (await outcomeMarker(_otherRecipientId)).seenAt,
          isNull,
          reason: "another recipient's row of the same Request stays unseen",
        );
        final receipt = await writer.execute(
          Sql.named(
            'SELECT seen_at FROM public.notification_outbox WHERE id = @id',
          ),
          parameters: {'id': _middleReceiptId},
        );
        expect(receipt.single[0], isNotNull);
      },
    );

    test(
      'a later relabel by somebody else ticks the seen row again and moves it '
      'up again',
      () async {
        await authorClosesRequest();
        final firstChangedAt = (await outcomeMarker(_viewerId)).changedAt;
        expect(firstChangedAt, isNotNull);
        await viewerMarksSeen(['inbox:$_requestId']);
        expect((await forwardRow()).seenAt, isNotNull);

        await authorDeletesClosedRequest();

        final marker = await outcomeMarker(_viewerId);
        expect(marker.changedBy, _authorId);
        expect(marker.changedAt, isNotNull);
        expect(
          marker.seenAt,
          isNotNull,
          reason: 'the earlier mark-seen is still recorded',
        );
        expect(marker.changedAt!.isAfter(firstChangedAt!), isTrue);
        expect(marker.changedAt!.isAfter(marker.seenAt!), isTrue);

        final row = await forwardRow();
        expect(row.forwardOutcome, 'deletedBeforeResponse');
        expect(row.seenAt, isNull, reason: 'the new relabel is a new tick');
        expect(
          row.createdAt.toUtc().isAtSameMomentAs(marker.changedAt!),
          isTrue,
          reason: 'the row moves up to the new relabel',
        );
      },
    );

    test(
      'a forward row whose outcome never changed keeps its entry position and '
      'reads as seen',
      () async {
        await viewerOffersHelp();

        final marker = await outcomeMarker(_viewerId);
        expect(marker.changedAt, isNull);

        final row = await forwardRow();
        expect(row.forwardOutcome, 'helping');
        expect(
          row.createdAt.toUtc().isAtSameMomentAs(DateTime.parse(_forwardedAt)),
          isTrue,
          reason: 'position is entry_at',
        );
        expect(
          row.seenAt?.toUtc(),
          DateTime.parse(_forwardedAt),
          reason: 'seen_at stays latest_forward_at',
        );
      },
    );

    /// Puts the viewer's forward row into the state a matrix case names
    /// and checks what the Activity stream shows for it.
    Future<void> expectCase(_TickCase c) async {
      await resetFixture();
      switch (c.relabelledBy) {
        case 'otherUser':
          await authorClosesRequest();
        case 'viewer':
          await viewerAnswers(2);
        case 'nobody':
          await viewerOffersHelp();
        default:
          fail('case "${c.name}": unknown relabelledBy ${c.relabelledBy}');
      }
      if (c.markedSeenAfter) {
        await viewerMarksSeen(['inbox:$_requestId']);
      }

      final marker = await outcomeMarker(_viewerId);
      final row = await forwardRow();
      expect(row.seenAt == null, c.unseen, reason: 'case "${c.name}": unseen');
      final expectedPosition = switch (c.positionKey) {
        'outcome_changed_at' => marker.changedAt,
        'entry_at' => DateTime.parse(_forwardedAt),
        _ => fail('case "${c.name}": unknown positionKey ${c.positionKey}'),
      };
      expect(
        expectedPosition,
        isNotNull,
        reason: 'case "${c.name}": ${c.positionKey} is set',
      );
      expect(
        row.createdAt.toUtc().isAtSameMomentAs(expectedPosition!),
        isTrue,
        reason:
            'case "${c.name}": created_at ${row.createdAt.toUtc()} '
            'must equal ${c.positionKey} $expectedPosition',
      );
    }

    test(
      'every outcome-tick case reads in the real stream as the rule says',
      () async {
        for (final c in _tickMatrix) {
          await expectCase(c);
        }
      },
    );

    test(
      "the viewer's own answer after somebody else changed the row leaves no "
      'tick',
      () async {
        // Watching, then the author re-invites (back to pending), then the
        // viewer answers «Can't help»: the last change is the viewer's.
        await viewerAnswers(1);
        await database.withMutatingUser(
          _authorId,
          () => inbox.repinForAuthorInvite(
            userId: _viewerId,
            beaconId: _requestId,
          ),
        );
        await viewerAnswers(2);

        final marker = await outcomeMarker(_viewerId);
        expect(marker.changedBy, _viewerId);
        expect(marker.changedAt, isNotNull);

        final row = await forwardRow();
        expect(row.forwardOutcome, 'notInterested');
        expect(
          row.seenAt,
          isNotNull,
          reason: 'outcome_changed_by is the viewer, so there is no tick',
        );
        expect(
          row.createdAt.toUtc().isAtSameMomentAs(marker.changedAt!),
          isTrue,
          reason: 'position is GREATEST(entry_at, outcome_changed_at)',
        );
      },
    );

    test(
      'the attention contract records the forward outcome tick as the server '
      'SQL and the real stream apply it',
      () async {
        final contract = AttentionAxisContract.load().forwardOutcomeTick;

        String squash(String s) =>
            s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
        expect(
          squash(contract.position),
          contains(squash('GREATEST(entry_at, outcome_changed_at)')),
        );
        expect(
          squash(contract.unseen),
          contains(squash('outcome_changed_by <> viewer')),
        );
        expect(
          squash(contract.unseen),
          contains(
            squash(
              "outcome_changed_at > COALESCE(outcome_seen_at, '-infinity')",
            ),
          ),
        );
        // Mark-seen is part of the recorded rule: an `inbox:<beaconId>` id
        // is what writes the viewer's outcome_seen_at.
        expect(squash(contract.markSeen), contains('inbox:'));
        expect(squash(contract.markSeen), contains('outcome_seen_at'));

        // Drift guard: each recorded SQL fragment must literally appear in
        // lib/data/repository/attention_repository.dart (the loader reads
        // that file, not the JSON). The keyword checks only stop a fragment
        // from being a token that is trivially present there; whether the
        // SQL *does* the rule is proven by the stream cases below.
        final sql = contract.sql;
        for (final word in ['greatest', 'entry_at', 'outcome_changed_at']) {
          expect(squash(sql['position']!), contains(word), reason: 'position');
        }
        for (final word in ['outcome_changed_by', 'outcome_seen_at']) {
          expect(squash(sql['unseen']!), contains(word), reason: 'unseen');
        }
        expect(squash(sql['markSeen']!), contains('outcome_seen_at'));
        expect(contract.assertMatchesServerSql, returnsNormally);

        // The recorded cases are this file's matrix, value for value, so
        // the documented behaviour cannot drop or soften a case.
        String key(_TickCase c) =>
            '${c.relabelledBy}/markedSeen=${c.markedSeenAfter} -> '
            'unseen=${c.unseen}, position=${c.positionKey}';
        final recorded = [
          for (final c in contract.cases)
            (
              name: c.name,
              relabelledBy: c.relabelledBy,
              markedSeenAfter: c.markedSeenAfter,
              unseen: c.unseen,
              positionKey: c.positionKey,
            ),
        ];
        expect(
          {for (final c in recorded) key(c)},
          containsAll({for (final c in _tickMatrix) key(c)}),
        );

        for (final c in recorded) {
          await expectCase(c);
        }
      },
    );
  }, skip: skipReason);
}

final class _OutcomeMarker {
  const _OutcomeMarker({
    required this.changedAt,
    required this.changedBy,
    required this.seenAt,
  });

  final DateTime? changedAt;
  final String? changedBy;
  final DateTime? seenAt;
}

const _viewerId = 'Uouttick01';
const _authorId = 'Uouttick02';
const _otherRecipientId = 'Uouttick03';
const _requestId = 'Bouttickreq';
const _middleReceiptId = 'Nouttickmid';
const _forwardedAt = '2026-08-01T10:00:00Z';
const _middleReceiptAt = '2026-08-02T10:00:00Z';

typedef _TickCase = ({
  String name,
  String relabelledBy,
  bool markedSeenAfter,
  bool unseen,
  String positionKey,
});

/// The forward-row outcome tick, case by case. The contract JSON must record
/// the same cases (`forwardOutcomeTick.cases`).
const List<_TickCase> _tickMatrix = [
  (
    name: 'relabelled by another user ticks and moves up',
    relabelledBy: 'otherUser',
    markedSeenAfter: false,
    unseen: true,
    positionKey: 'outcome_changed_at',
  ),
  (
    name: 'marking it seen clears the tick and keeps the position',
    relabelledBy: 'otherUser',
    markedSeenAfter: true,
    unseen: false,
    positionKey: 'outcome_changed_at',
  ),
  (
    name: "the viewer's own relabel never ticks",
    relabelledBy: 'viewer',
    markedSeenAfter: false,
    unseen: false,
    positionKey: 'outcome_changed_at',
  ),
  (
    name: 'a row whose outcome never changed stays at its entry',
    relabelledBy: 'nobody',
    markedSeenAfter: false,
    unseen: false,
    positionKey: 'entry_at',
  ),
];
