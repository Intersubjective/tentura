@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

/// My Work's attention projection names the Request: every receipt it returns
/// (the latest optional one and each live obligation) carries the Request's
/// title and kind, and the title is withheld the moment the viewer may no
/// longer read the Request's content. The receipt and its count stay.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MY_WORK_REQUEST_TITLE_TEST_DB',
    defaultNamePrefix: 'tentura_test_mywork_title',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('my work attention Request identity', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository query;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      query = AttentionRepository(database);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_room_message,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {'id': _viewerId, 'key': '$_viewerId-key'},
      );
    });

    Future<MyWorkBeaconAttention> projection() async {
      final rows = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_beaconId},
      );
      expect(rows, hasLength(1));
      return rows.single;
    }

    // What the client receives: the receipt through the GraphQL mapper.
    Map<String, Object?> wire(AttentionReceipt receipt) =>
        QueryAttention.mapReceiptForTesting(receipt);

    test('a readable Request gives its title and kind on the latest receipt '
        'and on every live obligation', () async {
      await _beacon(writer, _beaconId, _viewerId, 'Fix the roof');
      await _receipt(writer, 'Nopt01', requiresAction: false);
      await _receipt(writer, 'Nobl01');
      await _receipt(writer, 'Nobl02');

      final row = await projection();

      expect(row.latestUnseen, isNotNull);
      expect(row.liveObligations, hasLength(2));
      for (final receipt in [row.latestUnseen!, ...row.liveObligations]) {
        final mapped = wire(receipt);
        expect(mapped['beaconTitle'], 'Fix the roof', reason: receipt.id);
        expect(mapped['beaconKind'], 0, reason: receipt.id);
      }
    }, skip: skipReason);

    test(
      'a Post gives its kind and opening words on a live obligation',
      () async {
        await _post(writer, _beaconId, _viewerId);
        await _receipt(writer, 'Nobl04');

        final row = await projection();

        final mapped = wire(row.liveObligations.single);
        expect(mapped['beaconKind'], 1);
        expect(mapped['postRootExcerpt'], 'Need a ladder');
      },
      skip: skipReason,
    );

    test('losing read access withholds the title but leaves the same '
        'receipts and count', () async {
      await _beacon(writer, _beaconId, _viewerId, 'Fix the roof');
      await _receipt(writer, 'Nopt03', requiresAction: false);
      await _receipt(writer, 'Nobl03');

      final before = await projection();
      expect(wire(before.latestUnseen!)['beaconTitle'], 'Fix the roof');
      expect(
        wire(before.liveObligations.single)['beaconTitle'],
        'Fix the roof',
      );

      Future<bool> canRead() async {
        final r = await writer.execute(
          Sql.named('SELECT public.beacon_can_read_content(@b, @v)'),
          parameters: {'b': _beaconId, 'v': _viewerId},
        );
        return r.single.single! as bool;
      }

      expect(await canRead(), isTrue, reason: 'readable to start with');

      // The Request is deleted: the only state where a receipt is still
      // served (tombstone policy) while its content is not readable.
      await writer.execute(
        Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @id'),
        parameters: {'id': _beaconId},
      );
      await writer.execute(
        "UPDATE public.notification_outbox SET access_policy = 'beacon_tombstone'",
      );

      expect(
        await canRead(),
        isFalse,
        reason: 'the projection must be run with content access denied',
      );

      final after = await projection();

      expect(after.unseenCount, before.unseenCount);
      expect(after.latestUnseen?.id, before.latestUnseen?.id);
      expect(
        [for (final r in after.liveObligations) r.id],
        [
          for (final r in before.liveObligations) r.id,
        ],
      );
      for (final receipt in [after.latestUnseen!, ...after.liveObligations]) {
        final mapped = wire(receipt);
        expect(mapped.containsKey('beaconTitle'), isTrue);
        expect(mapped['beaconTitle'], isNull, reason: receipt.id);
      }
    }, skip: skipReason);
  });
}

const _viewerId = 'Umwviewer001';
const _beaconId = 'Bmwbeacon0001';

Future<void> _beacon(
  Connection writer,
  String id,
  String authorId,
  String title, {
  int status = 0,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @author, @title, 'body', @status)
'''),
  parameters: {'id': id, 'author': authorId, 'title': title, 'status': status},
);

Future<void> _post(Connection writer, String id, String authorId) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES (@id, @author, '', '', 0, 1, 1, false, now())
'''),
    parameters: {'id': id, 'author': authorId},
  );
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body) '
      "VALUES ('Rmwroot00001', @id, @author, 'Need a ladder')",
    ),
    parameters: {'id': id, 'author': authorId},
  );
  await writer.execute(
    Sql.named(
      "UPDATE public.beacon SET post_root_message_id = 'Rmwroot00001' "
      'WHERE id = @id',
    ),
    parameters: {'id': id},
  );
}

Future<void> _receipt(
  Connection writer,
  String id, {
  bool requiresAction = true,
  String accessPolicy = 'beacon_content',
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
  @id, @viewer, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedup,
  CAST('2026-07-16T12:00:00Z' AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', @presentationKey, CAST(@payload AS jsonb),
  'standard', @accessPolicy,
  @requiresAction, @threadKey
)
'''),
  parameters: {
    'id': id,
    'viewer': _viewerId,
    'accessPolicy': accessPolicy,
    'dedup': 'dedup-$id',
    'beaconId': _beaconId,
    'sourceEventKey': 'source-$id',
    'presentationKey': requiresAction ? 'offer_declined' : 'deadline_changed',
    'payload': jsonEncode({
      'eventType': requiresAction ? 'offerDeclined' : 'deadlineChanged',
      'beaconId': _beaconId,
    }),
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$_viewerId' : null,
  },
);
