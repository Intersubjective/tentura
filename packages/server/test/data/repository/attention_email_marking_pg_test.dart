@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

import '../../support/disposable_pg_target.dart';

/// U05b — the email channel marks by the **channel collapse key**.
///
/// One immediate email represents a whole collapse family, because U05b makes
/// the delivery layer send one notification per family. Marking must cover
/// exactly that family for exactly that account: mark too little and the
/// digest re-sends what was just emailed, mark too much and a receipt that
/// was never emailed is silently suppressed forever (and, via
/// `deleteSettledOlderThan`, becomes deletable early).
///
/// `notification_outbox.dedup_key` is the persisted channel collapse key —
/// `<accountId>|attention-v1|<collapseKey>` — so no new column is introduced.
/// The account is passed explicitly rather than trusted to be encoded in that
/// string: the marking is per-account by definition, and the predicate should
/// say so rather than depend on how the key happens to be built.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U05B_EMAIL_TEST_DB',
    defaultNamePrefix: 'tentura_test_u05b_email',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('markEmailedByChannelCollapseKey', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late NotificationOutboxRepository outbox;
    late AttentionDispatchRepository dispatch;
    late MutatingUnitOfWork unitOfWork;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      outbox = NotificationOutboxRepository(database);
      dispatch = AttentionDispatchRepository(
        database,
        Logger('attention-email-marking-test'),
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
      String collapseKey = _familyA,
      String recipientId = _recipientId,
    }) => unitOfWork.run(
      actorUserId: _actorId,
      action: () => dispatch.record(
        _intent(
          sourceEventKey: sourceEventKey,
          collapseKey: collapseKey,
          recipientId: recipientId,
        ),
      ),
    );

    test(
      'marks every receipt of the sent family and nothing outside it',
      () async {
        await record('a-1');
        await record('a-2');
        await record('b-1', collapseKey: _familyB);
        await record('other-1', recipientId: _secondRecipientId);
        // A row that shares the family's dedup_key but belongs to another
        // account. Unreachable through dispatch, which prefixes the account
        // id — which is exactly why the predicate must not rely on that.
        await _insertForeignRow(writer);

        final marked = await outbox.markEmailedByChannelCollapseKey(
          accountId: _recipientId,
          channelCollapseKey: _channelKey(_familyA),
        );
        expect(marked, 2, reason: 'both receipts of family A, and only those');

        final state = await _emailedState(writer);
        expect(
          state.entries
              .where((entry) => entry.value)
              .map((entry) => entry.key)
              .toSet(),
          {'a-1', 'a-2'},
          reason:
              'family B, the other recipient, and the foreign-account row '
              'must stay unemailed',
        );
        expect(state['foreign'], isFalse);
      },
    );

    test('an already-emailed receipt keeps its original timestamp', () async {
      await record('a-1');
      await outbox.markEmailedByChannelCollapseKey(
        accountId: _recipientId,
        channelCollapseKey: _channelKey(_familyA),
      );
      final first = await _emailedAt(writer, 'a-1');
      expect(first, isNotNull);

      await record('a-2');
      final marked = await outbox.markEmailedByChannelCollapseKey(
        accountId: _recipientId,
        channelCollapseKey: _channelKey(_familyA),
      );
      expect(marked, 1, reason: 'only the receipt that was still unemailed');
      expect(await _emailedAt(writer, 'a-1'), first);
      expect(await _emailedAt(writer, 'a-2'), isNotNull);
    });

    test('an unknown collapse family marks nothing', () async {
      await record('a-1');
      expect(
        await outbox.markEmailedByChannelCollapseKey(
          accountId: _recipientId,
          channelCollapseKey: _channelKey('relay|nosuchthing'),
        ),
        0,
      );
      expect(await _emailedAt(writer, 'a-1'), isNull);
    });
  }, skip: skipReason);
}

const _actorId = 'Uu05bmailactor';
const _recipientId = 'Uu05bmailrecip';
const _secondRecipientId = 'Uu05bmailsecond';
const _beaconId = 'Bu05bmail';
const _familyA = 'relay|family-a';
const _familyB = 'relay|family-b';

/// The value dispatch persists in `notification_outbox.dedup_key` — the
/// channel collapse key as stored.
String _channelKey(String collapseKey) =>
    '$_recipientId|attention-v1|$collapseKey';

AttentionDispatchIntent _intent({
  required String sourceEventKey,
  required String collapseKey,
  required String recipientId,
}) => AttentionDispatchIntent(
  eventType: AttentionEventType.relayReceived,
  sourceEventKey: sourceEventKey,
  actorUserId: _actorId,
  priority: NotificationPriority.normal,
  kind: NotificationKind.newRelay,
  title: 'Forwarded Request',
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

Future<void> _insertForeignRow(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, source_event_key, destination_kind, presentation_key,
  suppression_class, access_policy, beacon_id, target_entity_id
) VALUES (
  gen_random_uuid()::text, @accountId, 'coordination', 'newRelay', 'normal',
  'Foreign', 'Foreign', '/#/', @dedupKey, 'foreign', 'beacon',
  'attention.relay', 'standard', 'beacon_content', @beaconId, @beaconId
)
'''),
    parameters: {
      'accountId': _secondRecipientId,
      'dedupKey': _channelKey(_familyA),
      'beaconId': _beaconId,
    },
  );
}

/// `source_event_key` → whether the receipt is marked emailed.
Future<Map<String, bool>> _emailedState(Connection writer) async {
  final rows = await writer.execute('''
SELECT source_event_key, emailed_at IS NOT NULL
FROM public.notification_outbox
''');
  return {
    for (final row in rows) row[0]! as String: row[1]! as bool,
  };
}

Future<Object?> _emailedAt(Connection writer, String sourceEventKey) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT emailed_at::text FROM public.notification_outbox
WHERE source_event_key = @key
'''),
    parameters: {'key': sourceEventKey},
  );
  return rows.single.single;
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
    (_actorId, 'u05b-mail-actor-key'),
    (_recipientId, 'u05b-mail-recipient-key'),
    (_secondRecipientId, 'u05b-mail-second-key'),
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
