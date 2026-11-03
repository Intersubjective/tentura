import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

/// Real dispatched receipts, then the persisted lifecycle transition. History
/// keeps both rows; only the open Post contributes to Unread and the sweep.
Future<void> seedPostLifecycleReceipts(
  Connection writer, {
  required bool closedOnly,
  bool clearedClosed = false,
}) async {
  final database = getIt<TenturaDb>();
  final attention = TransactionalAttentionCase(
    MutatingUnitOfWork(database),
    AttentionDispatchRepository(database, Logger('PostLifecycleFixture')),
  );
  for (final (id, title) in [
    ('Bdotclosed001', 'Закрытая запись'),
    if (!closedOnly) ('Bdotopen00001', 'Открытая запись'),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, published_at, expires_at, is_discoverable)
VALUES (@id, 'Ua00000000001', '', '', 1, 0, now(), now() + interval '2 hours', false)
'''),
      parameters: {'id': id},
    );
    final sourceKey = 'reply:$id';
    await attention.runAction<void>(
      actorUserId: 'Ua00000000003',
      action: (tx) => tx.record(
        AttentionDispatchIntent(
          eventType: AttentionEventType.roomMessagePosted,
          sourceEventKey: sourceKey,
          actorUserId: 'Ua00000000003',
          priority: NotificationPriority.normal,
          kind: NotificationKind.roomActivityLowPriority,
          title: title,
          body: 'Новый ответ',
          actionUrl: '/#/beacon/$id',
          collapseKey: AttentionCollapseKey.none(sourceKey),
          beaconId: id,
          beaconKind: BeaconKind.post,
          recipients: [
            AttentionRecipientSnapshot(
              recipientId: 'Ua00000000001',
              reasons: const {AttentionRecipientReason.directedChatTarget},
              role: AttentionRecipientRoleFacts(
                beaconId: id,
                actorUserId: 'Ua00000000003',
                canReadBeaconContent: true,
                excerpt: 'Новый ответ',
              ),
            ),
          ],
        ),
      ),
    );
  }
  await writer.execute(
    "UPDATE public.beacon SET status = 6 WHERE id = 'Bdotclosed001'",
  );
  if (clearedClosed) {
    await writer.execute(
      "UPDATE public.notification_outbox SET cleared_at = now(), clear_reason = 'explicit', seen_at = now() WHERE beacon_id = 'Bdotclosed001'",
    );
  }
}
