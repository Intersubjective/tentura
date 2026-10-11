@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _inviter = 'Uaicinviter1';
const _invitee = 'Uaicinvitee1';
const _other = 'Uaicother001';
const _users = [_inviter, _invitee, _other];

const _beacon = 'Baicbeacon01';
const _otherBeacon = 'Baicbeacon02';

/// Plan unit C2: `AttentionSystemSettlementPort.clearAuthorInviteReceived`
/// clears (and marks seen) exactly the invitee's `authorInviteReceived`
/// receipts on one Request. Accept, decline, withdraw, supersede, expiry and
/// block cleanup all end the invitation, so the optional update it raised
/// must stop asking for attention.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_AUTHOR_INVITE_CLEAR_TEST_DB',
    defaultNamePrefix: 'tentura_test_author_invite_clear',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('clearAuthorInviteReceived', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionDispatchRepository dispatch;
    late AttentionSystemSettlementRepository settlement;
    late MutatingUnitOfWork uow;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      dispatch = AttentionDispatchRepository(
        database,
        Logger('AuthorInviteClearPgTest'),
      );
      settlement = AttentionSystemSettlementRepository(database);
      uow = MutatingUnitOfWork(database);
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> receipt({
      required AttentionEventType eventType,
      required String beaconId,
      required String recipientId,
      required String key,
    }) => uow.run(
      actorUserId: _inviter,
      action: () => dispatch.record(
        AttentionDispatchIntent(
          eventType: eventType,
          sourceEventKey: key,
          actorUserId: _inviter,
          priority: NotificationPriority.normal,
          kind: eventType == AttentionEventType.authorInviteReceived
              ? NotificationKind.authorInviteReceived
              : NotificationKind.newRelay,
          title: 'Inviter',
          body: 'invites you to help',
          actionUrl: '/#/beacon/view/$beaconId',
          collapseKey: AttentionCollapseKey.none(key),
          recipients: [
            AttentionRecipientSnapshot(
              recipientId: recipientId,
              reasons: {
                if (eventType == AttentionEventType.authorInviteReceived)
                  AttentionRecipientReason.authorInvitee
                else
                  AttentionRecipientReason.forwardRecipient,
              },
              role: AttentionRecipientRoleFacts(
                canReadBeaconContent: true,
                beaconId: beaconId,
                actorUserId: _inviter,
              ),
            ),
          ],
          beaconId: beaconId,
        ),
      ),
    );

    Future<Map<String, ({bool cleared, bool seen, String? reason})>>
    receipts() async => {
      for (final row in await writer.execute('''
SELECT o.source_event_key, o.cleared_at IS NOT NULL, o.seen_at IS NOT NULL,
       o.clear_reason
FROM public.notification_outbox o
ORDER BY o.source_event_key
'''))
        row[0]! as String: (
          cleared: row[1]! as bool,
          seen: row[2]! as bool,
          reason: row[3] as String?,
        ),
    };

    Future<int> clear(String beaconId, String inviteeId) => uow.run(
      actorUserId: _inviter,
      action: () => settlement.clearAuthorInviteReceived(
        beaconId: beaconId,
        inviteeId: inviteeId,
      ),
    );

    test("clears and marks seen only the invitee's invite receipt on the "
        'Request', () async {
      await receipt(
        eventType: AttentionEventType.authorInviteReceived,
        beaconId: _beacon,
        recipientId: _invitee,
        key: 'k1-invite',
      );
      await receipt(
        eventType: AttentionEventType.authorInviteReceived,
        beaconId: _otherBeacon,
        recipientId: _invitee,
        key: 'k2-invite-other-request',
      );
      await receipt(
        eventType: AttentionEventType.authorInviteReceived,
        beaconId: _beacon,
        recipientId: _other,
        key: 'k3-invite-other-person',
      );
      await receipt(
        eventType: AttentionEventType.relayReceived,
        beaconId: _beacon,
        recipientId: _invitee,
        key: 'k4-relay',
      );

      expect(await clear(_beacon, _invitee), 1);

      final after = await receipts();
      expect(after['k1-invite'], (cleared: true, seen: true, reason: 'sweep'));
      expect(
        after['k2-invite-other-request'],
        (cleared: false, seen: false, reason: null),
      );
      expect(
        after['k3-invite-other-person'],
        (cleared: false, seen: false, reason: null),
      );
      expect(after['k4-relay'], (cleared: false, seen: false, reason: null));
    });

    test('is idempotent and harmless without a receipt', () async {
      expect(await clear(_beacon, _invitee), 0);

      await receipt(
        eventType: AttentionEventType.authorInviteReceived,
        beaconId: _beacon,
        recipientId: _invitee,
        key: 'k1-invite',
      );
      expect(await clear(_beacon, _invitee), 1);
      expect(await clear(_beacon, _invitee), 0);
    });

    test('keeps an earlier seen_at', () async {
      await receipt(
        eventType: AttentionEventType.authorInviteReceived,
        beaconId: _beacon,
        recipientId: _invitee,
        key: 'k1-invite',
      );
      await writer.execute('''
UPDATE public.notification_outbox SET seen_at = '2026-01-01T00:00:00Z'
''');

      await clear(_beacon, _invitee);

      final rows = await writer.execute('''
SELECT seen_at = '2026-01-01T00:00:00Z'::timestamptz, cleared_at IS NOT NULL
FROM public.notification_outbox
''');
      expect(rows.single[0], isTrue);
      expect(rows.single[1], isTrue);
    });
  });
}

Future<void> _seed(Connection writer) async {
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
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('aiclear', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at)
VALUES
  ('$_beacon', '$_inviter', 'Child', '', 0, 0, false, now()),
  ('$_otherBeacon', '$_inviter', 'Other', '', 0, 0, false, now())
''');
}
