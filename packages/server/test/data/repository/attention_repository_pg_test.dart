@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/coordination/filter_beacon_notifications.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attention authorized relation and repositories', () {
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository query;
    late AttentionAckRepository ack;
    late AttentionDispatchRepository dispatch;
    late AttentionChannelDeliveryRepository delivery;
    late MutatingUnitOfWork unitOfWork;
    late BeaconRoomRepository room;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      await writer.execute('''
CREATE TABLE public.attention_uow_probe (
  id text NOT NULL,
  phase text NOT NULL,
  transaction_id bigint NOT NULL,
  actor_user_id text
)
''');
      await writer.execute(r'''
CREATE FUNCTION public.capture_attention_uow_receipt()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.attention_uow_probe (
    id, phase, transaction_id, actor_user_id
  ) VALUES (
    NEW.id,
    'receipt',
    txid_current(),
    NULLIF(current_setting('tentura.mutating_user_id', true), '')
  );
  RETURN NULL;
END;
$$
''');
      await writer.execute('''
CREATE TRIGGER attention_uow_receipt_probe
AFTER INSERT ON public.notification_outbox
FOR EACH ROW EXECUTE FUNCTION public.capture_attention_uow_receipt()
''');
      database = TenturaDb(target.databaseEnv);
      query = AttentionRepository(database);
      ack = AttentionAckRepository(database);
      dispatch = AttentionDispatchRepository(database);
      delivery = AttentionChannelDeliveryRepository(database);
      unitOfWork = MutatingUnitOfWork(database);
      room = BeaconRoomRepository(database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.attention_channel_delivery,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.notification_outbox,
  public.notification_preference,
  public.beacon_room_seen,
  public.beacon_room_message,
  public.coordination_item,
  public.beacon,
  public.attention_uow_probe,
  public."user"
CASCADE
''');
      for (final (id, key) in const [
        (_viewerId, 'attention-viewer-key'),
        (_otherId, 'attention-other-key'),
      ]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': id, 'key': key},
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES
  (@contentId, @viewerId, 'Readable', 'Readable request', 0),
  (@tombstoneId, @viewerId, 'Deleted secret', 'Deleted request', 2),
  (@hiddenId, @otherId, 'Hidden', 'Hidden request', 0)
'''),
        parameters: {
          'contentId': _contentBeaconId,
          'tombstoneId': _tombstoneBeaconId,
          'hiddenId': _hiddenBeaconId,
          'viewerId': _viewerId,
          'otherId': _otherId,
        },
      );
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test(
      'relation delegates access and applies every policy and preference',
      () async {
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_preference (
  account_id, muted_in_app_event_classes
) VALUES (@accountId, ARRAY['request_progress']::text[])
'''),
          parameters: {'accountId': _viewerId},
        );

        await _insertReceipt(writer, id: 'N01legacyprofile');
        await _insertReceipt(
          writer,
          id: 'N02legacycontent',
          beaconId: _contentBeaconId,
        );
        await _insertReceipt(
          writer,
          id: 'N03legacytomb',
          beaconId: _tombstoneBeaconId,
        );
        await _insertReceipt(
          writer,
          id: 'N04legacyhidden',
          beaconId: _hiddenBeaconId,
        );
        await _insertReceipt(
          writer,
          id: 'N05content',
          beaconId: _contentBeaconId,
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon',
          presentationKey: 'request_status_changed',
        );
        await _insertReceipt(
          writer,
          id: 'N06contenthidden',
          beaconId: _hiddenBeaconId,
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon',
          presentationKey: 'request_status_changed',
        );
        await _insertReceipt(
          writer,
          id: 'N07tombstone',
          beaconId: _tombstoneBeaconId,
          accessPolicy: 'beacon_tombstone',
          destinationKind: 'beacon',
          presentationKey: 'request_removed',
        );
        await _insertReceipt(
          writer,
          id: 'N08safe',
          beaconId: _hiddenBeaconId,
          accessPolicy: 'recipient_safe',
          destinationKind: 'safe_terminal',
          presentationKey: 'offer_removed',
        );
        await _insertReceipt(
          writer,
          id: 'N09safewrongdest',
          beaconId: _hiddenBeaconId,
          accessPolicy: 'recipient_safe',
          destinationKind: 'beacon_people_offer',
          presentationKey: 'offer_removed',
        );
        await _insertReceipt(
          writer,
          id: 'N10profile',
          accessPolicy: 'profile',
          destinationKind: 'profile',
          presentationKey: 'invite_accepted',
        );
        await _insertReceipt(
          writer,
          id: 'N11profilewrongkey',
          accessPolicy: 'profile',
          destinationKind: 'profile',
          presentationKey: 'relationship_private_label',
        );
        await _insertReceipt(
          writer,
          id: 'N12muted',
          beaconId: _contentBeaconId,
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon',
          presentationKey: 'request_status_changed',
          suppressionClass: 'noisy',
          preferenceClass: 'request_progress',
        );
        await _insertReceipt(
          writer,
          id: 'N13mandatory',
          beaconId: _contentBeaconId,
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon',
          presentationKey: 'needs_me',
          suppressionClass: 'mandatory',
        );

        final result = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.unread,
          limit: 100,
        );
        final ids = result.page.items.map((item) => item.id).toSet();
        expect(ids, {
          'N01legacyprofile',
          'N02legacycontent',
          'N03legacytomb',
          'N05content',
          'N07tombstone',
          'N08safe',
          'N10profile',
          'N13mandatory',
        });
        expect(result.summary.unreadTotal, ids.length);
        expect(result.page.items, isNotEmpty);

        for (final id in ['N03legacytomb', 'N07tombstone']) {
          final item = result.page.items.singleWhere((row) => row.id == id);
          expect(item.title, kBeaconUnavailableNotificationTitle);
          expect(item.body, kBeaconUnavailableNotificationBody);
        }

        final definition = await writer.execute('''
SELECT pg_get_functiondef(
  'public.visible_attention_receipts(text)'::regprocedure
)
''');
        final sql = definition.single.single! as String;
        expect(sql, contains('beacon_can_read_content'));
        expect(sql, contains('beacon_can_read_tombstone'));
        expect(sql, contains('muted_in_app_event_classes'));
      },
    );

    test(
      'unreadForBeacons returns only authorized candidate Beacon ids',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nmarker-visible',
          beaconId: _contentBeaconId,
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon',
          presentationKey: 'request_status_changed',
        );
        await _insertReceipt(
          writer,
          id: 'Nmarker-hidden',
          beaconId: _hiddenBeaconId,
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon',
          presentationKey: 'request_status_changed',
        );

        expect(
          await query.unreadForBeacons(
            accountId: _viewerId,
            beaconIds: {_contentBeaconId, _hiddenBeaconId},
          ),
          {_contentBeaconId},
        );
        expect(
          await query.unreadForBeacons(
            accountId: _viewerId,
            beaconIds: const {},
          ),
          isEmpty,
        );
      },
    );

    test('composite cursor is stable for equal timestamps', () async {
      for (final id in const [
        'Nsame05',
        'Nsame04',
        'Nsame03',
        'Nsame02',
        'Nsame01',
      ]) {
        await _insertReceipt(writer, id: id);
      }

      final first = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        limit: 2,
      );
      final second = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        cursor: first.page.nextCursor,
        limit: 2,
      );
      final third = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        cursor: second.page.nextCursor,
        limit: 2,
      );

      expect(
        [
          ...first.page.items,
          ...second.page.items,
          ...third.page.items,
        ].map((item) => item.id),
        ['Nsame05', 'Nsame04', 'Nsame03', 'Nsame02', 'Nsame01'],
      );
      expect(first.summary.unreadTotal, 5);
      expect(second.summary.unreadTotal, 5);
      expect(third.page.nextCursor, isNull);
    });

    test(
      'search is authorized, payload-only, cursor-stable, and uses its index',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nsearch03',
          presentationPayload: '{"beaconId":"needle-request"}',
        );
        await _insertReceipt(
          writer,
          id: 'Nsearch02',
          presentationPayload: '{"messageId":"needle-message"}',
        );
        await _insertReceipt(
          writer,
          id: 'Nsearch01',
          presentationPayload: '{"targetEntityId":"needle-person"}',
        );
        await _insertReceipt(
          writer,
          id: 'Nsearchhidden',
          beaconId: _hiddenBeaconId,
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon',
          presentationKey: 'request_status_changed',
          presentationPayload: '{"beaconId":"needle-hidden"}',
        );
        await _insertReceipt(
          writer,
          id: 'Nsearchcopyonly',
          presentationPayload: '{"eventType":"ordinary"}',
          title: 'Needle must not be searchable from channel copy',
          body: 'Needle must not be searchable from channel copy',
        );

        final first = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.all,
          search: 'needle',
          limit: 2,
        );
        final second = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.all,
          search: 'needle',
          cursor: first.page.nextCursor,
          limit: 2,
        );

        expect(
          [...first.page.items, ...second.page.items].map((item) => item.id),
          ['Nsearch03', 'Nsearch02', 'Nsearch01'],
        );
        expect(second.page.nextCursor, isNull);

        await writer.execute('SET enable_seqscan = off');
        final plan = await writer.execute('''
EXPLAIN (COSTS OFF)
SELECT id
FROM public.notification_outbox
WHERE to_tsvector(
  'simple',
  coalesce(presentation_payload ->> 'eventType', '') || ' ' ||
  coalesce(presentation_payload ->> 'beaconId', '') || ' ' ||
  coalesce(presentation_payload ->> 'coordinationItemId', '') || ' ' ||
  coalesce(presentation_payload ->> 'targetEntityId', '') || ' ' ||
  coalesce(presentation_payload ->> 'messageId', '')
) @@ websearch_to_tsquery('simple', 'needle')
''');
        final planText = plan.map((row) => row.single).join('\n');
        expect(planText, contains('notification_outbox__payload_search'));
      },
    );

    test(
      'markSeen and markAllSeen are authorized, monotonic, and dual-write',
      () async {
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_preference (
  account_id, muted_in_app_event_classes
) VALUES (@accountId, ARRAY['request_progress']::text[])
'''),
          parameters: {'accountId': _viewerId},
        );
        await _insertReceipt(writer, id: 'Nvisible');
        await _insertReceipt(
          writer,
          id: 'Nhidden',
          beaconId: _hiddenBeaconId,
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon',
          presentationKey: 'request_status_changed',
        );
        await _insertReceipt(
          writer,
          id: 'Nmuted',
          beaconId: _contentBeaconId,
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon',
          presentationKey: 'request_status_changed',
          suppressionClass: 'noisy',
          preferenceClass: 'request_progress',
        );

        expect(
          await ack.markSeen(
            accountId: _viewerId,
            ids: const ['Nvisible', 'Nhidden', 'Nmuted'],
          ),
          1,
        );
        expect(
          await ack.markSeen(
            accountId: _viewerId,
            ids: const ['Nvisible'],
          ),
          0,
        );
        await _assertSeenOnly(writer, 'Nvisible');

        await _insertReceipt(writer, id: 'Nvisible2');
        expect(await ack.markAllSeen(_viewerId), 1);
        await _assertSeenOnly(writer, 'Nvisible2');

        final hidden = await writer.execute('''
SELECT id, seen_at, read_at
FROM public.notification_outbox
WHERE id IN ('Nhidden', 'Nmuted')
ORDER BY id
''');
        expect(hidden.every((row) => row[1] == null && row[2] == null), isTrue);

        final result = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.unread,
        );
        expect(result.summary.unreadTotal, 0);
        expect(result.page.items, isEmpty);
      },
    );

    test(
      'room watermark bridge clears only directed messages at or before it',
      () async {
        await writer.execute(
          Sql.named('''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, creator_id, target_person_id, published
) VALUES (
  'Iattentionthread', @beaconId, 2, @authorId, @otherId, true
)
'''),
          parameters: {
            'beaconId': _contentBeaconId,
            'authorId': _viewerId,
            'otherId': _otherId,
          },
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, mentions, thread_item_id, created_at
) VALUES
  ('Rdirectedold', @beaconId, @authorId, 'Old', ARRAY[]::text[], NULL,
    '2026-07-16T10:00:00Z'),
  ('Rdirectednew', @beaconId, @authorId, 'New', ARRAY[]::text[], NULL,
    '2026-07-16T12:00:00Z'),
  ('Rdirectedthread', @beaconId, @authorId, 'Thread', ARRAY[]::text[],
    'Iattentionthread', '2026-07-16T10:00:00Z')
'''),
          parameters: {
            'beaconId': _contentBeaconId,
            'authorId': _viewerId,
          },
        );
        for (final (id, messageId) in const [
          ('Ndirectedold', 'Rdirectedold'),
          ('Ndirectednew', 'Rdirectednew'),
        ]) {
          await _insertReceipt(
            writer,
            id: id,
            beaconId: _contentBeaconId,
            accessPolicy: 'beacon_content',
            destinationKind: 'beacon_room_message',
            presentationKey: 'room_message_posted',
            targetEntityId: messageId,
          );
        }
        await _insertReceipt(
          writer,
          id: 'Ndirectedthread',
          beaconId: _contentBeaconId,
          coordinationItemId: 'Iattentionthread',
          accessPolicy: 'beacon_content',
          destinationKind: 'beacon_room_message',
          presentationKey: 'room_message_posted',
          targetEntityId: 'Rdirectedthread',
        );

        await room.markBeaconRoomSeen(
          userId: _viewerId,
          beaconId: _contentBeaconId,
          threadItemId: null,
          at: DateTime.parse('2026-07-16T11:00:00Z'),
        );
        await _assertSeenOnly(writer, 'Ndirectedold');
        await _assertUnread(writer, 'Ndirectednew');
        await _assertUnread(writer, 'Ndirectedthread');

        await room.markBeaconRoomSeen(
          userId: _viewerId,
          beaconId: _contentBeaconId,
          threadItemId: 'Iattentionthread',
          at: DateTime.parse('2026-07-16T11:00:00Z'),
        );
        await _assertSeenOnly(writer, 'Ndirectedthread');

        await room.markBeaconRoomSeen(
          userId: _viewerId,
          beaconId: _contentBeaconId,
          threadItemId: null,
          at: DateTime.parse('2026-07-16T09:00:00Z'),
        );
        final watermark = await writer.execute(
          Sql.named('''
SELECT last_seen_at
FROM public.beacon_room_seen
WHERE user_id = @userId AND beacon_id = @beaconId
  AND thread_item_id IS NULL
'''),
          parameters: {
            'userId': _viewerId,
            'beaconId': _contentBeaconId,
          },
        );
        expect(
          DateTime.parse(watermark.single.single.toString()),
          DateTime.parse('2026-07-16T11:00:00Z'),
        );
        await _assertUnread(writer, 'Ndirectednew');

        expect(
          await ack.bridgeRoomWatermark(
            accountId: _viewerId,
            beaconId: _contentBeaconId,
            threadItemId: null,
            lastSeenAt: DateTime.parse('2026-07-16T13:00:00Z'),
          ),
          1,
        );
        await _assertSeenOnly(writer, 'Ndirectednew');
      },
    );

    test(
      'unit of work shares txid and actor, then persists a delivery job',
      () async {
        final useCase = TransactionalAttentionCase(unitOfWork, dispatch);

        final result = await useCase.run(
          actorUserId: _viewerId,
          intent: _dispatchIntent(),
          mutation: () => database.withMutatingUser(_viewerId, () async {
            await _insertDomainProbe(database, 'domain-success');
            return 'committed';
          }),
        );

        expect(result, 'committed');
        expect(await _deliveryCount(writer), 1);
        final probes = await writer.execute('''
SELECT phase, transaction_id, actor_user_id
FROM public.attention_uow_probe
ORDER BY phase
''');
        expect(probes.map((row) => row[0]), ['domain', 'receipt']);
        expect(probes.map((row) => row[1]).toSet(), hasLength(1));
        expect(probes.map((row) => row[2]).toSet(), {_viewerId});
      },
    );

    test('domain and receipt failures roll back symmetrically', () async {
      final domainFailureCase = TransactionalAttentionCase(
        unitOfWork,
        dispatch,
      );
      await expectLater(
        domainFailureCase.run<void>(
          actorUserId: _viewerId,
          intent: _dispatchIntent(),
          mutation: () async {
            await _insertDomainProbe(database, 'domain-failure');
            throw StateError('domain failed');
          },
        ),
        throwsStateError,
      );
      expect(await _probeCount(writer), 0);
      expect(await _outboxCount(writer), 0);

      final receiptFailureCase = TransactionalAttentionCase(
        unitOfWork,
        dispatch,
      );
      await expectLater(
        receiptFailureCase.run<void>(
          actorUserId: _viewerId,
          intent: _dispatchIntent(recipientId: 'Uattentionmissing'),
          mutation: () => _insertDomainProbe(database, 'receipt-failure'),
        ),
        throwsA(isA<Exception>()),
      );
      expect(await _probeCount(writer), 0);
      expect(await _outboxCount(writer), 0);
    });

    test(
      'delivery jobs are durable and duplicate recording collapses',
      () async {
        final useCase = TransactionalAttentionCase(unitOfWork, dispatch);
        expect(
          await useCase.run(
            actorUserId: _viewerId,
            intent: _dispatchIntent(),
            mutation: () async {
              await _insertDomainProbe(database, 'channel-failure');
              return 42;
            },
          ),
          42,
        );
        expect(await _outboxCount(writer), 1);
        expect(await _deliveryCount(writer), 1);
        expect(await _probeCount(writer), 2);
        await expectLater(
          unitOfWork.run(
            actorUserId: _viewerId,
            action: () => dispatch.record(
              _dispatchIntent().copyWith(body: 'different source facts'),
            ),
          ),
          throwsStateError,
        );

        await writer.execute('TRUNCATE public.attention_uow_probe');
        await writer.execute(
          'TRUNCATE public.attention_channel_delivery, public.notification_outbox, public.attention_occurrence_recipient, public.attention_occurrence',
        );
        await unitOfWork.run(
          actorUserId: _viewerId,
          action: () async {
            await _insertDomainProbe(database, 'collapse');
            await dispatch.record(_dispatchIntent());
            await dispatch.record(_dispatchIntent(sourceEventKey: 'relay-2'));
          },
        );
        final collapsed = await writer.execute('''
SELECT count(*)::int, max(collapsed_count)::int
FROM public.notification_outbox
''');
        expect(collapsed.single[0], 1);
        expect(collapsed.single[1], 2);
      },
    );

    test(
      'watcher-only status receipt is durable but has no channel decision',
      () async {
        await unitOfWork.run(
          actorUserId: _viewerId,
          action: () => dispatch.record(
            const AttentionDispatchIntent(
              eventType: AttentionEventType.requestStatusChanged,
              sourceEventKey: 'status-transition-1',
              actorUserId: _viewerId,
              priority: NotificationPriority.low,
              kind: NotificationKind.roomActivityLowPriority,
              title: 'Request status changed',
              body: 'Request moved from open to closed',
              actionUrl: '/#/view?id=$_contentBeaconId',
              collapseKey: 'status-transition-1',
              recipients: [
                AttentionRecipientSnapshot(
                  recipientId: _otherId,
                  reasons: {AttentionRecipientReason.activeParticipant},
                  role: AttentionRecipientRoleFacts(
                    canReadBeaconContent: true,
                    beaconId: _contentBeaconId,
                  ),
                ),
                AttentionRecipientSnapshot(
                  recipientId: _viewerId,
                  reasons: {AttentionRecipientReason.inboxStanceHolder},
                  role: AttentionRecipientRoleFacts(
                    canReadBeaconContent: true,
                    beaconId: _contentBeaconId,
                  ),
                  collapseKey: 'request-status|$_contentBeaconId',
                  channelEligible: false,
                ),
              ],
              beaconId: _contentBeaconId,
            ),
          ),
        );

        expect(await _deliveryCount(writer), 1);
        final rows = await writer.execute('''
SELECT account_id, suppression_class
FROM public.notification_outbox
ORDER BY account_id
''');
        expect(rows, hasLength(2));
        expect(
          rows.map((row) => (row[0], row[1])).toSet(),
          {(_otherId, 'standard'), (_viewerId, 'noisy')},
        );
      },
    );

    test(
      'delivery claims lease, throttle, retry, and dead-letter atomically',
      () async {
        await unitOfWork.run(
          actorUserId: _viewerId,
          action: () => dispatch.record(_dispatchIntent()),
        );
        final now = DateTime.timestamp().toUtc();
        final first = await delivery.claimDue(
          workerId: 'worker-a',
          now: now,
          limit: 10,
        );
        expect(first, hasLength(1));
        final competing = await delivery.claimDue(
          workerId: 'worker-b',
          now: now,
          limit: 10,
        );
        expect(competing, isEmpty);

        final expiredLease = now.subtract(const Duration(seconds: 1)).toUtc();
        await writer.execute(
          Sql.named('''
UPDATE public.attention_channel_delivery
SET lease_until = @leaseUntil
WHERE id = @id
'''),
          parameters: {
            'leaseUntil': expiredLease,
            'id': first.single.id,
          },
        );
        await writer.execute(
          Sql.named('''
UPDATE public.attention_channel_throttle
SET lease_until = @leaseUntil
WHERE account_id = @accountId AND channel = 'immediate'
'''),
          parameters: {
            'leaseUntil': expiredLease,
            'accountId': _otherId,
          },
        );
        final reclaimed = await delivery.claimDue(
          workerId: 'worker-c',
          now: now,
          limit: 10,
        );
        expect(reclaimed, hasLength(1));

        await delivery.retryOrDeadLetter(
          id: reclaimed.single.id,
          workerId: 'worker-c',
          now: now,
          error: StateError('fcm down'),
        );
        final retrySoon = await delivery.claimDue(
          workerId: 'worker-b',
          now: now.add(const Duration(seconds: 29)),
          limit: 10,
        );
        expect(retrySoon, isEmpty);
        final retry = await delivery.claimDue(
          workerId: 'worker-b',
          now: now.add(const Duration(minutes: 1)),
          limit: 10,
        );
        expect(retry, hasLength(1));

        final terminalLease = now.add(const Duration(minutes: 3));
        await writer.execute(
          Sql.named('''
UPDATE public.attention_channel_delivery
SET attempts = 5, status = 'leased', lease_owner = 'worker-b',
    lease_until = @leaseUntil
WHERE id = @id
'''),
          parameters: {
            'leaseUntil': terminalLease,
            'id': retry.single.id,
          },
        );
        await delivery.retryOrDeadLetter(
          id: retry.single.id,
          workerId: 'worker-b',
          now: now.add(const Duration(minutes: 2)),
          error: StateError('still down'),
        );
        final terminal = await writer.execute('''
SELECT status, dead_lettered_at IS NOT NULL
FROM public.attention_channel_delivery
WHERE id = '${retry.single.id}'
''');
        expect(terminal.single, ['dead', true]);
      },
    );
  }, skip: skipReason);
}

const _viewerId = 'Uattention01';
const _otherId = 'Uattention02';
const _contentBeaconId = 'Battentioncontent';
const _tombstoneBeaconId = 'Battentiontomb';
const _hiddenBeaconId = 'Battentionhidden';

AttentionDispatchIntent _dispatchIntent({
  String recipientId = _otherId,
  String sourceEventKey = 'relay-1',
}) => AttentionDispatchIntent(
  eventType: AttentionEventType.relayReceived,
  sourceEventKey: sourceEventKey,
  actorUserId: _viewerId,
  priority: NotificationPriority.normal,
  kind: NotificationKind.newRelay,
  title: 'Forwarded Request',
  body: 'A Request was forwarded to you',
  actionUrl: '/#/view?id=$_contentBeaconId',
  collapseKey: 'relay|$_contentBeaconId',
  recipients: [
    AttentionRecipientSnapshot(
      recipientId: recipientId,
      reasons: const {AttentionRecipientReason.forwardRecipient},
      role: const AttentionRecipientRoleFacts(
        canReadBeaconContent: true,
        beaconId: _contentBeaconId,
        actorUserId: _viewerId,
      ),
    ),
  ],
  beaconId: _contentBeaconId,
);

Future<void> _insertDomainProbe(TenturaDb database, String id) =>
    database.customStatement(
      r'''
INSERT INTO public.attention_uow_probe (
  id, phase, transaction_id, actor_user_id
) VALUES (
  $1,
  'domain',
  txid_current(),
  NULLIF(current_setting('tentura.mutating_user_id', true), '')
)
''',
      [id],
    );

Future<int> _probeCount(Connection writer) async {
  final rows = await writer.execute(
    'SELECT count(*)::int FROM public.attention_uow_probe',
  );
  return rows.single.single! as int;
}

Future<int> _outboxCount(Connection writer) async {
  final rows = await writer.execute(
    'SELECT count(*)::int FROM public.notification_outbox',
  );
  return rows.single.single! as int;
}

Future<int> _deliveryCount(Connection writer) async {
  final rows = await writer.execute(
    'SELECT count(*)::int FROM public.attention_channel_delivery',
  );
  return rows.single.single! as int;
}

class _TestChannels implements BeaconNotificationPort {
  _TestChannels({this.onHandOff, this.throwOnHandOff = false});

  final Future<void> Function(List<AttentionChannelDecision>)? onHandOff;
  final bool throwOnHandOff;
  int handOffCalls = 0;

  @override
  Future<void> dispatch(BeaconNotificationIntent intent) async {}

  @override
  Future<void> handOffChannels(
    List<AttentionChannelDecision> decisions,
  ) async {
    handOffCalls += 1;
    await onHandOff?.call(decisions);
    if (throwOnHandOff) {
      throw StateError('channel failed');
    }
  }
}

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  String? beaconId,
  String? coordinationItemId,
  String accessPolicy = 'legacy',
  String? destinationKind,
  String? presentationKey,
  String suppressionClass = 'standard',
  String? preferenceClass,
  String? targetEntityId,
  String createdAt = '2026-07-16T12:00:00Z',
  String presentationPayload = '{"eventType":"fixture"}',
  String title = 'Secret title',
  String body = 'Secret body',
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, coordination_item_id, source_event_key,
  destination_kind, target_entity_id,
  presentation_key, presentation_payload,
  suppression_class, in_app_preference_class, access_policy
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  @title, @body, '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @coordinationItemId, @sourceEventKey,
  @destinationKind, @targetEntityId,
  @presentationKey, CAST(@presentationPayload AS jsonb),
  @suppressionClass, @preferenceClass, @accessPolicy
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'coordinationItemId': coordinationItemId,
    'sourceEventKey': destinationKind == null ? null : 'source-$id',
    'destinationKind': destinationKind,
    'targetEntityId': targetEntityId,
    'presentationKey': presentationKey,
    'presentationPayload': presentationPayload,
    'title': title,
    'body': body,
    'suppressionClass': suppressionClass,
    'preferenceClass': preferenceClass,
    'accessPolicy': accessPolicy,
  },
);

Future<void> _assertSeenOnly(Connection writer, String id) async {
  final row = await writer.execute(
    Sql.named('''
SELECT seen_at, read_at
FROM public.notification_outbox
WHERE id = @id
'''),
    parameters: {'id': id},
  );
  expect(row.single[0], isNotNull);
  expect(row.single[1], isNull);
}

Future<void> _assertUnread(Connection writer, String id) async {
  final row = await writer.execute(
    Sql.named('''
SELECT seen_at, read_at
FROM public.notification_outbox
WHERE id = @id
'''),
    parameters: {'id': id},
  );
  expect(row.single[0], isNull);
  expect(row.single[1], isNull);
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_ATTENTION_TEST_DB'] ??
        'tentura_test_attention_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_ATTENTION_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      final remaining = await connection.execute(
        r'SELECT count(*)::int FROM pg_database WHERE datname = $1',
        parameters: [databaseName],
      );
      if (remaining.single.single != 0) {
        throw StateError('Disposable database was not dropped: $databaseName');
      }
    } finally {
      await connection.close();
    }
  }
}
