@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/use_case/attention_sweep_case.dart';

import '../../support/disposable_pg_target.dart';

/// A Post (`kind = 1`) reaches For You as one grouped row, never as a pinned
/// decision: its arrival receipt counts as a child of the group, the group is
/// positioned at its newest child, and clearing the row clears receipts only —
/// the viewer's inbox stance and room access stay as they were. A Request
/// keeps today's rules (pinned while unanswered, outcome rows dismissible).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_POST_GROUPING_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_post_group',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attention Post grouping', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository query;
    late AttentionSweepCase sweep;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      query = AttentionRepository(database);
      sweep = AttentionSweepCase(AttentionSweepRepository(database));
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.inbox_item,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.notification_beacon_mute,
  public.attention_clear_operation,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
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
      'a Post that only arrived is one grouped row that is not pinned',
      () async {
        await _forwardPost(writer);
        await _insertReceipt(
          writer,
          id: 'Npgarrive01',
          beaconId: _postId,
          presentationKey: 'relay_received',
          createdAt: _arrivalAt,
        );

        final items = await _activityItems(query);
        final row = items.single;

        expect(row.itemKind, AttentionItemKind.requestActivity);
        expect(row.beaconId, _postId);
        expect(row.eventTotal, 1);
        expect(row.eventUnseenCount, 1);
        expect(
          items.where((i) => i.itemKind == AttentionItemKind.forward),
          isEmpty,
          reason: 'a Post inbox item is never a pinned decision',
        );
        final summary = await query.surfaceSummary(accountId: _viewerId);
        expect(summary.forYouDot, isTrue);
      },
      skip: skipReason,
    );

    test(
      'a reply an hour after arrival positions the row at the reply',
      () async {
        await _forwardPost(writer);
        await _insertReceipt(
          writer,
          id: 'Npgarrive02',
          beaconId: _postId,
          presentationKey: 'relay_received',
          createdAt: _arrivalAt,
        );
        await _insertReceipt(
          writer,
          id: 'Npgreply02',
          beaconId: _postId,
          createdAt: _replyAt,
        );

        final row = (await _activityItems(query)).single;

        expect(row.itemKind, AttentionItemKind.requestActivity);
        expect(row.eventTotal, 2);
        expect(row.createdAt.toUtc(), _replyAt);
      },
      skip: skipReason,
    );

    test(
      'dismiss-all clears the Post row and its receipts but not the inbox '
      'stance or room access',
      () async {
        await _forwardPost(writer);
        await _insertParticipant(writer);
        await _insertReceipt(
          writer,
          id: 'Npgarrive03',
          beaconId: _postId,
          presentationKey: 'relay_received',
          createdAt: _arrivalAt,
        );
        await _insertReceipt(
          writer,
          id: 'Npgreply03',
          beaconId: _postId,
          createdAt: _replyAt,
        );

        final result = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPpostgroup03',
        );

        expect(result.failed, isEmpty);
        expect(result.status, AttentionClearStatus.complete);
        expect(
          result.appliedReceiptIds,
          unorderedEquals(['Npgarrive03', 'Npgreply03']),
        );
        expect(await _activityItems(query), isEmpty);
        final inbox = await writer.execute(
          Sql.named(
            'SELECT status, tombstone_dismissed_at FROM public.inbox_item '
            'WHERE user_id = @u AND beacon_id = @b',
          ),
          parameters: {'u': _viewerId, 'b': _postId},
        );
        expect(inbox.single[0], 0);
        expect(inbox.single[1], isNull);
        final access = await writer.execute(
          Sql.named(
            'SELECT role, room_access FROM public.beacon_participant '
            'WHERE user_id = @u AND beacon_id = @b',
          ),
          parameters: {'u': _viewerId, 'b': _postId},
        );
        expect(access.single[0], 6);
        expect(access.single[1], 3);
      },
      skip: skipReason,
    );

    test('a new mention after clearing brings the row back', () async {
      await _forwardPost(writer);
      await _insertReceipt(
        writer,
        id: 'Npgarrive04',
        beaconId: _postId,
        presentationKey: 'relay_received',
        createdAt: _arrivalAt,
      );
      await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPpostgroup04',
      );
      expect(await _activityItems(query), isEmpty);

      await _insertReceipt(
        writer,
        id: 'Npgmention04',
        beaconId: _postId,
        createdAt: _replyAt,
      );

      final row = (await _activityItems(query)).single;
      expect(row.itemKind, AttentionItemKind.requestActivity);
      expect(row.beaconId, _postId);
      expect(row.eventTotal, 1);
      expect(row.createdAt.toUtc(), _replyAt);
    }, skip: skipReason);

    test(
      'a Request forward still waits as a pinned decision that dismiss-all '
      'leaves alone',
      () async {
        await _forwardRequest(writer, status: 0);

        expect(
          (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
          isTrue,
          reason: 'an unanswered Request forward is a pinned decision',
        );

        final result = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPpostgroup05',
        );

        expect(result.appliedOutcomeBeaconIds, isEmpty);
        expect(result.failed, isEmpty);
        expect(await _tombstoneDismissedAt(writer, _requestId), isNull);
        expect(
          (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
          isTrue,
        );
      },
      skip: skipReason,
    );

    test(
      'a Request outcome row is dismissed by dismiss-all as before',
      () async {
        await _forwardRequest(writer, status: 2);

        final result = await sweep.dismissAll(
          accountId: _viewerId,
          operationId: 'OPpostgroup06',
        );

        expect(result.appliedOutcomeBeaconIds, [_requestId]);
        expect(result.failed, isEmpty);
        expect(await _tombstoneDismissedAt(writer, _requestId), isNotNull);
      },
      skip: skipReason,
    );

    group('mute', () {
      test(
        'a muted Post hides its arrival and reply rows from the list, the '
        'dot and the Dismiss all affordance',
        () async {
          await _forwardPost(writer);
          await _insertReceipt(
            writer,
            id: 'Npgarrmute1',
            beaconId: _postId,
            presentationKey: 'relay_received',
            createdAt: _arrivalAt,
          );
          await _insertReceipt(
            writer,
            id: 'Npgreplmute1',
            beaconId: _postId,
            createdAt: _replyAt,
          );
          await _mutePost(writer);

          expect(await _activityItems(query), isEmpty);
          final summary = await query.surfaceSummary(accountId: _viewerId);
          expect(
            summary.forYouDot,
            isFalse,
            reason: 'a muted Post lights no For You dot',
          );
          expect(
            summary.forYouSweepEligible,
            isFalse,
            reason: 'hidden rows are not something Dismiss all would clear',
          );

          final result = await sweep.dismissAll(
            accountId: _viewerId,
            operationId: 'OPpostmute01',
          );
          expect(result.failed, isEmpty);
          expect(
            result.appliedReceiptIds,
            isEmpty,
            reason: 'Dismiss all captures nothing from a muted Post',
          );
          expect(await _clearedReceiptIds(writer), isEmpty);
        },
        skip: skipReason,
      );

      test(
        'an indefinite mute and a mute that runs into the future both hide '
        'the Post rows',
        () async {
          await _forwardPost(writer);
          await _insertReceipt(
            writer,
            id: 'Npgarrmute2',
            beaconId: _postId,
            kind: NotificationKind.newRelay,
            presentationKey: 'relay_received',
            createdAt: _arrivalAt,
          );

          await _mutePost(writer, until: DateTime.now().toUtc().add(_aDay));
          expect(await _activityItems(query), isEmpty);

          await _mutePost(writer);
          expect(await _activityItems(query), isEmpty);
        },
        skip: skipReason,
      );

      test(
        'a mention on a muted Post still shows and is the only child counted',
        () async {
          await _forwardPost(writer);
          await _insertReceipt(
            writer,
            id: 'Npgarrmute3',
            beaconId: _postId,
            presentationKey: 'relay_received',
            createdAt: _arrivalAt,
          );
          await _insertReceipt(
            writer,
            id: 'Npgreplmute3',
            beaconId: _postId,
            createdAt: _replyAt,
          );
          await _insertReceipt(
            writer,
            id: 'Npgmentmute3',
            beaconId: _postId,
            kind: NotificationKind.roomMention,
            createdAt: _mentionAt,
          );
          await _mutePost(writer);

          final row = (await _activityItems(query)).single;

          expect(row.itemKind, AttentionItemKind.requestActivity);
          expect(row.beaconId, _postId);
          expect(row.eventTotal, 1);
          expect(
            row.eventUnseenCount,
            1,
            reason: 'muted children do not count as unseen either',
          );
          expect(row.createdAt.toUtc(), _mentionAt);
          expect(
            row.eventsPreview.map((e) => e.id),
            ['Npgmentmute3'],
            reason:
                'muted arrival and reply stay out of the expandable preview',
          );
          expect(
            (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
            isTrue,
          );
        },
        skip: skipReason,
      );

      test(
        'dismiss-all leaves hidden rows of a muted Post uncleared, and they '
        'return when the mute is lifted',
        () async {
          await _forwardPost(writer);
          await _insertReceipt(
            writer,
            id: 'Npgarrmute4',
            beaconId: _postId,
            kind: NotificationKind.newRelay,
            presentationKey: 'relay_received',
            createdAt: _arrivalAt,
          );
          await _insertReceipt(
            writer,
            id: 'Npgreplmute4',
            beaconId: _postId,
            kind: NotificationKind.roomActivityLowPriority,
            createdAt: _replyAt,
          );
          await _mutePost(writer);

          final result = await sweep.dismissAll(
            accountId: _viewerId,
            operationId: 'OPpostmute04',
          );

          expect(result.failed, isEmpty);
          expect(result.appliedReceiptIds, isEmpty);
          expect(
            await _clearedReceiptIds(writer),
            isEmpty,
            reason: 'a row the viewer could not see must not be cleared',
          );

          await writer.execute(
            'DELETE FROM public.notification_beacon_mute',
          );
          final row = (await _activityItems(query)).single;
          expect(row.beaconId, _postId);
          expect(row.eventTotal, 2);
        },
        skip: skipReason,
      );

      test(
        'dismiss-all on a muted Post clears only the mention it shows',
        () async {
          await _forwardPost(writer);
          await _insertReceipt(
            writer,
            id: 'Npgreplmute5',
            beaconId: _postId,
            kind: NotificationKind.roomActivityLowPriority,
            createdAt: _arrivalAt,
          );
          await _insertReceipt(
            writer,
            id: 'Npgmentmute5',
            beaconId: _postId,
            kind: NotificationKind.roomMention,
            createdAt: _replyAt,
          );
          await _mutePost(writer);

          final result = await sweep.dismissAll(
            accountId: _viewerId,
            operationId: 'OPpostmute05',
          );

          expect(result.failed, isEmpty);
          expect(result.appliedReceiptIds, ['Npgmentmute5']);
          expect(await _clearedReceiptIds(writer), ['Npgmentmute5']);
        },
        skip: skipReason,
      );

      test(
        'once the mute has expired the uncleared rows are visible again',
        () async {
          await _forwardPost(writer);
          await _insertReceipt(
            writer,
            id: 'Npgarrmute6',
            beaconId: _postId,
            kind: NotificationKind.newRelay,
            presentationKey: 'relay_received',
            createdAt: _arrivalAt,
          );
          await _insertReceipt(
            writer,
            id: 'Npgreplmute6',
            beaconId: _postId,
            kind: NotificationKind.roomActivityLowPriority,
            createdAt: _replyAt,
          );
          await _mutePost(writer, until: DateTime.now().toUtc().add(_aDay));
          expect(await _activityItems(query), isEmpty);

          await _mutePost(
            writer,
            until: DateTime.now().toUtc().subtract(_aDay),
          );

          final row = (await _activityItems(query)).single;
          expect(row.itemKind, AttentionItemKind.requestActivity);
          expect(row.beaconId, _postId);
          expect(row.eventTotal, 2);
          expect(row.createdAt.toUtc(), _replyAt);
          expect(
            (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
            isTrue,
          );
        },
        skip: skipReason,
      );

      test(
        'another account muting the Post does not hide the viewer rows',
        () async {
          await _forwardPost(writer);
          await _insertReceipt(
            writer,
            id: 'Npgarrmute7',
            beaconId: _postId,
            kind: NotificationKind.newRelay,
            presentationKey: 'relay_received',
            createdAt: _arrivalAt,
          );
          await _mutePost(writer, accountId: _authorId);

          final row = (await _activityItems(query)).single;
          expect(row.beaconId, _postId);
          expect(row.eventTotal, 1);
        },
        skip: skipReason,
      );

      test(
        'a muted Request still shows its rows exactly as without a mute',
        () async {
          await _forwardRequest(writer, status: 2);
          await _insertReceipt(
            writer,
            id: 'Nreqreplmute8',
            beaconId: _requestId,
            kind: NotificationKind.roomActivityLowPriority,
            createdAt: _replyAt,
          );
          final withoutMute = _rowSignatures(await _activityItems(query));
          expect(withoutMute, isNotEmpty);

          await _muteBeacon(writer, _requestId);
          final mutes = await writer.execute(
            Sql.named(
              'SELECT count(*) FROM public.notification_beacon_mute '
              'WHERE account_id = @a AND beacon_id = @b '
              'AND muted_until IS NULL',
            ),
            parameters: {'a': _viewerId, 'b': _requestId},
          );
          expect(mutes.single.first, 1, reason: 'the Request is muted');

          expect(
            _rowSignatures(await _activityItems(query)),
            withoutMute,
          );
          expect(
            (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
            isTrue,
          );
          final result = await sweep.dismissAll(
            accountId: _viewerId,
            operationId: 'OPpostmute08',
          );
          expect(result.appliedReceiptIds, ['Nreqreplmute8']);
          expect(await _clearedReceiptIds(writer), ['Nreqreplmute8']);
        },
        skip: skipReason,
      );
    });
  });
}

const _viewerId = 'Uattnpostgrp01';
const _authorId = 'Uattnpostgrp02';
const _postId = 'Battnpostgrp01';
const _requestId = 'Battnpostgrp02';

final _arrivalAt = DateTime.utc(2026, 7, 16, 10);
final _replyAt = DateTime.utc(2026, 7, 16, 11);
final _mentionAt = DateTime.utc(2026, 7, 16, 12);
const _aDay = Duration(days: 1);

Future<List<AttentionReceipt>> _activityItems(AttentionRepository query) async {
  final feed = await query.attentionFeed(
    accountId: _viewerId,
    view: AttentionFeedView.all,
    surface: AttentionSurface.activity,
  );
  return feed.page.items;
}

/// A published Post by the author, forwarded to the viewer: the forward edge
/// admits the viewer to read it and leaves the inbox item undecided.
Future<void> _forwardPost(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES (@id, @authorId, '', '', 0, 1, 1, false, now())
'''),
    parameters: {'id': _postId, 'authorId': _authorId},
  );
  await _forwardEdge(writer, beaconId: _postId);
  await _setInboxStatus(writer, beaconId: _postId, status: 0);
}

Future<void> _forwardRequest(Connection writer, {required int status}) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @authorId, 'A Request', 'Request body', 0)
'''),
    parameters: {'id': _requestId, 'authorId': _authorId},
  );
  await _forwardEdge(writer, beaconId: _requestId);
  await _setInboxStatus(writer, beaconId: _requestId, status: status);
}

Future<void> _forwardEdge(Connection writer, {required String beaconId}) =>
    writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@id, @beaconId, @senderId, @recipientId)
'''),
      parameters: {
        'id': 'F$beaconId',
        'beaconId': beaconId,
        'senderId': _authorId,
        'recipientId': _viewerId,
      },
    );

Future<void> _setInboxStatus(
  Connection writer, {
  required String beaconId,
  required int status,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@userId, @beaconId, @status, 1, now(), '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = EXCLUDED.status
'''),
  parameters: {'userId': _viewerId, 'beaconId': beaconId, 'status': status},
);

/// The viewer as an admitted addressee of the Post.
Future<void> _insertParticipant(Connection writer) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES (@beaconId, @userId, 6, 3)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET role = 6, room_access = 3
'''),
  parameters: {'beaconId': _postId, 'userId': _viewerId},
);

Future<Object?> _tombstoneDismissedAt(
  Connection writer,
  String beaconId,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT tombstone_dismissed_at FROM public.inbox_item '
      'WHERE user_id = @userId AND beacon_id = @beaconId',
    ),
    parameters: {'userId': _viewerId, 'beaconId': beaconId},
  );
  return rows.isEmpty ? null : rows.first.first;
}

/// The viewer's in-app mute of [beaconId]; `until == null` mutes indefinitely.
Future<void> _muteBeacon(
  Connection writer,
  String beaconId, {
  String? accountId,
  DateTime? until,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_beacon_mute (account_id, beacon_id, muted_until)
VALUES (@accountId, @beaconId, CAST(@until AS timestamptz))
ON CONFLICT (account_id, beacon_id)
DO UPDATE SET muted_until = EXCLUDED.muted_until
'''),
  parameters: {
    'accountId': accountId ?? _viewerId,
    'beaconId': beaconId,
    'until': until?.toIso8601String(),
  },
);

Future<void> _mutePost(
  Connection writer, {
  String? accountId,
  DateTime? until,
}) => _muteBeacon(writer, _postId, accountId: accountId, until: until);

List<String> _rowSignatures(List<AttentionReceipt> items) => [
  for (final i in items)
    '${i.itemKind}:${i.beaconId}:${i.eventTotal}:${i.eventUnseenCount}',
];

Future<List<String>> _clearedReceiptIds(Connection writer) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT id FROM public.notification_outbox '
      'WHERE account_id = @accountId AND cleared_at IS NOT NULL ORDER BY id',
    ),
    parameters: {'accountId': _viewerId},
  );
  return [for (final r in rows) r.first! as String];
}

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  required DateTime createdAt,
  NotificationKind kind = NotificationKind.coordinationChanged,
  String presentationKey = 'request_status_changed',
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'coordination', @kind, 'normal',
  'Title', 'Body', '/attention', @dedupKey, CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', @presentationKey, '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content'
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'kind': kind.name,
    'dedupKey': 'dedup-$id',
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'presentationKey': presentationKey,
    'createdAt': createdAt.toIso8601String(),
  },
);
