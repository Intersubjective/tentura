@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/help_path_node.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

import '../../support/disposable_pg_target.dart';

/// The channel decision a worker claims carries the presentation identity of
/// its job, decoded from what dispatch really wrote (encoder, jsonb, decoder).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CHANNEL_DECISION_DECODE_TEST_DB',
    defaultNamePrefix: 'tentura_test_channel_decision_decode',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('channel decision presentation identity', () {
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
        Logger('channel-decision-decode-test'),
      );
      unitOfWork = MutatingUnitOfWork(database);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() => _resetFixtures(writer));

    Future<void> record({
      required AttentionEventType eventType,
      required String sourceEventKey,
      required String title,
      required String body,
      required Set<AttentionRecipientReason> reasons,
      required AttentionRecipientRoleFacts role,
    }) => unitOfWork.run(
      actorUserId: _actorId,
      action: () => dispatch.record(
        AttentionDispatchIntent(
          eventType: eventType,
          sourceEventKey: sourceEventKey,
          actorUserId: _actorId,
          priority: NotificationPriority.normal,
          kind: NotificationKind.commitmentEvent,
          title: title,
          body: body,
          actionUrl: '/#/view?id=$_beaconId',
          collapseKey: 'family|$_beaconId',
          recipients: [
            AttentionRecipientSnapshot(
              recipientId: _recipientId,
              reasons: reasons,
              role: role,
            ),
          ],
          beaconId: _beaconId,
        ),
      ),
    );

    Future<AttentionChannelDecision> claim() async {
      final claimed = await AttentionChannelDeliveryRepository(database)
          .claimDue(
            workerId: 'w',
            now: DateTime.timestamp().add(const Duration(days: 1)),
            limit: 10,
          );
      expect(claimed, hasLength(1));
      return claimed.single.decision;
    }

    // Read through dynamic so a missing field is a runtime failure of the
    // behaviour, not a compile error; the casts pin the API shape
    // (String key, JSON map payload).
    String keyOf(AttentionChannelDecision d) =>
        (d as dynamic).presentationKey as String;
    Map<String, Object?> payloadOf(AttentionChannelDecision d) =>
        Map<String, Object?>.from((d as dynamic).presentationPayload as Map);

    test('a dispatched job decodes to a decision carrying the receipt key '
        'and payload with every existing field intact', () async {
      await record(
        eventType: AttentionEventType.helpOfferSubmitted,
        sourceEventKey: 'offer-1',
        title: 'Anna offered help',
        body: 'She can drive',
        reasons: const {AttentionRecipientReason.forwardRecipient},
        role: const AttentionRecipientRoleFacts(
          canReadBeaconContent: true,
          beaconId: _beaconId,
          actorUserId: _actorId,
          beaconTitle: 'Readable',
          excerpt: 'I can drive',
        ),
      );
      final receipt = (await writer.execute('''
SELECT id, dedup_key, presentation_key, presentation_payload::text
FROM public.notification_outbox
''')).single;
      final decision = await claim();

      expect(keyOf(decision), 'help_offer_submitted');
      expect(keyOf(decision), receipt[2]);
      expect(payloadOf(decision), jsonDecode(receipt[3]! as String));
      expect(payloadOf(decision)['excerpt'], 'I can drive');

      expect(decision.receiptId, receipt[0]);
      expect(decision.recipientId, _recipientId);
      expect(decision.kind, NotificationKind.commitmentEvent);
      expect(decision.priority, NotificationPriority.normal);
      expect(decision.title, 'Anna offered help');
      expect(decision.body, 'She can drive');
      expect(decision.actionUrl, '/#/view?id=$_beaconId');
      expect(decision.dedupKey, receipt[1]);
      expect(decision.actorUserId, _actorId);
      expect(decision.reason, 'forwardRecipient');
      expect(decision.beaconId, _beaconId);
      expect(decision.beaconKind, BeaconKind.request);
    });

    test('a payload with strings, ints, bools, null, nested maps and lists '
        'written by dispatch decodes equal to the receipt payload', () async {
      await record(
        eventType: AttentionEventType.forwardHelped,
        sourceEventKey: 'helped-1',
        title: 'Your forward helped',
        body: 'Vera helped',
        reasons: const {AttentionRecipientReason.pathForwarder},
        role: const AttentionRecipientRoleFacts(
          canReadBeaconContent: true,
          beaconId: _beaconId,
          actorUserId: _actorId,
          beaconTitle: 'Readable',
          forwardHelped: ForwardHelpedDetails(
            authorId: _actorId,
            helperId: null,
            path: [
              HelpPathNode.named(userId: _actorId, displayName: 'Anna Author'),
              HelpPathNode.anonymous(2),
            ],
          ),
        ),
      );
      final stored =
          jsonDecode(
                (await writer.execute('''
SELECT presentation_payload::text FROM public.notification_outbox
''')).single.single! as String,
              )
              as Map<String, dynamic>;
      // The fixture really holds every JSON value kind.
      final path = stored['path'] as List;
      expect(stored['personal'], isA<bool>());
      expect(stored['beaconTitle'], isA<String>());
      expect((path.last as Map)['anonymousCount'], 2);
      expect((path.last as Map)['userId'], isNull);
      expect((path.last as Map).containsKey('userId'), isTrue);
      expect(path.first, containsPair('userId', _actorId));

      final decision = await claim();

      expect(keyOf(decision), 'forward_helped');
      expect(payloadOf(decision), stored);
    });
  }, skip: skipReason);
}

const _actorId = 'Ucdpactor';
const _recipientId = 'Ucdprecipient';
const _beaconId = 'Bcdpcontent';

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
    (_actorId, 'cdp-actor-key'),
    (_recipientId, 'cdp-recipient-key'),
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
