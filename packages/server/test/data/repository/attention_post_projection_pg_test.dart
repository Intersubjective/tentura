@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

import '../../support/disposable_pg_target.dart';

/// A live obligation puts its Request or Post in the viewer's responsibility
/// scope, so it is read as a plain My Work receipt; a Post's optional receipts
/// surface on Activity as one grouped row per Post. Both read paths must carry
/// the Post fields.
///
/// Receipt rows describe the beacon they are about. For a Post (a `kind = 1`
/// beacon with no title) that description lives on its root message, so the
/// attention projection has to carry the beacon kind, the root excerpt and the
/// first root image; a Request keeps today's shape and gets no Post fields.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_POST_PROJECTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_post_proj',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attention receipt Post projection', () {
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
  public.beacon_room_message_attachment,
  public.beacon_room_message,
  public.notification_outbox,
  public.beacon,
  public.image,
  public."user"
CASCADE
''');
      for (final id in [_viewerId, _authorId]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    test(
      'a Post receipt on My Work carries kind 1, the root excerpt and image id',
      () async {
        await _insertPost(writer, withImages: true);
        await _insertReceipt(
          writer,
          id: 'Nppost01',
          beaconId: _postId,
          requiresAction: true,
        );

        final item = await _singleReceipt(
          query,
          surface: AttentionSurface.myWork,
        );

        expect(item.beaconKind, BeaconKind.post);
        expect(item.postRootExcerpt, _rootBody.substring(0, 140));
        expect(item.postRootImageId, _firstImageId);
      },
      skip: skipReason,
    );

    test('the root excerpt is cut at 140 characters', () async {
      await _insertPost(writer);
      await _insertReceipt(
        writer,
        id: 'Nppost02',
        beaconId: _postId,
        requiresAction: true,
      );

      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.myWork,
      );

      expect(
        _rootBody.length,
        greaterThan(140),
        reason: 'fixture precondition',
      );
      expect(item.postRootExcerpt, hasLength(140));
      expect(item.postRootExcerpt, _rootBody.substring(0, 140));
    }, skip: skipReason);

    test('a Post root without images has an excerpt and no image id', () async {
      await _insertPost(writer, rootBody: 'Short note');
      await _insertReceipt(
        writer,
        id: 'Nppost03',
        beaconId: _postId,
        requiresAction: true,
      );

      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.myWork,
      );

      expect(item.beaconKind, BeaconKind.post);
      expect(item.postRootExcerpt, 'Short note');
      expect(item.postRootImageId, isNull);
    }, skip: skipReason);

    test('the root image is the first image, skipping files', () async {
      await _insertPost(writer, withImages: true);
      await _insertReceipt(
        writer,
        id: 'Nppost04',
        beaconId: _postId,
        requiresAction: true,
      );

      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.myWork,
      );

      expect(
        item.postRootImageId,
        _firstImageId,
        reason:
            'position 0 is a file and a later image sits at position 2; the '
            'first image attachment by position is the one at position 1',
      );
      expect(item.postRootImageId, isNot(_secondImageId));
    }, skip: skipReason);

    test(
      'attachments of other room messages never become the root image',
      () async {
        await _insertPost(writer, rootBody: 'Root without images');
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('Rpostprojreply', @beaconId, @authorId, 'A reply with a picture')
'''),
          parameters: {'beaconId': _postId, 'authorId': _authorId},
        );
        await _insertImageAttachment(
          writer,
          id: 'Apostprojrepl',
          messageId: 'Rpostprojreply',
          imageId: _secondImageId,
          position: 0,
        );
        await _insertReceipt(
          writer,
          id: 'Nppost05',
          beaconId: _postId,
          requiresAction: true,
        );

        final item = await _singleReceipt(
          query,
          surface: AttentionSurface.myWork,
        );

        expect(item.postRootExcerpt, 'Root without images');
        expect(item.postRootImageId, isNull);
      },
      skip: skipReason,
    );

    test(
      'a Post receipt on the grouped Activity row carries kind 1, the root '
      'excerpt and image id',
      () async {
        await _insertPost(writer, withImages: true);
        await _insertReceipt(writer, id: 'Nppost08', beaconId: _postId);

        final item = await _singleReceipt(
          query,
          surface: AttentionSurface.activity,
        );

        expect(item.itemKind, AttentionItemKind.requestActivity);
        expect(item.beaconKind, BeaconKind.post);
        expect(item.postRootExcerpt, _rootBody.substring(0, 140));
        expect(item.postRootImageId, _firstImageId);
      },
      skip: skipReason,
    );

    test('a Request receipt carries kind 0 and no Post fields', () async {
      await _insertRequest(writer);
      await _insertReceipt(writer, id: 'Nppost06', beaconId: _requestId);

      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.myWork,
      );

      expect(item.beaconKind, BeaconKind.request);
      expect(item.postRootExcerpt, isNull);
      expect(item.postRootImageId, isNull);
    }, skip: skipReason);

    test(
      'a Request receipt with every optional column set keeps each existing '
      'field and gains kind 0 with null Post fields',
      () async {
        await _insertRequest(writer);
        await _insertReceipt(
          writer,
          id: 'Nppost07',
          beaconId: _requestId,
          actorUserId: _authorId,
          targetEntityId: 'target-1',
          suppressionClass: 'noisy',
          preferenceClass: 'request_progress',
          seenAt: '2026-07-16T13:00:00Z',
          clearedAt: '2026-07-16T14:00:00Z',
          clearReason: 'explicit',
        );

        final item = await _singleReceipt(
          query,
          surface: AttentionSurface.myWork,
        );

        expect(_fieldsOf(item), {
          'id': 'Nppost07',
          'accountId': _viewerId,
          'category': NotificationCategory.coordination,
          'kind': NotificationKind.coordinationChanged,
          'priority': NotificationPriority.normal,
          'title': 'Title',
          'body': 'Body',
          'actionUrl': '/attention',
          'createdAt': DateTime.utc(2026, 7, 16, 12),
          'collapsedCount': 1,
          'suppressionClass': AttentionSuppressionClass.noisy,
          'accessPolicy': AttentionAccessPolicy.beaconContent,
          'presentationPayload': {'eventType': 'fixture'},
          'beaconId': _requestId,
          'coordinationItemId': null,
          'actorUserId': _authorId,
          'seenAt': DateTime.utc(2026, 7, 16, 13),
          'sourceEventKey': 'source-Nppost07',
          'destinationKind': AttentionDestinationKind.beacon,
          'targetEntityId': 'target-1',
          'presentationKey': 'request_status_changed',
          'inAppPreferenceClass': AttentionPreferenceClass.requestProgress,
          'requiresAction': false,
          'attentionThreadKey': null,
          'settlementKind': null,
          'settledAt': null,
          'settledByUserId': null,
          'settledByOccurrenceId': null,
          'clearedAt': DateTime.utc(2026, 7, 16, 14),
          'clearReason': 'explicit',
          'surface': AttentionSurface.myWork,
          'itemKind': AttentionItemKind.receipt,
          'forwardOutcome': null,
          'forwardCount': null,
          'digestCount': null,
          'eventTotal': null,
          'eventUnseenCount': null,
          'eventsPreview': isEmpty,
          'provenanceJson': null,
          'beaconAuthorId': null,
          'beaconAuthorName': null,
          'beaconAuthorImageId': null,
          'beaconImageId': null,
          'beaconEndAt': null,
          'beaconTitle': 'A plain Request',
          'allowsForward': null,
          'beaconKind': BeaconKind.request,
          'postRootExcerpt': null,
          'postRootImageId': null,
        });
      },
      skip: skipReason,
    );

    test(
      'a live obligation Request receipt keeps each existing field and gains '
      'kind 0 with null Post fields',
      () async {
        await _insertRequest(writer);
        await _insertReceipt(
          writer,
          id: 'Nppost09',
          beaconId: _requestId,
          requiresAction: true,
        );

        final item = await _singleReceipt(
          query,
          surface: AttentionSurface.myWork,
        );

        expect(_fieldsOf(item), {
          'id': 'Nppost09',
          'accountId': _viewerId,
          'category': NotificationCategory.coordination,
          'kind': NotificationKind.coordinationChanged,
          'priority': NotificationPriority.normal,
          'title': 'Title',
          'body': 'Body',
          'actionUrl': '/attention',
          'createdAt': DateTime.utc(2026, 7, 16, 12),
          'collapsedCount': 1,
          'suppressionClass': AttentionSuppressionClass.standard,
          'accessPolicy': AttentionAccessPolicy.beaconContent,
          'presentationPayload': {'eventType': 'fixture'},
          'beaconId': _requestId,
          'coordinationItemId': null,
          'actorUserId': null,
          'seenAt': null,
          'sourceEventKey': 'source-Nppost09',
          'destinationKind': AttentionDestinationKind.beacon,
          'targetEntityId': null,
          'presentationKey': 'request_status_changed',
          'inAppPreferenceClass': null,
          'requiresAction': true,
          'attentionThreadKey': 'v1|needsMe|Nppost09|$_viewerId',
          'settlementKind': null,
          'settledAt': null,
          'settledByUserId': null,
          'settledByOccurrenceId': null,
          'clearedAt': null,
          'clearReason': null,
          'surface': AttentionSurface.myWork,
          'itemKind': AttentionItemKind.receipt,
          'forwardOutcome': null,
          'forwardCount': null,
          'digestCount': null,
          'eventTotal': null,
          'eventUnseenCount': null,
          'eventsPreview': isEmpty,
          'provenanceJson': null,
          'beaconAuthorId': null,
          'beaconAuthorName': null,
          'beaconAuthorImageId': null,
          'beaconImageId': null,
          'beaconEndAt': null,
          'beaconTitle': 'A plain Request',
          'allowsForward': null,
          'beaconKind': BeaconKind.request,
          'postRootExcerpt': null,
          'postRootImageId': null,
        });
      },
      skip: skipReason,
    );

    test(
      'a settled obligation Request receipt keeps its settlement fields and '
      'gains kind 0 with null Post fields',
      () async {
        await _insertRequest(writer);
        await _insertReceipt(
          writer,
          id: 'Nppost10',
          beaconId: _requestId,
          requiresAction: true,
          settlementKind: 'resolved',
          settledAt: '2026-07-16T15:00:00Z',
          settledByUserId: _authorId,
        );

        final item = await _singleReceipt(
          query,
          surface: AttentionSurface.myWork,
        );

        expect(item.settlementKind, AttentionSettlementKind.resolved);
        expect(item.settledAt?.toUtc(), DateTime.utc(2026, 7, 16, 15));
        expect(item.settledByUserId, _authorId);
        expect(item.settledByOccurrenceId, isNull);
        expect(item.requiresAction, isTrue);
        expect(item.attentionThreadKey, 'v1|needsMe|Nppost10|$_viewerId');
        expect(item.clearedAt, isNull);
        expect(item.clearReason, isNull);
        expect(item.beaconKind, BeaconKind.request);
        expect(item.postRootExcerpt, isNull);
        expect(item.postRootImageId, isNull);
      },
      skip: skipReason,
    );
  });
}

const _viewerId = 'Uattnpostprj01';
const _authorId = 'Uattnpostprj02';
const _postId = 'Battnpostprj01';
const _requestId = 'Battnpostprj02';
const _rootMessageId = 'Rpostprojroot1';
const _firstImageId = '11111111-1111-4111-8111-111111111111';
const _secondImageId = '22222222-2222-4222-8222-222222222222';

/// Longer than 140 characters; the 141st character differs from a filler so a
/// wrong cut length is visible.
final _rootBody = '${List.filled(14, '0123456789').join()}TAIL-THAT-IS-CUT';

Future<AttentionReceipt> _singleReceipt(
  AttentionRepository query, {
  required AttentionSurface surface,
}) async {
  final feed = await query.attentionFeed(
    accountId: _viewerId,
    view: AttentionFeedView.all,
    surface: surface,
  );
  expect(feed.page.items, hasLength(1));
  return feed.page.items.single;
}

Future<void> _insertRequest(Connection writer) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @viewerId, 'A plain Request', 'Request body', 0)
'''),
  parameters: {'id': _requestId, 'viewerId': _viewerId},
);

/// A published Post authored by the viewer, with its root message set.
Future<void> _insertPost(
  Connection writer, {
  String? rootBody,
  bool withImages = false,
}) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES (@id, @viewerId, '', '', 0, 1, 1, false, now())
'''),
    parameters: {'id': _postId, 'viewerId': _viewerId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@messageId, @beaconId, @viewerId, @body)
'''),
    parameters: {
      'messageId': _rootMessageId,
      'beaconId': _postId,
      'viewerId': _viewerId,
      'body': rootBody ?? _rootBody,
    },
  );
  await writer.execute(
    Sql.named(
      'UPDATE public.beacon SET post_root_message_id = @messageId '
      'WHERE id = @id',
    ),
    parameters: {'messageId': _rootMessageId, 'id': _postId},
  );
  if (!withImages) return;
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, mime, file_name, file_url, "position")
VALUES ('Apostprojfile', @messageId, 2, 'application/pdf', 'a.pdf',
        'room/a.pdf', 0)
'''),
    parameters: {'messageId': _rootMessageId},
  );
  await _insertImageAttachment(
    writer,
    id: 'Apostprojimg1',
    messageId: _rootMessageId,
    imageId: _firstImageId,
    position: 1,
  );
  await _insertImageAttachment(
    writer,
    id: 'Apostprojimg2',
    messageId: _rootMessageId,
    imageId: _secondImageId,
    position: 2,
  );
}

Future<void> _insertImageAttachment(
  Connection writer, {
  required String id,
  required String messageId,
  required String imageId,
  required int position,
}) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.image (id, hash, height, width, author_id)
VALUES (CAST(@imageId AS uuid), 'hash', 10, 10, @authorId)
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {'imageId': imageId, 'authorId': _authorId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, image_id, mime, "position")
VALUES (@id, @messageId, 1, CAST(@imageId AS uuid), 'image/jpeg', @position)
'''),
    parameters: {
      'id': id,
      'messageId': messageId,
      'imageId': imageId,
      'position': position,
    },
  );
}

/// Every receipt field by name, so a snapshot comparison names the field that
/// moved. Timestamps are compared in UTC.
Map<String, Object?> _fieldsOf(AttentionReceipt r) => {
  'id': r.id,
  'accountId': r.accountId,
  'category': r.category,
  'kind': r.kind,
  'priority': r.priority,
  'title': r.title,
  'body': r.body,
  'actionUrl': r.actionUrl,
  'createdAt': r.createdAt.toUtc(),
  'collapsedCount': r.collapsedCount,
  'suppressionClass': r.suppressionClass,
  'accessPolicy': r.accessPolicy,
  'presentationPayload': r.presentationPayload,
  'beaconId': r.beaconId,
  'coordinationItemId': r.coordinationItemId,
  'actorUserId': r.actorUserId,
  'seenAt': r.seenAt?.toUtc(),
  'sourceEventKey': r.sourceEventKey,
  'destinationKind': r.destinationKind,
  'targetEntityId': r.targetEntityId,
  'presentationKey': r.presentationKey,
  'inAppPreferenceClass': r.inAppPreferenceClass,
  'requiresAction': r.requiresAction,
  'attentionThreadKey': r.attentionThreadKey,
  'settlementKind': r.settlementKind,
  'settledAt': r.settledAt?.toUtc(),
  'settledByUserId': r.settledByUserId,
  'settledByOccurrenceId': r.settledByOccurrenceId,
  'clearedAt': r.clearedAt?.toUtc(),
  'clearReason': r.clearReason,
  'surface': r.surface,
  'itemKind': r.itemKind,
  'forwardOutcome': r.forwardOutcome,
  'forwardCount': r.forwardCount,
  'digestCount': r.digestCount,
  'eventTotal': r.eventTotal,
  'eventUnseenCount': r.eventUnseenCount,
  'eventsPreview': r.eventsPreview,
  'provenanceJson': r.provenanceJson,
  'beaconAuthorId': r.beaconAuthorId,
  'beaconAuthorName': r.beaconAuthorName,
  'beaconAuthorImageId': r.beaconAuthorImageId,
  'beaconImageId': r.beaconImageId,
  'beaconEndAt': r.beaconEndAt?.toUtc(),
  'beaconTitle': r.beaconTitle,
  'allowsForward': r.allowsForward,
  'beaconKind': r.beaconKind,
  'postRootExcerpt': r.postRootExcerpt,
  'postRootImageId': r.postRootImageId,
};

/// A receipt for the viewer. `requiresAction` makes it a live obligation
/// (thread key included); the optional columns default to NULL.
Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  bool requiresAction = false,
  String suppressionClass = 'standard',
  String? actorUserId,
  String? targetEntityId,
  String? preferenceClass,
  String? seenAt,
  String? clearedAt,
  String? clearReason,
  String? settlementKind,
  String? settledAt,
  String? settledByUserId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  actor_user_id, target_entity_id, in_app_preference_class,
  seen_at, cleared_at, clear_reason,
  requires_action, attention_thread_key,
  settlement_kind, settled_at, settled_by_user_id
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST('2026-07-16T12:00:00Z' AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  @suppressionClass, 'beacon_content',
  @actorUserId, @targetEntityId, @preferenceClass,
  CAST(@seenAt AS timestamptz), CAST(@clearedAt AS timestamptz), @clearReason,
  @requiresAction, @threadKey,
  @settlementKind, CAST(@settledAt AS timestamptz), @settledByUserId
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'suppressionClass': suppressionClass,
    'actorUserId': actorUserId,
    'targetEntityId': targetEntityId,
    'preferenceClass': preferenceClass,
    'seenAt': seenAt,
    'clearedAt': clearedAt,
    'clearReason': clearReason,
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$_viewerId' : null,
    'settlementKind': settlementKind,
    'settledAt': settledAt,
    'settledByUserId': settledByUserId,
  },
);
