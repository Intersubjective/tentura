@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// U08 — the clear command's storage guarantees.
///
/// This group holds the two refusals the schema itself owes us. They are
/// asserted *by constraint name*, because a test that merely observes "the
/// write failed" would keep passing if the failure moved to some unrelated
/// constraint.
///
/// The FK case is carried in from U04's verify: U08 is the first writer of
/// `cleared_by_operation_id`, and until now nothing proved the FK refuses an
/// operation id that does not exist.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U08_CLEAR_TEST_DB',
    defaultNamePrefix: 'tentura_test_u08_clear',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('clear-state constraints', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await _resetFixtures(writer);
    });

    test(
      'notification_outbox__cleared_by_operation_fkey rejects an unknown '
      'operation id',
      () async {
        await _insertReceipt(writer, id: 'Nu08fkey', beaconId: _beaconId);

        await expectLater(
          writer.execute(
            Sql.named('''
UPDATE public.notification_outbox
   SET cleared_at = now(),
       clear_reason = 'explicit',
       cleared_by_operation_id = @operationId
 WHERE id = 'Nu08fkey'
'''),
            parameters: {'operationId': 'OPu08doesnotexist'},
          ),
          throwsA(
            isA<ServerException>().having(
              (error) => error.constraintName,
              'constraintName',
              'notification_outbox__cleared_by_operation_fkey',
            ),
          ),
        );

        final after = await writer.execute(
          "SELECT cleared_at FROM public.notification_outbox WHERE id = 'Nu08fkey'",
        );
        expect(after.first.first, isNull);
      },
    );

    test(
      'an obligation cannot be cleared: '
      'notification_outbox__clear_optional_only_chk is the catcher',
      () async {
        // The eligible predicate (`NOT requires_action AND cleared_at IS NULL`)
        // is what keeps obligations out of every token this unit issues. This
        // test is the second line: if that predicate ever regresses, the write
        // still has to be refused, and by this constraint specifically.
        await _insertReceipt(
          writer,
          id: 'Nu08oblig',
          beaconId: _beaconId,
          requiresAction: true,
        );
        await _insertOperation(writer, id: 'OPu08oblig');

        await expectLater(
          writer.execute('''
UPDATE public.notification_outbox
   SET cleared_at = now(),
       clear_reason = 'explicit',
       cleared_by_operation_id = 'OPu08oblig'
 WHERE id = 'Nu08oblig'
'''),
          throwsA(
            isA<ServerException>().having(
              (error) => error.constraintName,
              'constraintName',
              'notification_outbox__clear_optional_only_chk',
            ),
          ),
        );
      },
    );
  }, skip: skipReason);
}

const _viewerId = 'Uu08clear01';
const _authorId = 'Uu08clear02';
const _strangerId = 'Uu08clear03';
const _beaconId = 'Bu08clearown';
const _forwardedBeaconId = 'Bu08clearfwd';

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.user_block,
  public.beacon_forward_edge,
  public.attention_clear_operation,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_viewerId, _authorId, _strangerId]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES
  (@ownedId, @viewerId, 'Owned', 'Owned request', 0),
  (@forwardedId, @authorId, 'Forwarded', 'Forwarded request', 0)
'''),
    parameters: {
      'ownedId': _beaconId,
      'forwardedId': _forwardedBeaconId,
      'viewerId': _viewerId,
      'authorId': _authorId,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fu08clear01', @beaconId, @senderId, @recipientId)
'''),
    parameters: {
      'beaconId': _forwardedBeaconId,
      'senderId': _authorId,
      'recipientId': _viewerId,
    },
  );
}

Future<void> _insertOperation(
  Connection writer, {
  required String id,
  String accountId = _viewerId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.attention_clear_operation (id, account_id, surface, status)
VALUES (@id, @accountId, 'explicit', 'complete')
'''),
  parameters: {'id': id, 'accountId': accountId},
);

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  String accountId = _viewerId,
  String createdAt = '2026-09-16T10:00:00Z',
  bool requiresAction = false,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  @requiresAction, @threadKey
)
'''),
  parameters: {
    'id': id,
    'accountId': accountId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$accountId' : null,
  },
);
