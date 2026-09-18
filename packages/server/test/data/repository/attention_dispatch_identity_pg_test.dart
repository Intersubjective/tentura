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

/// U05a — immutable in-app receipt identity.
///
/// Two properties are proven here by observation, never by reading the
/// dispatch SQL:
///
/// 1. **Immutability.** A later event sharing a collapse key must not rewrite
///    an existing receipt. Every mutable-looking column of the first receipt
///    is captured *before* the second dispatch and compared verbatim after.
/// 2. **Replay dedup survives.** Re-delivering the same `source_event_key`
///    still yields exactly one receipt — sequentially and concurrently. This
///    guard lives at the *occurrence* grain
///    (`attention_occurrence.source_event_key` UNIQUE plus the m0178
///    `notification_outbox__occurrence_account` UNIQUE index), not on the
///    collapse-keyed `notification_outbox__dedup` index that U05a makes
///    non-unique. The two concurrency tests exist so that the move of that
///    guarantee from one index to the other is explicit, not incidental.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U05A_IDENTITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_u05a_identity',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attention dispatch receipt identity', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionDispatchRepository dispatch;
    late MutatingUnitOfWork unitOfWork;

    setUpAll(() async {
      if (skipReason != false) return;
      // The concurrency cases deliberately open a second TenturaDb against
      // the same database: two connections is the whole point of the test.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      dispatch = AttentionDispatchRepository(
        database,
        Logger('attention-dispatch-identity-test'),
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

    test(
      'a second occurrence in the same collapse family adds a receipt '
      'instead of rewriting the first',
      () async {
        await unitOfWork.run(
          actorUserId: _actorId,
          action: () => dispatch.record(_intent(sourceEventKey: 'relay-1')),
        );
        final before = await _receipts(writer);
        expect(before, hasLength(1));
        final first = before.single;

        await unitOfWork.run(
          actorUserId: _actorId,
          action: () => dispatch.record(_intent(sourceEventKey: 'relay-2')),
        );

        final after = await _receipts(writer);
        expect(
          after,
          hasLength(2),
          reason: 'two distinct occurrences must produce two receipts',
        );

        final firstAfter = after.firstWhere((row) => row['id'] == first['id']);
        expect(
          firstAfter,
          first,
          reason: 'no column of an existing receipt may move after insert',
        );

        final second = after.firstWhere((row) => row['id'] != first['id']);
        expect(second['source_event_key'], 'relay-2');
        expect(second['occurrence_id'], isNot(first['occurrence_id']));
        expect(
          second['dedup_key'],
          first['dedup_key'],
          reason: 'the collapse family is unchanged; only identity is',
        );
        expect(
          {first['collapsed_count'], second['collapsed_count']},
          {1},
          reason: 'collapsed_count is no longer a write-time counter',
        );
      },
    );

    test(
      'replaying one source_event_key inserts exactly one receipt',
      () async {
        for (var i = 0; i < 3; i++) {
          await unitOfWork.run(
            actorUserId: _actorId,
            action: () => dispatch.record(_intent(sourceEventKey: 'relay-1')),
          );
        }
        expect(await _count(writer, 'public.attention_occurrence'), 1);
        expect(
          await _count(writer, 'public.attention_occurrence_recipient'),
          1,
        );
        expect(await _count(writer, 'public.notification_outbox'), 1);
        expect(await _count(writer, 'public.attention_channel_delivery'), 1);
      },
    );

    test(
      'two concurrent deliveries of one source_event_key insert once',
      () async {
        final rival = openDisposablePgDatabase(target);
        addTearDown(rival.close);
        final rivalDispatch = AttentionDispatchRepository(
          rival,
          Logger('attention-dispatch-identity-test-rival'),
        );
        final rivalUnitOfWork = MutatingUnitOfWork(rival);

        await Future.wait([
          unitOfWork.run(
            actorUserId: _actorId,
            action: () => dispatch.record(_intent(sourceEventKey: 'race-1')),
          ),
          rivalUnitOfWork.run(
            actorUserId: _actorId,
            action: () =>
                rivalDispatch.record(_intent(sourceEventKey: 'race-1')),
          ),
        ]);

        expect(await _count(writer, 'public.attention_occurrence'), 1);
        expect(await _count(writer, 'public.notification_outbox'), 1);
      },
    );

    test(
      'two concurrent occurrences in one collapse family both land',
      () async {
        final rival = openDisposablePgDatabase(target);
        addTearDown(rival.close);
        final rivalDispatch = AttentionDispatchRepository(
          rival,
          Logger('attention-dispatch-identity-test-rival'),
        );
        final rivalUnitOfWork = MutatingUnitOfWork(rival);

        await Future.wait([
          unitOfWork.run(
            actorUserId: _actorId,
            action: () => dispatch.record(_intent(sourceEventKey: 'par-1')),
          ),
          rivalUnitOfWork.run(
            actorUserId: _actorId,
            action: () =>
                rivalDispatch.record(_intent(sourceEventKey: 'par-2')),
          ),
        ]);

        expect(await _count(writer, 'public.notification_outbox'), 2);
      },
    );
  }, skip: skipReason);
}

const _actorId = 'Uu05aactor';
const _recipientId = 'Uu05arecipient';
const _beaconId = 'Bu05acontent';

AttentionDispatchIntent _intent({required String sourceEventKey}) =>
    AttentionDispatchIntent(
      eventType: AttentionEventType.relayReceived,
      sourceEventKey: sourceEventKey,
      actorUserId: _actorId,
      priority: NotificationPriority.normal,
      kind: NotificationKind.newRelay,
      title: 'Forwarded Request',
      body: 'A Request was forwarded to you',
      actionUrl: '/#/view?id=$_beaconId',
      collapseKey: 'relay|$_beaconId',
      recipients: const [
        AttentionRecipientSnapshot(
          recipientId: _recipientId,
          reasons: {AttentionRecipientReason.forwardRecipient},
          role: AttentionRecipientRoleFacts(
            canReadBeaconContent: true,
            beaconId: _beaconId,
            actorUserId: _actorId,
          ),
        ),
      ],
      beaconId: _beaconId,
    );

/// Every column a later event could plausibly rewrite, read as text so the
/// comparison is byte-for-byte rather than through a decoder.
Future<List<Map<String, Object?>>> _receipts(Connection writer) async {
  final rows = await writer.execute('''
SELECT id, created_at::text, requires_action, occurrence_id, source_event_key,
       dedup_key, collapsed_count, presentation_key,
       presentation_payload::text, title, body, action_url, category, kind,
       priority, destination_kind, target_entity_id, attention_thread_key,
       in_app_preference_class, suppression_class, access_policy
FROM public.notification_outbox
ORDER BY created_at, id
''');
  return [
    for (final row in rows) row.toColumnMap(),
  ];
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
    (_actorId, 'u05a-actor-key'),
    (_recipientId, 'u05a-recipient-key'),
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
