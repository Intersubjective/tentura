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
import 'package:tentura_server/domain/entity/help_path_node.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

import '../../support/disposable_pg_target.dart';

/// Every channel job carries the presentation identity of the receipt it
/// notifies about: the same key and the same per-recipient payload that the
/// recipient's in-app receipt stores.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CHANNEL_JOB_PRESENTATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_channel_job_presentation',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('channel job presentation identity', () {
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
        Logger('channel-job-presentation-test'),
      );
      unitOfWork = MutatingUnitOfWork(database);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() => _resetFixtures(writer));

    Future<void> record(
      String sourceEventKey, {
      AttentionEventType eventType = AttentionEventType.relayReceived,
      NotificationKind kind = NotificationKind.newRelay,
      List<String> recipients = const [_recipientId],
      String title = 'Forwarded Request',
      String? excerpt,
      Map<String, String> excerptFor = const {},
      ForwardHelpedDetails? forwardHelped,
      Set<AttentionRecipientReason> reasons = const {
        AttentionRecipientReason.forwardRecipient,
      },
    }) => unitOfWork.run(
      actorUserId: _actorId,
      action: () => dispatch.record(
        AttentionDispatchIntent(
          eventType: eventType,
          sourceEventKey: sourceEventKey,
          actorUserId: _actorId,
          priority: NotificationPriority.normal,
          kind: kind,
          title: title,
          body: 'Body of $sourceEventKey',
          actionUrl: '/#/view?id=$_beaconId',
          collapseKey: 'family|$_beaconId',
          recipients: [
            for (final id in recipients)
              AttentionRecipientSnapshot(
                recipientId: id,
                reasons: reasons,
                role: AttentionRecipientRoleFacts(
                  canReadBeaconContent: true,
                  beaconId: _beaconId,
                  actorUserId: _actorId,
                  beaconTitle: 'Readable',
                  excerpt: excerptFor[id] ?? excerpt,
                  forwardHelped: forwardHelped,
                ),
              ),
          ],
          beaconId: _beaconId,
        ),
      ),
    );

    test('a help offer job carries the help_offer_submitted key, the '
        'receipt payload and the intent copy', () async {
      await record(
        'offer-1',
        eventType: AttentionEventType.helpOfferSubmitted,
        kind: NotificationKind.commitmentEvent,
        title: 'Anna offered help',
        excerpt: 'I can drive',
      );

      final jobs = await _jobs(writer);
      expect(jobs, hasLength(1));
      final receipt = await _receiptOf(writer, 'offer-1', _recipientId);
      expect(receipt['presentation_key'], 'help_offer_submitted');
      expect(jobs.single['receipt_id'], receipt['id']);
      final payload = jobs.single['payload'] as Map<String, dynamic>;
      expect(payload['presentationKey'], 'help_offer_submitted');
      expect(payload['presentationPayload'], isA<Map<String, dynamic>>());
      expect(payload['presentationPayload'], receipt['presentation_payload']);
      expect(_presentation(payload)['excerpt'], 'I can drive');
      expect(payload['title'], 'Anna offered help');
      expect(payload['body'], 'Body of offer-1');
    });

    test('a room message to two members writes one job each with '
        'room_message_posted and that member own payload', () async {
      await record(
        'message-1',
        eventType: AttentionEventType.roomMessagePosted,
        kind: NotificationKind.roomActivityLowPriority,
        recipients: [_recipientId, _secondId],
        excerptFor: {
          _recipientId: 'First member words',
          _secondId: 'Second member words',
        },
      );

      final jobs = await _jobs(writer);
      expect(jobs, hasLength(2));
      expect({for (final job in jobs) job['account_id']}, {
        _recipientId,
        _secondId,
      });
      for (final job in jobs) {
        final receipt = await _receiptOf(
          writer,
          'message-1',
          job['account_id']! as String,
        );
        expect(job['receipt_id'], receipt['id']);
        final payload = job['payload'] as Map<String, dynamic>;
        expect(payload['presentationKey'], 'room_message_posted');
        expect(payload['presentationPayload'], isA<Map<String, dynamic>>());
        expect(payload['presentationPayload'], receipt['presentation_payload']);
        expect(
          _presentation(payload)['excerpt'],
          job['account_id'] == _recipientId
              ? 'First member words'
              : 'Second member words',
        );
        expect(payload['title'], 'Forwarded Request');
        expect(payload['body'], 'Body of message-1');
      }
    });

    test('a collapsed pending job carries the key and payload of the newest '
        'event, not the first', () async {
      await record(
        'first',
        eventType: AttentionEventType.helpOfferSubmitted,
        kind: NotificationKind.commitmentEvent,
        excerpt: 'first words',
      );
      await record(
        'second',
        eventType: AttentionEventType.roomMessagePosted,
        kind: NotificationKind.roomActivityLowPriority,
        excerpt: 'second words',
      );

      final first = await _receiptOf(writer, 'first', _recipientId);
      final second = await _receiptOf(writer, 'second', _recipientId);
      expect(first['presentation_key'], 'help_offer_submitted');
      expect(second['presentation_key'], 'room_message_posted');

      final jobs = await _jobs(writer);
      expect(jobs, hasLength(1));
      expect(jobs.single['receipt_id'], second['id']);
      final payload = jobs.single['payload'] as Map<String, dynamic>;
      expect(payload['presentationKey'], 'room_message_posted');
      expect(payload['presentationPayload'], second['presentation_payload']);
      expect(_presentation(payload)['excerpt'], 'second words');
    });

    test('a forward helped job carries its key and still decodes to forward '
        'helped content when claimed', () async {
      await record(
        'helped-1',
        eventType: AttentionEventType.forwardHelped,
        kind: NotificationKind.commitmentEvent,
        reasons: const {AttentionRecipientReason.pathForwarder},
        forwardHelped: const ForwardHelpedDetails(
          authorId: _actorId,
          helperId: _secondId,
          path: [
            HelpPathNode.named(userId: _actorId, displayName: 'Anna Author'),
            HelpPathNode.named(userId: _recipientId, displayName: 'Boris'),
            HelpPathNode.named(userId: _secondId, displayName: 'Vera'),
          ],
        ),
      );

      final jobs = await _jobs(writer);
      expect(jobs, hasLength(1));
      final receipt = await _receiptOf(writer, 'helped-1', _recipientId);
      expect(jobs.single['receipt_id'], receipt['id']);
      final payload = jobs.single['payload'] as Map<String, dynamic>;
      expect(payload['presentationKey'], 'forward_helped');
      expect(payload['presentationPayload'], receipt['presentation_payload']);

      expect(payload['title'], 'Forwarded Request');
      expect(payload['body'], 'Body of helped-1');

      final claimed = await AttentionChannelDeliveryRepository(database)
          .claimDue(
            workerId: 'w',
            now: DateTime.timestamp().add(const Duration(days: 1)),
            limit: 10,
          );
      final content = claimed.single.decision.forwardHelped;
      final stored = receipt['presentation_payload'] as Map<String, dynamic>;
      expect(content, isNotNull);
      expect(content!.beaconTitle, stored['beaconTitle']);
      expect(content.beaconTitle, isNotEmpty);
      expect(
        [for (final node in content.path) node.userId],
        [for (final node in stored['path'] as List) (node as Map)['userId']],
      );
      expect(content.path, hasLength(3));
    });
  }, skip: skipReason);
}

const _actorId = 'Ucjpactor';
const _recipientId = 'Ucjprecipient';
const _secondId = 'Ucjpsecond';
const _beaconId = 'Bcjpcontent';

Future<List<Map<String, dynamic>>> _jobs(Connection writer) async {
  final rows = await writer.execute('''
SELECT account_id, receipt_id, payload
FROM public.attention_channel_delivery ORDER BY created_at, id
''');
  return [
    for (final row in rows)
      {
        'account_id': row[0],
        'receipt_id': row[1],
        'payload': jsonDecode(jsonEncode(row[2])) as Map<String, dynamic>,
      },
  ];
}

Future<Map<String, dynamic>> _receiptOf(
  Connection writer,
  String sourceEventKey,
  String accountId,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT id, presentation_key, presentation_payload
FROM public.notification_outbox
WHERE account_id = @a AND source_event_key = @k
'''),
    parameters: {'a': accountId, 'k': sourceEventKey},
  );
  final row = rows.single;
  return {
    'id': row[0],
    'presentation_key': row[1],
    'presentation_payload': jsonDecode(jsonEncode(row[2])),
  };
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
    (_actorId, 'cjp-actor-key'),
    (_recipientId, 'cjp-recipient-key'),
    (_secondId, 'cjp-second-key'),
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

Map<String, dynamic> _presentation(Map<String, dynamic> jobPayload) =>
    jobPayload['presentationPayload']! as Map<String, dynamic>;
