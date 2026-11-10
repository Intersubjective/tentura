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

import '../../support/disposable_pg_target.dart';

/// A forward row whose Request the author closed carries one unread tick
/// (`inbox_item.outcome_seen_at` older than `outcome_changed_at`). The tick
/// must go away however the viewer deals with it: «Read all» (`markAllSeen`),
/// opening the Request anywhere (`markSeenForBeacon`), or tapping the row.
/// And only a move INTO an outcome ticks: reopening a Request, or a re-invite
/// putting the row back to pending, is not an outcome and adds no tick.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_OUTCOME_TICK_CLEARING_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_outcome_clear',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('forward row outcome tick clearing', () {
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

    Future<void> seedRequest(String beaconId) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @authorId, 'Outcome tick', 'A Request forwarded to the viewer', 0)
'''),
        parameters: {'id': beaconId, 'authorId': _authorId},
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
            'edgeId': 'FE$beaconId$recipient',
            'beaconId': beaconId,
            'authorId': _authorId,
            'recipientId': recipient,
          },
        );
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
          parameters: {'u': recipient, 'b': beaconId, 'at': _forwardedAt},
        );
        await writer.execute(
          Sql.named('''
UPDATE public.attention_request_state
SET first_entry_at = CAST(@at AS timestamptz)
WHERE account_id = @u AND beacon_id = @b
'''),
          parameters: {'u': recipient, 'b': beaconId, 'at': _forwardedAt},
        );
      }
    }

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
      await seedRequest(_requestId);
    }

    setUp(resetFixture);

    Future<void> authorMoves(
      String beaconId,
      BeaconStatus from,
      BeaconStatus to,
      String reason,
    ) => database.withMutatingUser(
      _authorId,
      () => beacons.recordBeaconStatusTransition(
        beaconId: beaconId,
        fromStatus: from,
        toStatus: to,
        reason: reason,
        actorId: _authorId,
      ),
    );

    /// Closed before the viewer answered: every pending recipient's row
    /// becomes `closedBeforeResponse` (inbox status 3).
    Future<void> authorCloses([String beaconId = _requestId]) => authorMoves(
      beaconId,
      BeaconStatus.open,
      BeaconStatus.closed,
      BeaconLifecycleChangeReason.directClose,
    );

    /// The author opens the final check; the untouched forward rows read
    /// `closedBeforeResponse` until the author reopens from review.
    Future<void> authorOpensFinalCheck() => authorMoves(
      _requestId,
      BeaconStatus.open,
      BeaconStatus.reviewOpen,
      BeaconLifecycleChangeReason.closureOpened,
    );

    /// m0246 path: review → open reverts the 3 tombstone to 0.
    Future<void> authorReopensFromReview() => authorMoves(
      _requestId,
      BeaconStatus.reviewOpen,
      BeaconStatus.open,
      BeaconLifecycleChangeReason.reopenedFromReview,
    );

    Future<void> viewerAnswers(int status) => database.withMutatingUser(
      _viewerId,
      () => inbox.setStatus(
        userId: _viewerId,
        beaconId: _requestId,
        status: status,
        rejectionMessage: '',
      ),
    );

    /// The author's forward path writing the recipient's row back to pending
    /// (`status = 0`) with an upsert, as a re-forward does.
    Future<void> authorReforwardUpsert() => database.withMutatingUser(
      _authorId,
      () => database.customStatement('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (
  '$_viewerId', '$_requestId', 0, 2, now(), '', ''
)
ON CONFLICT (user_id, beacon_id) DO UPDATE SET
  status = 0,
  forward_count = public.inbox_item.forward_count + 1,
  latest_forward_at = EXCLUDED.latest_forward_at
'''),
    );

    Future<void> viewerMarksSeen(List<String> ids) =>
        ack.markSeen(accountId: _viewerId, ids: ids);

    Future<AttentionReceipt> forwardRow(
      String beaconId, {
      String viewer = _viewerId,
    }) async {
      final feed = await stream.attentionFeed(
        accountId: viewer,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final rows = feed.page.items
          .where((item) => item.id == 'inbox:$beaconId')
          .toList();
      expect(rows, hasLength(1), reason: 'one forward row for $beaconId');
      return rows.single;
    }

    Future<_OutcomeMarker> outcomeMarker(
      String userId, [
      String beaconId = _requestId,
    ]) async {
      final rows = await writer.execute(
        Sql.named('''
SELECT outcome_changed_at, outcome_changed_by, outcome_seen_at, status
FROM public.inbox_item
WHERE user_id = @u AND beacon_id = @b
'''),
        parameters: {'u': userId, 'b': beaconId},
      );
      final row = rows.single;
      return _OutcomeMarker(
        changedAt: (row[0] as DateTime?)?.toUtc(),
        changedBy: row[1] as String?,
        seenAt: (row[2] as DateTime?)?.toUtc(),
        status: row[3]! as int,
      );
    }

    // --- «Read all» ---------------------------------------------------------

    test(
      'Read all clears the forward outcome tick and the row stays seen and in '
      'place after a reload',
      () async {
        await authorCloses();
        final before = await forwardRow(_requestId);
        expect(before.seenAt, isNull, reason: 'precondition: the row ticks');

        await ack.markAllSeen(_viewerId);

        final marker = await outcomeMarker(_viewerId);
        expect(marker.seenAt, isNotNull, reason: 'outcome_seen_at is written');
        final after = await forwardRow(_requestId);
        expect(after.seenAt, isNotNull, reason: 'the tick is gone on reload');
        expect(
          after.createdAt.toUtc().isAtSameMomentAs(before.createdAt.toUtc()),
          isTrue,
          reason: 'clearing the tick does not move the row',
        );
      },
    );

    test(
      'Read all on the Activity surface clears the forward outcome tick',
      () async {
        await authorCloses();

        await ack.markAllSeen(_viewerId, surface: AttentionSurface.activity);

        expect((await outcomeMarker(_viewerId)).seenAt, isNotNull);
        expect((await forwardRow(_requestId)).seenAt, isNotNull);
      },
    );

    test(
      'Read all on the My Work surface leaves the forward outcome tick alone',
      () async {
        await authorCloses();

        await ack.markAllSeen(_viewerId, surface: AttentionSurface.myWork);

        expect((await outcomeMarker(_viewerId)).seenAt, isNull);
        expect((await forwardRow(_requestId)).seenAt, isNull);
      },
    );

    test(
      "Read all by one recipient leaves another recipient's tick unseen",
      () async {
        await authorCloses();

        await ack.markAllSeen(_viewerId);

        expect((await outcomeMarker(_viewerId)).seenAt, isNotNull);
        expect((await outcomeMarker(_otherRecipientId)).seenAt, isNull);
        expect(
          (await forwardRow(_requestId, viewer: _otherRecipientId)).seenAt,
          isNull,
        );
      },
    );

    // --- opening the Request elsewhere --------------------------------------

    test(
      'opening a Request clears its forward outcome tick and a reload shows '
      'the row seen',
      () async {
        await authorCloses();

        await ack.markSeenForBeacon(accountId: _viewerId, beaconId: _requestId);

        expect((await outcomeMarker(_viewerId)).seenAt, isNotNull);
        expect((await forwardRow(_requestId)).seenAt, isNotNull);
      },
    );

    test(
      'opening a Request leaves the tick on another Request and on another '
      "recipient's row untouched",
      () async {
        await seedRequest(_otherRequestId);
        await authorCloses();
        await authorCloses(_otherRequestId);

        await ack.markSeenForBeacon(accountId: _viewerId, beaconId: _requestId);

        expect((await outcomeMarker(_viewerId)).seenAt, isNotNull);
        expect(
          (await outcomeMarker(_viewerId, _otherRequestId)).seenAt,
          isNull,
          reason: 'a different Request keeps its tick',
        );
        expect(
          (await outcomeMarker(_otherRecipientId)).seenAt,
          isNull,
          reason: "another recipient's tick on the same Request stays",
        );
        expect((await forwardRow(_otherRequestId)).seenAt, isNull);
      },
    );

    // --- only a move INTO an outcome ticks ---------------------------------

    test(
      'reopening a Request from review adds no tick to a forward row the '
      'viewer already saw',
      () async {
        await authorOpensFinalCheck();
        expect((await outcomeMarker(_viewerId)).status, 3);
        await viewerMarksSeen(['inbox:$_requestId']);
        final before = await outcomeMarker(_viewerId);
        expect(before.changedAt, isNotNull);

        await authorReopensFromReview();

        final after = await outcomeMarker(_viewerId);
        expect(after.status, 0, reason: 'the row is pending again');
        expect(after.changedAt, before.changedAt);
        expect(after.changedBy, before.changedBy);
        // A pending row is no outcome row in the stream; what must hold is
        // that the earlier outcome is still seen.
        final stillSeen = await outcomeMarker(_viewerId);
        expect(stillSeen.changedAt!.isAfter(stillSeen.seenAt!), isFalse);
      },
    );

    test(
      'a re-invite putting a watching row back to pending by another user '
      'adds no tick and records no change',
      () async {
        await database.withMutatingUser(
          _viewerId,
          () => inbox.setStatus(
            userId: _viewerId,
            beaconId: _requestId,
            status: 1,
            rejectionMessage: '',
          ),
        );
        final before = await outcomeMarker(_viewerId);
        expect(before.changedBy, _viewerId);

        await database.withMutatingUser(
          _authorId,
          () => inbox.repinForAuthorInvite(
            userId: _viewerId,
            beaconId: _requestId,
          ),
        );

        final after = await outcomeMarker(_viewerId);
        expect(after.status, 0, reason: 'precondition: back to pending');
        expect(after.changedAt, before.changedAt);
        expect(after.changedBy, _viewerId);
      },
    );

    for (final (status, word) in [(1, 'watching'), (2, 'notInterested')]) {
      test(
        "the viewer's own answer «$word» is recorded as theirs and never "
        'reads as unseen',
        () async {
          await viewerAnswers(status);

          final marker = await outcomeMarker(_viewerId);
          expect(marker.status, status);
          expect(marker.changedBy, _viewerId);
          expect(marker.changedAt, isNotNull);
          final row = await forwardRow(_requestId);
          expect(row.forwardOutcome, word);
          expect(row.seenAt, isNotNull, reason: 'no unread tick');

          // Read all and opening the Request leave it untouched and unticked.
          await ack.markAllSeen(_viewerId);
          await ack.markSeenForBeacon(
            accountId: _viewerId,
            beaconId: _requestId,
          );
          expect((await outcomeMarker(_viewerId)).changedBy, _viewerId);
          expect((await forwardRow(_requestId)).seenAt, isNotNull);
        },
      );
    }

    test(
      'a re-forward upsert by another user putting a watching row back to '
      'pending adds no tick and records no change',
      () async {
        await viewerAnswers(1);
        final before = await outcomeMarker(_viewerId);
        expect(before.changedBy, _viewerId);

        await authorReforwardUpsert();

        final after = await outcomeMarker(_viewerId);
        expect(after.status, 0, reason: 'precondition: back to pending');
        expect(after.changedAt, before.changedAt);
        expect(after.changedBy, _viewerId);
      },
    );

    test(
      'a Request closed directly, seen, then reopened through review adds no '
      'tick on the reopen and ticks when closed again',
      () async {
        await authorCloses();
        expect((await outcomeMarker(_viewerId)).status, 3);
        await viewerMarksSeen(['inbox:$_requestId']);
        final seen = await outcomeMarker(_viewerId);
        expect(seen.seenAt, isNotNull);

        await authorMoves(
          _requestId,
          BeaconStatus.closed,
          BeaconStatus.reviewOpen,
          BeaconLifecycleChangeReason.closureOpened,
        );
        await authorReopensFromReview();

        final reopened = await outcomeMarker(_viewerId);
        expect(reopened.status, 0, reason: 'the reopen put the row to pending');
        expect(reopened.changedAt, seen.changedAt);
        expect(reopened.changedBy, seen.changedBy);
        // A pending row is no outcome row in the stream; what must hold is
        // that the earlier outcome is still seen.
        final stillSeen = await outcomeMarker(_viewerId);
        expect(stillSeen.changedAt!.isAfter(stillSeen.seenAt!), isFalse);

        await authorCloses();

        final marker = await outcomeMarker(_viewerId);
        expect(marker.status, 3);
        expect(marker.changedAt!.isAfter(marker.seenAt!), isTrue);
        expect((await forwardRow(_requestId)).seenAt, isNull);
      },
    );

    test(
      'closing the Request again after a reopen ticks the seen row again',
      () async {
        await authorOpensFinalCheck();
        await viewerMarksSeen(['inbox:$_requestId']);
        await authorReopensFromReview();
        final seen = await outcomeMarker(_viewerId);
        expect(seen.seenAt, isNotNull);
        expect(seen.status, 0, reason: 'precondition: reopened to pending');

        await authorCloses();

        final marker = await outcomeMarker(_viewerId);
        expect(marker.status, 3);
        expect(marker.changedBy, _authorId);
        expect(marker.changedAt!.isAfter(marker.seenAt!), isTrue);
        final row = await forwardRow(_requestId);
        expect(row.forwardOutcome, 'closedBeforeResponse');
        expect(row.seenAt, isNull, reason: 'a move into an outcome ticks');
      },
    );
  }, skip: skipReason);
}

final class _OutcomeMarker {
  const _OutcomeMarker({
    required this.changedAt,
    required this.changedBy,
    required this.seenAt,
    required this.status,
  });

  final DateTime? changedAt;
  final String? changedBy;
  final DateTime? seenAt;
  final int status;
}

const _viewerId = 'Uclrtick01';
const _authorId = 'Uclrtick02';
const _otherRecipientId = 'Uclrtick03';
const _requestId = 'Bclrtickreq';
const _otherRequestId = 'Bclrtickrq2';
const _forwardedAt = '2026-08-01T10:00:00Z';
