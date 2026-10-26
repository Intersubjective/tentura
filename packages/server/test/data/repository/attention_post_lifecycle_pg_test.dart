@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';

const _author = 'Uattnttl01';
const _member = 'Uattnttl02';
const _post = 'Battnttl01';
const _request = 'Battnttl02';
const _warningKey = 'post_expiring:$_post';
const _replyKey = 'reply:$_post';
const _requestKey = 'reply:$_request';

/// Expiry is a read-time eligibility rule, shared by the grouped row, its
/// children, counts, dot and dismiss-all capture. It never deletes history.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_POST_LIFECYCLE_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_post_ttl',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late AttentionRepository query;
  late TransactionalAttentionCase attention;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    query = AttentionRepository(database);
    attention = TransactionalAttentionCase(
      MutatingUnitOfWork(database),
      AttentionDispatchRepository(database, Logger('PostLifecyclePgTest')),
    );
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<void> record(AttentionDispatchIntent intent) =>
      attention.runAction<void>(
        actorUserId: intent.actorUserId,
        action: (tx) => tx.record(intent),
      );

  Future<void> seedFixture() async {
    await writer.execute('''
TRUNCATE public.attention_occurrence, public.notification_outbox,
  public.beacon, public."user" CASCADE
''');
    for (final id in [_author, _member]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
    }
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, published_at,
   expires_at, expiry_warning_eligible, is_discoverable)
VALUES ('$_post', '$_author', '', '', 1, 0, now(),
        now() + interval '2 hours', true, false)
''');
    await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pattnttl01', '$_post', '$_member', 6, 0, 3)
''');
    // Real dispatch persists occurrences, recipients and receipts. The two
    // event types deliberately include the expiry warning: it has no exemption.
    await record(
      _intent(
        beaconId: _post,
        sourceKey: _warningKey,
        warning: true,
      ),
    );
    await record(_intent(beaconId: _post, sourceKey: _replyKey));
  }

  setUp(seedFixture);

  Future<void> expire() => writer.execute('''
UPDATE public.beacon SET expires_at = now() - interval '1 minute'
WHERE id = '$_post'
''');

  // S13 owns the read projection and depends on S1/S12, not the S9 worker.
  // Seed the persisted status produced by the expiry sweep; do not implement
  // or substitute for the worker in this projection fixture.
  Future<void> closeExpired() => writer.execute('''
UPDATE public.beacon SET status = 6 WHERE id = '$_post'
''');

  Future<Map<String, Object?>> projection({String beaconId = _post}) async {
    final feed = await query.attentionFeed(
      accountId: _author,
      view: AttentionFeedView.all,
      surface: AttentionSurface.activity,
    );
    final expanded = await query.activityAttention(
      accountId: _author,
      beaconId: beaconId,
    );
    final summary = await query.surfaceSummary(accountId: _author);
    final unread = await query.unreadForBeacons(
      accountId: _author,
      beaconIds: {beaconId},
    );
    return {
      'rows': [
        for (final row in feed.page.items)
          if (row.beaconId == beaconId)
            {
              'kind': row.itemKind.name,
              'total': row.eventTotal,
              'unseen': row.eventUnseenCount,
              'preview': row.eventsPreview.map((e) => e.sourceEventKey).toSet(),
            },
      ],
      'feedCount': feed.summary.unreadTotal,
      'expandedCount': expanded.eventTotal,
      'expandedUnseen': expanded.unseenCount,
      'expandedEvents': expanded.events.map((e) => e.sourceEventKey).toSet(),
      'unreadBeacons': unread,
      'dot': summary.forYouDot,
      'dismissAllEnabled': summary.forYouSweepEligible,
    };
  }

  Future<void> expectActivePost() async {
    expect(await projection(), {
      'rows': [
        {
          'kind': 'requestActivity',
          'total': 2,
          'unseen': 2,
          'preview': {_warningKey, _replyKey},
        },
      ],
      'feedCount': 2,
      'expandedCount': 2,
      'expandedUnseen': 2,
      'expandedEvents': {_warningKey, _replyKey},
      'unreadBeacons': {_post},
      'dot': true,
      'dismissAllEnabled': true,
    });
    final history = await query.attentionRequestHistory(
      accountId: _author,
      beaconId: _post,
    );
    expect(
      history.items.map((r) => r.presentationKey),
      unorderedEquals(['post_expiring_soon', 'room_message_posted']),
    );
  }

  const emptyProjection = {
    'rows': <Object?>[],
    'feedCount': 0,
    'expandedCount': 0,
    'expandedUnseen': 0,
    'expandedEvents': <String>{},
    'unreadBeacons': <String>{},
    'dot': false,
    'dismissAllEnabled': false,
  };

  group('For You Post lifecycle', () {
    test('expiry removes the warning and member reply from every projection '
        'before closure and keeps them absent after closure', () async {
      await expectActivePost();

      await expire();
      expect(
        (await writer.execute(
          "SELECT status FROM public.beacon WHERE id = '$_post'",
        )).single.single,
        0,
      );
      final expired = await projection();
      await closeExpired();
      final closed = await projection();
      final history = await query.attentionRequestHistory(
        accountId: _author,
        beaconId: _post,
      );

      expect(
        history.items.map((r) => r.sourceEventKey),
        unorderedEquals([_warningKey, _replyKey]),
        reason: 'the Post history remains readable after expiry and closure',
      );
      expect(
        {'expired while open': expired, 'closed after expiry': closed},
        {
          'expired while open': emptyProjection,
          'closed after expiry': emptyProjection,
        },
      );
    });

    test('Request receipts survive Post expiry and closure with their counts '
        'and unread dot intact', () async {
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, published_at)
VALUES ('$_request', '$_member', 'Request', '', 0, 0, now())
''');
      await writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id)
VALUES ('Fattnttl01', '$_request', '$_member', '$_author')
''');
      await writer.execute('''
UPDATE public.inbox_item SET status = 2
WHERE user_id = '$_author' AND beacon_id = '$_request'
''');
      await record(
        _intent(
          beaconId: _request,
          sourceKey: _requestKey,
          beaconKind: BeaconKind.request,
        ),
      );
      final before = await projection(beaconId: _request);
      expect(before['rows'], isNotEmpty);
      expect(before['expandedCount'], 1);
      expect(before['expandedUnseen'], 1);
      expect(before['expandedEvents'], {_requestKey});
      expect(before['unreadBeacons'], {_request});
      expect(before['dot'], isTrue);
      expect(before['dismissAllEnabled'], isTrue);
      expect(before['feedCount'], 3);
      final accountFeedBefore = await query.attentionFeed(
        accountId: _author,
        view: AttentionFeedView.all,
      );
      expect(accountFeedBefore.summary.unreadTotal, 3);

      // The feed total covers the whole account and must lose the two Post
      // receipts. Everything else here describes the Request or an indicator
      // that its unchanged unread receipt must keep on.
      Map<String, Object?> requestProjection(Map<String, Object?> state) => {
        for (final entry in state.entries)
          if (entry.key != 'feedCount') entry.key: entry.value,
      };

      await expire();
      final expiredPost = await projection();
      final expiredRequest = await projection(beaconId: _request);
      final accountFeedAfterExpiry = await query.attentionFeed(
        accountId: _author,
        view: AttentionFeedView.all,
      );
      await closeExpired();
      final closedPost = await projection();
      final request = await projection(beaconId: _request);
      final accountFeedAfterClosure = await query.attentionFeed(
        accountId: _author,
        view: AttentionFeedView.all,
      );

      expect(
        {
          'Request after Post expiry': requestProjection(expiredRequest),
          'Request after Post closure': requestProjection(request),
        },
        {
          'Request after Post expiry': requestProjection(before),
          'Request after Post closure': requestProjection(before),
        },
        reason:
            'Request rows, previews, counts and unread state are unchanged '
            'at each Post lifecycle transition',
      );
      expect(request['rows'], isNotEmpty);
      expect(request['expandedCount'], 1);
      expect(request['expandedUnseen'], 1);
      expect(request['expandedEvents'], {_requestKey});
      expect(
        {
          'account feed count after expiry':
              accountFeedAfterExpiry.summary.unreadTotal,
          'account feed count after closure':
              accountFeedAfterClosure.summary.unreadTotal,
        },
        {
          'account feed count after expiry': 1,
          'account feed count after closure': 1,
        },
        reason:
            'the unfiltered account feed still counts the Request receipt '
            'and excludes both Post receipts',
      );
      expect(
        {
          'feed count after expiry': expiredRequest['feedCount'],
          'feed count after closure': request['feedCount'],
        },
        {'feed count after expiry': 1, 'feed count after closure': 1},
        reason: 'only the Request receipt remains counted',
      );
      expect(request['unreadBeacons'], {_request});
      expect(request['dot'], isTrue);
      expect(
        {
          'expired Post rows': expiredPost['rows'],
          'expired Post children': expiredPost['expandedEvents'],
          'closed Post rows': closedPost['rows'],
          'closed Post children': closedPost['expandedEvents'],
        },
        {
          'expired Post rows': <Object?>[],
          'expired Post children': <String>{},
          'closed Post rows': <Object?>[],
          'closed Post children': <String>{},
        },
      );
    });

    test(
      'dismiss-all clears Post warnings and member replies before expiry '
      'and leaves them uncleared after expiry',
      () async {
        await expectActivePost();
        final eligibleReceipts = await writer.execute('''
SELECT id FROM public.notification_outbox
WHERE account_id = '$_author' AND beacon_id = '$_post'
''');
        expect(eligibleReceipts, hasLength(2));
        final cleared = await AttentionSweepRepository(database).dismissAll(
          accountId: _author,
          operationId: 'OPactivepost01',
        );
        expect(cleared.failed, isEmpty);
        expect(
          cleared.appliedReceiptIds,
          unorderedEquals(eligibleReceipts.map((row) => row.single! as String)),
        );
        final clearedReceipts = await writer.execute('''
SELECT cleared_at FROM public.notification_outbox
WHERE account_id = '$_author' AND beacon_id = '$_post'
''');
        expect(clearedReceipts, hasLength(2));
        expect(
          clearedReceipts.map((row) => row.single),
          everyElement(isNotNull),
        );
        expect(await projection(), emptyProjection);

        // Repeat with a fresh copy of the same fixture so the expired case
        // cannot pass merely because the eligible case already cleared it.
        await seedFixture();
        await expectActivePost();
        await expire();

        final result = await AttentionSweepRepository(database).dismissAll(
          accountId: _author,
          operationId: 'OPexpiredpost01',
        );

        expect(result.failed, isEmpty);
        expect(result.appliedReceiptIds, isEmpty);
        final receipts = await writer.execute('''
SELECT cleared_at FROM public.notification_outbox
WHERE account_id = '$_author' AND beacon_id = '$_post'
''');
        expect(receipts, hasLength(2));
        expect(receipts.map((row) => row.single), everyElement(isNull));
      },
    );
  });
}

AttentionDispatchIntent _intent({
  required String beaconId,
  required String sourceKey,
  bool warning = false,
  BeaconKind beaconKind = BeaconKind.post,
}) => AttentionDispatchIntent(
  eventType: warning
      ? AttentionEventType.postExpiringSoon
      : AttentionEventType.roomMessagePosted,
  sourceEventKey: sourceKey,
  actorUserId: warning ? null : _member,
  priority: warning ? NotificationPriority.high : NotificationPriority.normal,
  kind: warning
      ? NotificationKind.postExpiringSoon
      : NotificationKind.roomActivityLowPriority,
  title: warning ? 'Your post is about to expire' : 'Member reply',
  body: warning ? 'Your post expires in under 3 hours' : 'A member replied',
  actionUrl: '/#/beacon/$beaconId',
  collapseKey: AttentionCollapseKey.none(sourceKey),
  beaconId: beaconId,
  beaconKind: beaconKind,
  recipients: [
    AttentionRecipientSnapshot(
      recipientId: _author,
      reasons: warning
          ? const {AttentionRecipientReason.postAuthor}
          : const {AttentionRecipientReason.directedChatTarget},
      role: AttentionRecipientRoleFacts(
        beaconId: beaconId,
        actorUserId: warning ? null : _member,
        canReadBeaconContent: true,
        excerpt: warning ? null : 'A member replied',
      ),
    ),
  ],
);
