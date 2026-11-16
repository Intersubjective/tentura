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

/// A notice about one Request that names a linked Request (hierarchy notices)
/// carries that linked Request's current title, but only while the viewer may
/// read the linked Request. Each Request is gated on its own.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_RELATED_TITLE_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_rel_title',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attention receipt related Request title', () {
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
      for (final id in [_viewerId, _otherId]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    Future<AttentionReceipt> single(AttentionSurface surface) async {
      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: surface,
      );
      expect(feed.page.items, hasLength(1));
      return feed.page.items.single;
    }

    // What the client receives: the repository's receipt through the GraphQL
    // mapper. The key must be present (null when the title is withheld).
    String? relatedTitle(AttentionReceipt r) {
      final mapped = QueryAttention.mapReceiptForTesting(r);
      expect(mapped, contains('relatedBeaconTitle'));
      return mapped['relatedBeaconTitle'] as String?;
    }

    test('a readable related Request gives its title, trimmed', () async {
      await _beacon(writer, _ownId, _viewerId, 'Fix the fence');
      await _beacon(writer, _relId, _viewerId, '  Fix roof  ');
      await _receipt(writer, 'Nrel01', _ownId, related: _relId);

      final item = await single(AttentionSurface.myWork);

      expect(item.beaconTitle, 'Fix the fence');
      expect(relatedTitle(item), 'Fix roof');
    }, skip: skipReason);

    test('an unreadable related Request gives no title while the own Request '
        'keeps its title', () async {
      await _beacon(writer, _ownId, _viewerId, 'Fix the fence');
      await _beacon(writer, _relId, _otherId, 'Secret plan');
      await _receipt(writer, 'Nrel02', _ownId, related: _relId);

      final item = await single(AttentionSurface.myWork);

      expect(item.beaconTitle, 'Fix the fence');
      expect(relatedTitle(item), isNull);
    }, skip: skipReason);

    test('a readable related Request is named even when the own Request is '
        'unreadable', () async {
      // A receipt for an unreadable Request is dropped by the feed's access
      // filter unless its tombstone is readable, so the own Request is a
      // deleted one the viewer authored: content unreadable (beaconTitle
      // null), tombstone readable (row served). R is readable on its own.
      await _beacon(writer, _ownId, _viewerId, 'Hidden own', status: 2);
      await _beacon(writer, _relId, _viewerId, 'Fix roof');
      await _receipt(
        writer,
        'Nrel03',
        _ownId,
        related: _relId,
        accessPolicy: 'beacon_tombstone',
      );

      final item = await single(AttentionSurface.myWork);

      expect(item.beaconTitle, isNull);
      expect(relatedTitle(item), 'Fix roof');
    }, skip: skipReason);

    for (final blank in ['', '   ']) {
      test('a blank related title ("$blank") is served as null', () async {
        await _beacon(writer, _ownId, _viewerId, 'Fix the fence');
        await _beacon(writer, _relId, _viewerId, blank);
        await _receipt(writer, 'Nrel09', _ownId, related: _relId);

        final item = await single(AttentionSurface.myWork);

        expect(item.beaconTitle, 'Fix the fence');
        expect(relatedTitle(item), isNull);
      }, skip: skipReason);
    }

    test('a receipt without a related Request has no related title', () async {
      await _beacon(writer, _ownId, _viewerId, 'Fix the fence');
      await _receipt(writer, 'Nrel04', _ownId);

      final item = await single(AttentionSurface.myWork);

      expect(item.beaconTitle, 'Fix the fence');
      expect(relatedTitle(item), isNull);
    }, skip: skipReason);

    test(
      'a related id with no Request row is served without a title',
      () async {
        await _beacon(writer, _ownId, _viewerId, 'Fix the fence');
        await _receipt(writer, 'Nrel05', _ownId, related: 'Bnosuchbeacon');

        final item = await single(AttentionSurface.myWork);

        expect(item.beaconTitle, 'Fix the fence');
        expect(relatedTitle(item), isNull);
      },
      skip: skipReason,
    );

    test('the related title is read at feed time, not at write time', () async {
      await _beacon(writer, _ownId, _viewerId, 'Fix the fence');
      await _beacon(writer, _relId, _viewerId, 'Old roof');
      await _receipt(writer, 'Nrel06', _ownId, related: _relId);
      await writer.execute(
        Sql.named("UPDATE public.beacon SET title = 'New roof' WHERE id = @id"),
        parameters: {'id': _relId},
      );

      final item = await single(AttentionSurface.myWork);

      expect(relatedTitle(item), 'New roof');
    }, skip: skipReason);

    test('losing read access after the receipt was written hides the related '
        'title', () async {
      await _beacon(writer, _ownId, _viewerId, 'Fix the fence');
      await _beacon(writer, _relId, _viewerId, 'Fix roof');
      await _receipt(writer, 'Nrel07', _ownId, related: _relId);
      expect(relatedTitle(await single(AttentionSurface.myWork)), 'Fix roof');

      await writer.execute(
        Sql.named('UPDATE public.beacon SET user_id = @u WHERE id = @id'),
        parameters: {'u': _otherId, 'id': _relId},
      );

      final item = await single(AttentionSurface.myWork);
      expect(relatedTitle(item), isNull);
    }, skip: skipReason);

    test('a notice in a grouped Activity row names the related Request by '
        'the same rule', () async {
      // A Post groups its optional receipts into one Activity row.
      await _post(writer, _ownId, _viewerId);
      await _beacon(writer, _relId, _viewerId, 'Fix roof');
      await _receipt(
        writer,
        'Nrel08',
        _ownId,
        related: _relId,
        requiresAction: false,
      );

      var item = await single(AttentionSurface.activity);
      expect(item.eventsPreview, isNotEmpty);
      expect(
        [for (final e in item.eventsPreview) relatedTitle(e)],
        everyElement('Fix roof'),
      );

      await writer.execute(
        Sql.named('UPDATE public.beacon SET user_id = @u WHERE id = @id'),
        parameters: {'u': _otherId, 'id': _relId},
      );
      item = await single(AttentionSurface.activity);
      expect(item.eventsPreview, isNotEmpty);
      for (final e in item.eventsPreview) {
        expect(relatedTitle(e), isNull);
      }
    }, skip: skipReason);

    test('an unreadable related Request is withheld from a grouped Activity '
        'row from the first read', () async {
      await _post(writer, _ownId, _viewerId);
      await _beacon(writer, _relId, _otherId, 'Secret plan');
      await _receipt(
        writer,
        'Nrel10',
        _ownId,
        related: _relId,
        requiresAction: false,
      );

      final item = await single(AttentionSurface.activity);

      expect(item.eventsPreview, isNotEmpty);
      for (final e in item.eventsPreview) {
        expect(relatedTitle(e), isNull);
      }
    }, skip: skipReason);
  });
}

const _viewerId = 'Urelviewer01';
const _otherId = 'Urelother001';
const _ownId = 'Brelown00001';
const _relId = 'Brelrel00001';

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
      "INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body) "
      "VALUES ('Rrelroot0001', @id, @author, 'A post')",
    ),
    parameters: {'id': id, 'author': authorId},
  );
  await writer.execute(
    Sql.named(
      "UPDATE public.beacon SET post_root_message_id = 'Rrelroot0001' "
      'WHERE id = @id',
    ),
    parameters: {'id': id},
  );
}

Future<void> _receipt(
  Connection writer,
  String id,
  String beaconId, {
  String? related,
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
    'presentationKey': 'beacon_hierarchy_status_changed',
    'viewer': _viewerId,
    'accessPolicy': accessPolicy,
    'dedup': 'dedup-$id',
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'payload': jsonEncode({
      'eventType': 'beaconHierarchyStatusChanged',
      'beaconId': beaconId,
      'direction': 'child',
      'relatedBeaconId': ?related,
    }),
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$_viewerId' : null,
  },
);
