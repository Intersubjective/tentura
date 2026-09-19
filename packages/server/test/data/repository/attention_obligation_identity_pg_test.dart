@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

import '../../support/disposable_pg_target.dart';

/// U05c — obligation identity: `logical_task_key` + `lifecycle_generation`.
///
/// The unit is the distinction between two things that look alike from the
/// dispatch side and are not:
///
/// * a **semantic renewal** — the same unresolved task asked again (a helper
///   withdraws and offers anew; a review window is reopened). It supersedes
///   its predecessor *in the same transaction*, so the two generations never
///   coexist as live obligations.
/// * a **delivery retry** — the same event handed to the channel worker
///   again, or the same `source_event_key` replayed. It must bump nothing and
///   supersede nothing.
///
/// Both directions are asserted. A suite that only proved the renewal path
/// would stay green while every retry silently inflated a generation counter.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U05C_OBLIGATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_u05c_obligation',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attention obligation identity', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionDispatchRepository dispatch;
    late AttentionChannelDeliveryRepository delivery;
    late MutatingUnitOfWork unitOfWork;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      dispatch = AttentionDispatchRepository(
        database,
        Logger('attention-obligation-identity-test'),
      );
      delivery = AttentionChannelDeliveryRepository(database);
      unitOfWork = MutatingUnitOfWork(database);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() async {
      await _resetFixtures(writer);
    });

    test('an obligation receipt carries its logical task and generation 1',
        () async {
      await _record(unitOfWork, dispatch, _helpOffer(sourceEventKey: 'offer-1'));

      final rows = await _obligations(writer);
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['account_id'], _authorId);
      expect(
        row['logical_task_key'],
        'v1|helpOfferSubmitted|$_beaconId|$_helperId|$_authorId',
        reason: 'event family + beaconId + subjectId + recipientId (D03); the '
            'subject of an author obligation is the helper, so withdrawing '
            'and offering again is the same logical task',
      );
      expect(row['lifecycle_generation'], 1);
      expect(row['settlement_kind'], isNull);
    });

    test('an optional receipt carries neither column', () async {
      await _record(unitOfWork, dispatch, _relay(sourceEventKey: 'relay-1'));

      final rows = await writer.execute('''
SELECT logical_task_key, lifecycle_generation, requires_action
FROM public.notification_outbox
''');
      expect(rows, hasLength(1));
      expect(rows.single[0], isNull);
      expect(rows.single[1], isNull);
      expect(rows.single[2], false);
    });

    test('the same helper on two Requests holds two distinct live tasks',
        () async {
      await _record(unitOfWork, dispatch, _helpOffer(sourceEventKey: 'offer-a'));
      await _record(
        unitOfWork,
        dispatch,
        _helpOffer(sourceEventKey: 'offer-b', beaconId: _otherBeaconId),
      );

      final rows = await _obligations(writer);
      expect(rows, hasLength(2));
      expect(
        rows.map((row) => row['logical_task_key']).toSet(),
        hasLength(2),
        reason: 'D03: the Request is part of the key',
      );
      expect(rows.map((row) => row['lifecycle_generation']).toSet(), {1});
    });

    test('a semantic renewal supersedes its predecessor and bumps to 2',
        () async {
      await _record(unitOfWork, dispatch, _helpOffer(sourceEventKey: 'offer-1'));
      final first = (await _obligations(writer)).single;

      // Withdraw / re-offer: a new occurrence for the same unresolved task.
      await _record(unitOfWork, dispatch, _helpOffer(sourceEventKey: 'offer-2'));

      final live = await _liveObligations(writer);
      expect(
        live,
        hasLength(1),
        reason: 'at most one live obligation per (account_id, logical_task_key)',
      );
      expect(live.single['lifecycle_generation'], 2);
      expect(live.single['logical_task_key'], first['logical_task_key']);
      expect(live.single['id'], isNot(first['id']));

      final superseded = (await _obligations(writer))
          .firstWhere((row) => row['id'] == first['id']);
      expect(superseded['settlement_kind'], 'superseded');
      expect(superseded['settled_at'], isNotNull);
      expect(
        superseded['lifecycle_generation'],
        1,
        reason: 'the predecessor keeps the generation it was written with',
      );
    });

    test('a reopened review window is a new generation of one review task',
        () async {
      await _record(
        unitOfWork,
        dispatch,
        _reviewOpened(sourceEventKey: 'review-1'),
      );
      await _record(
        unitOfWork,
        dispatch,
        _reviewOpened(sourceEventKey: 'review-2'),
      );

      final live = await _liveObligations(writer);
      expect(live, hasLength(1));
      expect(
        live.single['logical_task_key'],
        'v1|reviewOpened|$_beaconId|$_beaconId|$_reviewerId',
        reason: 'the subject of a review obligation is the Request itself; '
            'generations distinguish review windows',
      );
      expect(live.single['lifecycle_generation'], 2);
    });

    test('replaying one source_event_key does not bump the generation',
        () async {
      for (var i = 0; i < 3; i++) {
        await _record(
          unitOfWork,
          dispatch,
          _helpOffer(sourceEventKey: 'offer-1'),
        );
      }

      final rows = await _obligations(writer);
      expect(rows, hasLength(1), reason: 'replay is deduped at the occurrence');
      expect(rows.single['lifecycle_generation'], 1);
      expect(rows.single['settlement_kind'], isNull);
    });

    test('a channel delivery retry bumps and supersedes nothing', () async {
      await _record(unitOfWork, dispatch, _helpOffer(sourceEventKey: 'offer-1'));
      final before = (await _obligations(writer)).single;

      final now = DateTime.now().toUtc();
      final claimed = await delivery.claimDue(
        workerId: 'u05c-worker',
        now: now,
        limit: 10,
      );
      expect(claimed, hasLength(1));
      await delivery.retryOrDeadLetter(
        id: claimed.single.id,
        workerId: 'u05c-worker',
        now: now,
        error: StateError('transient push failure'),
      );

      final after = await _obligations(writer);
      expect(after, hasLength(1));
      expect(
        after.single,
        before,
        reason: 'a retry is not a renewal: no column of the obligation moves',
      );
      final jobs = await writer.execute('''
SELECT status FROM public.attention_channel_delivery
''');
      expect(jobs.single[0], 'pending');
    });

    test(
      'a second live obligation for one logical task is rejected by '
      'notification_outbox__live_logical_task',
      () async {
        await _record(
          unitOfWork,
          dispatch,
          _helpOffer(sourceEventKey: 'offer-a'),
        );
        await _record(
          unitOfWork,
          dispatch,
          _helpOffer(sourceEventKey: 'offer-b', beaconId: _otherBeaconId),
        );
        final rows = await _obligations(writer);
        final target = rows.firstWhere((row) => row['beacon_id'] == _beaconId);
        final rival = rows.firstWhere(
          (row) => row['beacon_id'] == _otherBeaconId,
        );

        await expectLater(
          writer.execute(
            Sql.named('''
UPDATE public.notification_outbox
SET logical_task_key = @key
WHERE id = @id
'''),
            parameters: {
              'key': target['logical_task_key'],
              'id': rival['id'],
            },
          ),
          throwsA(
            isA<ServerException>().having(
              (error) => error.constraintName,
              'constraintName',
              'notification_outbox__live_logical_task',
            ),
          ),
          reason: 'the database, not the writer, is the last line of defence',
        );
      },
    );

    test('erasing the actor demotes the obligation and drops its identity',
        () async {
      await _record(unitOfWork, dispatch, _helpOffer(sourceEventKey: 'offer-1'));

      // m0129's erasure trigger keeps the shared history and strips the
      // obligation from it. It predates these columns; m0181 teaches it to
      // clear them too, or the whole account delete aborts on
      // `notification_outbox__logical_task_chk`.
      await writer.execute(
        Sql.named('DELETE FROM public."user" WHERE id = @id'),
        parameters: {'id': _helperId},
      );

      final rows = await writer.execute('''
SELECT requires_action, logical_task_key, lifecycle_generation,
       attention_thread_key
FROM public.notification_outbox
''');
      expect(rows, hasLength(1), reason: 'the receipt is retained, not deleted');
      expect(rows.single[0], false);
      expect(rows.single[1], isNull);
      expect(rows.single[2], isNull);
      expect(rows.single[3], isNull);
    });

    test('a failure after the supersede leaves the database unchanged',
        () async {
      await _record(unitOfWork, dispatch, _helpOffer(sourceEventKey: 'offer-1'));
      final before = await _obligations(writer);

      await expectLater(
        unitOfWork.run(
          actorUserId: _helperId,
          action: () async {
            await dispatch.record(_helpOffer(sourceEventKey: 'offer-2'));
            throw StateError('source mutation failed after the renewal');
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        await _obligations(writer),
        before,
        reason: 'supersede and insert commit together or not at all: neither '
            'two live rows nor none',
      );
      expect(await _liveObligations(writer), hasLength(1));
    });
  }, skip: skipReason);
}

const _helperId = 'Uu05chelper';
const _authorId = 'Uu05cauthor';
const _reviewerId = 'Uu05creviewer';
const _beaconId = 'Bu05crequest';
const _otherBeaconId = 'Bu05cother';

Future<void> _record(
  MutatingUnitOfWork unitOfWork,
  AttentionDispatchRepository dispatch,
  AttentionDispatchIntent intent,
) => unitOfWork.run(
  actorUserId: intent.actorUserId,
  action: () => dispatch.record(intent),
);

AttentionDispatchIntent _helpOffer({
  required String sourceEventKey,
  String beaconId = _beaconId,
}) => AttentionDispatchIntent(
  eventType: AttentionEventType.helpOfferSubmitted,
  sourceEventKey: sourceEventKey,
  actorUserId: _helperId,
  priority: NotificationPriority.normal,
  kind: NotificationKind.commitmentEvent,
  title: 'New offer of help',
  body: 'Someone offered to help',
  actionUrl: '/#/view?id=$beaconId',
  collapseKey: 'offer|$beaconId',
  recipients: [
    AttentionRecipientSnapshot(
      recipientId: _authorId,
      reasons: const {AttentionRecipientReason.authorOfBeacon},
      role: AttentionRecipientRoleFacts(
        canReadBeaconContent: true,
        beaconId: beaconId,
        targetEntityId: _helperId,
        actorUserId: _helperId,
      ),
    ),
  ],
  beaconId: beaconId,
  targetEntityId: _helperId,
);

AttentionDispatchIntent _reviewOpened({required String sourceEventKey}) =>
    AttentionDispatchIntent(
      eventType: AttentionEventType.reviewOpened,
      sourceEventKey: sourceEventKey,
      actorUserId: _authorId,
      priority: NotificationPriority.high,
      kind: NotificationKind.reviewReady,
      title: 'Review opened',
      body: 'A review window opened',
      actionUrl: '/#/view?id=$_beaconId',
      collapseKey: 'review|$_beaconId',
      recipients: const [
        AttentionRecipientSnapshot(
          recipientId: _reviewerId,
          reasons: {AttentionRecipientReason.reviewParticipant},
          role: AttentionRecipientRoleFacts(
            canReadBeaconContent: true,
            beaconId: _beaconId,
            actorUserId: _authorId,
          ),
        ),
      ],
      beaconId: _beaconId,
    );

AttentionDispatchIntent _relay({required String sourceEventKey}) =>
    AttentionDispatchIntent(
      eventType: AttentionEventType.relayReceived,
      sourceEventKey: sourceEventKey,
      actorUserId: _helperId,
      priority: NotificationPriority.normal,
      kind: NotificationKind.newRelay,
      title: 'Forwarded Request',
      body: 'A Request was forwarded to you',
      actionUrl: '/#/view?id=$_beaconId',
      collapseKey: 'relay|$_beaconId',
      recipients: const [
        AttentionRecipientSnapshot(
          recipientId: _authorId,
          reasons: {AttentionRecipientReason.forwardRecipient},
          role: AttentionRecipientRoleFacts(
            canReadBeaconContent: true,
            beaconId: _beaconId,
            actorUserId: _helperId,
          ),
        ),
      ],
      beaconId: _beaconId,
    );

Future<List<Map<String, Object?>>> _obligations(Connection writer) async {
  final rows = await writer.execute('''
SELECT id, account_id, beacon_id, logical_task_key, lifecycle_generation,
       settlement_kind, settled_at::text, created_at::text, requires_action,
       attention_thread_key
FROM public.notification_outbox
WHERE requires_action
ORDER BY created_at, id
''');
  return [
    for (final row in rows) row.toColumnMap(),
  ];
}

Future<List<Map<String, Object?>>> _liveObligations(Connection writer) async {
  final rows = await _obligations(writer);
  return [
    for (final row in rows)
      if (row['settlement_kind'] == null) row,
  ];
}

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.attention_channel_delivery,
  public.attention_channel_throttle,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon,
  public."user"
CASCADE
''');
  for (final (id, key) in const [
    (_helperId, 'u05c-helper-key'),
    (_authorId, 'u05c-author-key'),
    (_reviewerId, 'u05c-reviewer-key'),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': key},
    );
  }
  for (final id in const [_beaconId, _otherBeaconId]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@beaconId, @authorId, 'Request', 'A request', 0)
'''),
      parameters: {'beaconId': id, 'authorId': _authorId},
    );
  }
}
