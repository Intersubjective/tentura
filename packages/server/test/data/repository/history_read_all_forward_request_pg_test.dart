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
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

/// History is the account-wide notification feed. «Read all» must leave every
/// item in it read, a forwarded Request's included, and the unread count 0,
/// on the first fetch and on every later one.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HISTORY_READ_ALL_FORWARD_TEST_DB',
    defaultNamePrefix: 'tentura_test_hist_readall_fwd',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('History «Read all» with a forwarded Request', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository feedRepo;
    late AttentionAckRepository ack;
    late BeaconRepository beacons;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      feedRepo = AttentionRepository(database);
      ack = AttentionAckRepository(database);
      beacons = BeaconRepository(database);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> seedRequest(String beaconId) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @authorId, 'Forwarded', 'A Request forwarded to the viewer', 0)
'''),
        parameters: {'id': beaconId, 'authorId': _authorId},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (@edgeId, @beaconId, @authorId, @viewerId, now(), NULL)
'''),
        parameters: {
          'edgeId': 'FE$beaconId',
          'beaconId': beaconId,
          'authorId': _authorId,
          'viewerId': _viewerId,
        },
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@u, @b, 0, 1, CAST(@at AS timestamptz), '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET
  status = 0, forward_count = 1,
  latest_forward_at = EXCLUDED.latest_forward_at
'''),
        parameters: {'u': _viewerId, 'b': beaconId, 'at': _forwardedAt},
      );
      await writer.execute(
        Sql.named('''
UPDATE public.attention_request_state
SET first_entry_at = CAST(@at AS timestamptz)
WHERE account_id = @u AND beacon_id = @b
'''),
        parameters: {'u': _viewerId, 'b': beaconId, 'at': _forwardedAt},
      );
    }

    /// The forward shell receipt the relay producer writes for the recipient.
    Future<void> seedRelayReceipt(String beaconId, {bool seen = false}) =>
        writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  beacon_id, actor_user_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @viewer, 'requestProgress', 'newRelay', 'low',
  'Author', 'Author: note', '/#/view?id=' || @b, @dedup,
  CAST(@at AS timestamptz),
  CASE WHEN @seen THEN CAST(@at AS timestamptz) END,
  @b, @author, @source,
  'beacon', 'relay_received',
  '{"eventType":"relayReceived","personal":true}'::jsonb,
  'standard', 'beacon_content'
)
'''),
          parameters: {
            'id': 'Nrelay$beaconId',
            'viewer': _viewerId,
            'author': _authorId,
            'b': beaconId,
            'dedup': 'dedup-relay-$beaconId',
            'source': 'relayReceived:$beaconId:$_viewerId',
            'at': _forwardedAt,
            'seen': seen,
          },
        );

    Future<void> seedOptionalReceipt(String id) => writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @viewer, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedup, CAST(@at AS timestamptz),
  @b, @source,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content'
)
'''),
      parameters: {
        'id': id,
        'viewer': _viewerId,
        'dedup': 'dedup-$id',
        'source': 'source-$id',
        'at': '2026-08-01T11:00:00Z',
        'b': _requestId,
      },
    );

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
      for (final id in [_viewerId, _authorId]) {
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

    Future<void> authorMoves(BeaconStatus from, BeaconStatus to, String why) =>
        database.withMutatingUser(
          _authorId,
          () => beacons.recordBeaconStatusTransition(
            beaconId: _requestId,
            fromStatus: from,
            toStatus: to,
            reason: why,
            actorId: _authorId,
          ),
        );

    Future<void> authorCloses() => authorMoves(
      BeaconStatus.open,
      BeaconStatus.closed,
      BeaconLifecycleChangeReason.directClose,
    );

    /// History as the notification screen fetches it: every surface.
    Future<AttentionFeed> history([AttentionRepository? repo]) =>
        (repo ?? feedRepo).attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.all,
        );

    /// The Activity stream, where the synthetic forward row lives.
    Future<AttentionFeed> activity([AttentionRepository? repo]) =>
        (repo ?? feedRepo).attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.all,
          surface: AttentionSurface.activity,
        );

    /// A reload: a new database handle (new connection pool), as a new
    /// request after a page reload would use.
    Future<void> withFreshConnection(
      Future<void> Function(AttentionRepository repo) body,
    ) async {
      final fresh = openDisposablePgDatabase(target);
      try {
        await body(AttentionRepository(fresh));
      } finally {
        await fresh.close();
      }
    }

    AttentionReceipt forwardRowOf(AttentionFeed feed) {
      final rows = feed.page.items
          .where((i) => i.itemKind == AttentionItemKind.forward)
          .toList();
      expect(rows, hasLength(1), reason: 'one forward row in the feed');
      return rows.single;
    }

    void expectHistoryRead(
      AttentionFeed feed, {
      required String reason,
      bool forwardReceiptListed = true,
    }) {
      final relay = feed.page.items.where(
        (i) => i.presentationKey == 'relay_received',
      );
      if (forwardReceiptListed) {
        expect(relay, isNotEmpty, reason: '$reason: forward receipt present');
      }
      expect(
        [
          for (final item in feed.page.items)
            if (item.seenAt == null) item.id,
        ],
        isEmpty,
        reason: '$reason: every History item is read',
      );
      expect(feed.summary.unreadTotal, 0, reason: '$reason: unread count');
    }

    /// Everything the viewer can see after Read all, on a fresh connection.
    Future<void> expectEverythingReadAfterReload(
      String reason, {
      bool forwardReceiptListed = true,
    }) => withFreshConnection((repo) async {
      expect(
        forwardRowOf(await activity(repo)).seenAt,
        isNotNull,
        reason: '$reason: forward row read',
      );
      expectHistoryRead(
        await history(repo),
        reason: reason,
        forwardReceiptListed: forwardReceiptListed,
      );
    });

    /// Somebody other than the viewer relabels the forward row.
    Future<void> authorRelabels(int status) => database.withMutatingUser(
      _authorId,
      () => database.customStatement(
        'UPDATE public.inbox_item SET status = $status '
        "WHERE user_id = '$_viewerId' AND beacon_id = '$_requestId'",
      ),
    );

    /// A change with no actor: the Request's lifecycle writing the row, with
    /// no mutating user in the session (`outcome_changed_by` stays NULL).
    Future<void> systemMoves(BeaconStatus from, BeaconStatus to, String why) =>
        beacons.recordBeaconStatusTransition(
          beaconId: _requestId,
          fromStatus: from,
          toStatus: to,
          reason: why,
          actorId: null,
        );

    Future<void> systemCloses() => systemMoves(
      BeaconStatus.open,
      BeaconStatus.closed,
      BeaconLifecycleChangeReason.directClose,
    );

    Future<void> systemDeletes() async {
      await systemCloses();
      await systemMoves(
        BeaconStatus.closed,
        BeaconStatus.deleted,
        BeaconLifecycleChangeReason.deleted,
      );
    }

    Future<void> viewerOffersHelp() => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (@b, @u, 'offer', 0, now(), now())
'''),
      parameters: {'b': _requestId, 'u': _viewerId},
    );

    group('When the author closes an already-read forward', () {
      Future<AttentionFeed> historyUnread(AttentionRepository repo) =>
          repo.attentionFeed(
            accountId: _viewerId,
            view: AttentionFeedView.unread,
          );

      setUp(() async {
        await seedRelayReceipt(_requestId);
        await ack.markAllSeen(_viewerId);
        final pending = await feedRepo.activityOffers(
          accountId: _viewerId,
          beaconId: _requestId,
        );
        // An open, unanswered forward is pinned in Activity. If the stream
        // also projects it, that projection must agree that it was read.
        expect(pending.items.single.beaconId, _requestId);
        expect(pending.items.single.unseen, isFalse);
        final stream = await activity();
        expect(
          stream.page.items.where(
            (item) =>
                item.beaconId == _requestId &&
                item.itemKind == AttentionItemKind.forward &&
                item.seenAt == null,
          ),
          isEmpty,
          reason: 'Activity has no unread forward before the author closes it',
        );
        expect((await history()).summary.unreadTotal, 0);

        await authorCloses();

        final row = forwardRowOf(await activity());
        expect(row.forwardOutcome, 'closedBeforeResponse');
        expect(row.seenAt, isNull);
      });

      void expectUnreadClosure(AttentionFeed feed) {
        expect(
          feed.page.items.where(
            (item) => item.beaconId == _requestId && item.seenAt == null,
          ),
          isNotEmpty,
          reason: 'History lists an unread item for the newly closed Request',
        );
      }

      test(
        'History All lists and counts the closure until Read all clears it',
        () async {
          final before = await history();
          await ack.markAllSeen(_viewerId);

          Future<void> expectRead(AttentionRepository repo) async {
            final activityFeed = await activity(repo);
            expect(forwardRowOf(activityFeed).seenAt, isNotNull);
            expect(activityFeed.summary.unreadTotal, 0);
            final historyFeed = await history(repo);
            expect(
              historyFeed.page.items.map((item) => item.seenAt),
              everyElement(isNotNull),
            );
            expect(historyFeed.summary.unreadTotal, 0);
            expect((await historyUnread(repo)).page.items, isEmpty);
          }

          await expectRead(feedRepo);
          await withFreshConnection(expectRead);

          expectUnreadClosure(before);
          expect(before.summary.unreadTotal, greaterThanOrEqualTo(1));
        },
      );

      test(
        'History Unread lists the closure and Activity Read all clears its dot',
        () async {
          final before = await historyUnread(feedRepo);
          await ack.markAllSeen(_viewerId, surface: AttentionSurface.activity);

          Future<void> expectRead(AttentionRepository repo) async {
            final feed = await activity(repo);
            expect(forwardRowOf(feed).seenAt, isNotNull);
            expect(feed.summary.unreadTotal, 0);
          }

          await expectRead(feedRepo);
          await withFreshConnection(expectRead);

          expectUnreadClosure(before);
        },
      );
    });

    test(
      'Read all leaves the unread forward row and the unread ordinary receipt '
      'read, and a reload on a new connection still shows them read',
      () async {
        await authorCloses();
        await seedRelayReceipt(_requestId);
        await seedOptionalReceipt('Nplain01');
        expect(
          forwardRowOf(await activity()).seenAt,
          isNull,
          reason: 'precondition: the forward row ticks',
        );
        expect(
          (await history()).summary.unreadTotal,
          2,
          reason: 'precondition: forward receipt + ordinary receipt',
        );

        await ack.markAllSeen(_viewerId);

        expectHistoryRead(await history(), reason: 'after Read all');
        await expectEverythingReadAfterReload('after reload');
      },
    );

    test(
      'Read all on the Activity surface leaves the forward row read and the '
      'unread count 0 after a reload',
      () async {
        await authorCloses();
        await seedRelayReceipt(_requestId);
        expect(forwardRowOf(await activity()).seenAt, isNull);
        expect((await activity()).summary.unreadTotal, greaterThan(0));

        await ack.markAllSeen(_viewerId, surface: AttentionSurface.activity);

        expectHistoryRead(await activity(), reason: 'activity feed');
        await expectEverythingReadAfterReload('after reload');
      },
    );

    test(
      'the forward receipt of a Request the viewer has not answered gets '
      'seen_at on Read all and reads as seen in History',
      () async {
        await seedRelayReceipt(_requestId);

        await ack.markAllSeen(_viewerId);

        final rows = await writer.execute(
          Sql.named('''
SELECT seen_at FROM public.notification_outbox
WHERE account_id = @u AND presentation_key = 'relay_received'
'''),
          parameters: {'u': _viewerId},
        );
        expect(rows.single[0], isNotNull, reason: 'seen_at is set');
        expectHistoryRead(await history(), reason: 'after Read all');
      },
    );

    final outcomes = <(String, Future<void> Function())>[
      ('watching', () => authorRelabels(1)),
      ('notInterested', () => authorRelabels(2)),
      (
        'helping',
        () async {
          // The help offer alone makes the row read `helping` (the outcome
          // comes from the offer, not from the status); the author's relabel
          // is only the unread tick.
          await viewerOffersHelp();
          expect(
            forwardRowOf(await activity()).forwardOutcome,
            'helping',
            reason: 'precondition: the help offer yields helping',
          );
          await authorRelabels(1);
        },
      ),
      ('closedBeforeResponse', systemCloses),
      ('deletedBeforeResponse', systemDeletes),
    ];
    for (final (outcome, relabel) in outcomes) {
      test(
        'a forward row relabelled to $outcome by someone else is read after '
        'Read all and stays read on a reload',
        () async {
          await relabel();
          await seedRelayReceipt(_requestId);
          final before = forwardRowOf(await activity());
          expect(before.forwardOutcome, outcome, reason: 'precondition');
          expect(before.seenAt, isNull, reason: 'precondition: it ticks');

          await ack.markAllSeen(_viewerId);

          // A deleted Request's receipt is no longer readable, so History
          // has nothing to list for it; the rest must still be read.
          await expectEverythingReadAfterReload(
            outcome,
            forwardReceiptListed: outcome != 'deletedBeforeResponse',
          );
        },
      );
    }

    test(
      'Read all marks only what exists when it runs: another change to the '
      'same forwarded Request afterwards makes the forward row unread again',
      () async {
        await authorCloses();
        await seedRelayReceipt(_requestId);
        await ack.markAllSeen(_viewerId);
        expect(forwardRowOf(await activity()).seenAt, isNotNull);

        await database.withMutatingUser(
          _authorId,
          () => beacons.recordBeaconStatusTransition(
            beaconId: _requestId,
            fromStatus: BeaconStatus.closed,
            toStatus: BeaconStatus.deleted,
            reason: BeaconLifecycleChangeReason.deleted,
            actorId: _authorId,
          ),
        );

        final row = forwardRowOf(await activity());
        expect(row.forwardOutcome, 'deletedBeforeResponse');
        expect(row.seenAt, isNull, reason: 'a new relabel is a new tick');
      },
    );

    test(
      'Read all marks only what exists when it runs: a receipt arriving '
      'afterwards is unread',
      () async {
        await seedRelayReceipt(_requestId);
        await ack.markAllSeen(_viewerId);
        expectHistoryRead(await history(), reason: 'after Read all');

        await seedOptionalReceipt('Nlater01');

        final feed = await history();
        expect(feed.summary.unreadTotal, 1);
        expect(
          [
            for (final i in feed.page.items)
              if (i.seenAt == null) i.id,
          ],
          ['Nlater01'],
        );
      },
    );
  }, skip: skipReason);
}

const _viewerId = 'Uhistrdall1';
const _authorId = 'Uhistrdall2';
const _requestId = 'Bhistrdallrq';
const _forwardedAt = '2026-08-01T10:00:00Z';
