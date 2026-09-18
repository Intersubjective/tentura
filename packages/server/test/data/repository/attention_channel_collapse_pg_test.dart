@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:logging/logging.dart';

import '../../support/disposable_pg_target.dart';

/// U05b — collapsing lives at the channel layer.
///
/// U05a made in-app receipts immutable and one-per-occurrence, which is
/// right for the feed and wrong for push/email: a family of receipts that
/// share a collapse key is *one* thing to notify about. These tests assert
/// **delivery cardinality**, not row counts — a duplicate push is invisible
/// to a test that only counts receipts.
///
/// The collapse key is the one that already exists:
/// `attention_occurrence_recipient.collapse_key`. No new vocabulary, no new
/// column.
///
/// Two failure modes are pinned:
///
/// 1. **Duplicate notification.** Two receipts in one collapse family must
///    leave exactly one *pending* delivery job.
/// 2. **Stale `receiptId` in the payload.** The surviving job must carry the
///    newest receipt of the family — the one whose copy the notification
///    shows — so tapping the notification opens a receipt that exists and is
///    still open. An older receipt may have been cleared or settled in the
///    meantime; the newest cannot have been, because it was just written.
///
/// A job that is no longer pending (leased, delivered, dead) is never
/// collapsed into: that send has already left or is leaving, so swallowing a
/// later event into it would lose a notification outright.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U05B_CHANNEL_TEST_DB',
    defaultNamePrefix: 'tentura_test_u05b_channel',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attention channel collapse', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionDispatchRepository dispatch;
    late MutatingUnitOfWork unitOfWork;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      dispatch = AttentionDispatchRepository(
        database,
        Logger('attention-channel-collapse-test'),
      );
      unitOfWork = MutatingUnitOfWork(database);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() async {
      await _resetFixtures(writer);
    });

    Future<void> record(
      String sourceEventKey, {
      String collapseKey = 'relay|$_beaconId',
      String recipientId = _recipientId,
      String title = 'Forwarded Request',
    }) => unitOfWork.run(
      actorUserId: _actorId,
      action: () => dispatch.record(
        _intent(
          sourceEventKey: sourceEventKey,
          collapseKey: collapseKey,
          recipientId: recipientId,
          title: title,
        ),
      ),
    );

    test(
      'two receipts in one collapse family leave one pending delivery '
      'carrying the newest receipt',
      () async {
        await record('relay-1', title: 'First forward');
        await record('relay-2', title: 'Second forward');

        expect(
          await _count(writer, 'public.notification_outbox'),
          2,
          reason: 'in-app receipts stay one per occurrence (U05a)',
        );

        final jobs = await _deliveries(writer);
        expect(
          jobs,
          hasLength(1),
          reason: 'one collapse family is one notification, not two',
        );

        final newestReceipt = await _newestReceiptId(writer);
        expect(
          jobs.single['receipt_id'],
          newestReceipt,
          reason: 'the job must reference the receipt whose copy it carries',
        );
        expect(jobs.single['payload_receipt_id'], newestReceipt);
        expect(jobs.single['payload_title'], 'Second forward');
        expect(jobs.single['status'], 'pending');
      },
    );

    test('two collapse families keep two pending deliveries', () async {
      await record('relay-1');
      await record('other-1', collapseKey: 'relay|other');

      expect(await _deliveries(writer), hasLength(2));
    });

    test(
      'one collapse family across two recipients is two deliveries',
      () async {
        await record('relay-1');
        await record('relay-2', recipientId: _secondRecipientId);

        final jobs = await _deliveries(writer);
        expect(jobs, hasLength(2));
        expect(
          {for (final job in jobs) job['account_id']},
          {_recipientId, _secondRecipientId},
          reason:
              'collapse is per account; one recipient never absorbs another',
        );
      },
    );

    test('a leased job is never collapsed into', () async {
      await record('relay-1');
      await writer.execute('''
UPDATE public.attention_channel_delivery
SET status = 'leased', lease_owner = 'worker-x',
    lease_until = now() + interval '2 minutes'
''');

      await record('relay-2');

      final jobs = await _deliveries(writer);
      expect(
        jobs,
        hasLength(2),
        reason: 'the leased send has already left; the new event needs its own',
      );
      expect(
        {for (final job in jobs) job['status']},
        {'leased', 'pending'},
      );
    });

    test('a delivered job is never collapsed into', () async {
      await record('relay-1');
      await writer.execute('''
UPDATE public.attention_channel_delivery
SET status = 'delivered', delivered_at = now()
''');

      await record('relay-2');

      final jobs = await _deliveries(writer);
      expect(jobs, hasLength(2));
      expect(
        {for (final job in jobs) job['status']},
        {'delivered', 'pending'},
      );
    });
  }, skip: skipReason);
}

const _actorId = 'Uu05bactor';
const _recipientId = 'Uu05brecipient';
const _secondRecipientId = 'Uu05bsecond';
const _beaconId = 'Bu05bcontent';

AttentionDispatchIntent _intent({
  required String sourceEventKey,
  required String collapseKey,
  required String recipientId,
  required String title,
}) => AttentionDispatchIntent(
  eventType: AttentionEventType.relayReceived,
  sourceEventKey: sourceEventKey,
  actorUserId: _actorId,
  priority: NotificationPriority.normal,
  kind: NotificationKind.newRelay,
  title: title,
  body: 'A Request was forwarded to you',
  actionUrl: '/#/view?id=$_beaconId',
  collapseKey: collapseKey,
  recipients: [
    AttentionRecipientSnapshot(
      recipientId: recipientId,
      reasons: const {AttentionRecipientReason.forwardRecipient},
      role: const AttentionRecipientRoleFacts(
        canReadBeaconContent: true,
        beaconId: _beaconId,
        actorUserId: _actorId,
      ),
    ),
  ],
  beaconId: _beaconId,
);

Future<List<Map<String, Object?>>> _deliveries(Connection writer) async {
  final rows = await writer.execute('''
SELECT id, account_id, receipt_id, occurrence_id, status,
       payload->>'receiptId' AS payload_receipt_id,
       payload->>'title' AS payload_title,
       payload->>'dedupKey' AS payload_dedup_key
FROM public.attention_channel_delivery
ORDER BY created_at, id
''');
  return [for (final row in rows) row.toColumnMap()];
}

Future<String> _newestReceiptId(Connection writer) async {
  final rows = await writer.execute('''
SELECT id FROM public.notification_outbox
ORDER BY created_at DESC, id DESC LIMIT 1
''');
  return rows.single.single! as String;
}

Future<int> _count(Connection writer, String table) async {
  final rows = await writer.execute('SELECT count(*)::int FROM $table');
  return rows.single.single! as int;
}

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.attention_channel_delivery,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon,
  public."user"
CASCADE
''');
  for (final (id, key) in const [
    (_actorId, 'u05b-actor-key'),
    (_recipientId, 'u05b-recipient-key'),
    (_secondRecipientId, 'u05b-second-key'),
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
VALUES (@beaconId, @actorId, 'Readable', 'Readable request', 0)
'''),
    parameters: {'beaconId': _beaconId, 'actorId': _actorId},
  );
}
