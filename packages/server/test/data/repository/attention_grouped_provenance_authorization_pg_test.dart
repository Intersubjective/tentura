@Tags(['pg', 'mr'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';
import 'attention_grouped_provenance_pg_test.dart'
    show
        authorId,
        blockedSenderId,
        forwardTo,
        groupedRow,
        resetProvenanceFixtures,
        senderOneId,
        unreadableBeaconId,
        viewerId,
        watchRequest;

/// U10d — the authorization half of §0.1a, which is the risk in this unit.
///
/// Shape is easy to get right and easy to notice when it is wrong. Provenance
/// names *people* — who forwarded, and what they wrote to you — so the failure
/// that matters is a grouped row that names somebody the viewer is not allowed
/// to see. Two exclusions, each asserted against the list **and** the count:
/// a count that reveals a hidden person is still a leak.
///
/// Each exclusion was proved non-vacuous by loosening the wall in a throwaway
/// copy and watching the case go red — the U10d journal entry records the
/// diffs and their output.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_PROVENANCE_AUTHZ_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_prov_authz',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late AttentionRepository query;

  if (reachable) {
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
      await resetProvenanceFixtures(writer);
    });
  }

  test('a blocked forwarder is absent from the senders list', () async {
    await forwardTo(writer, senderId: senderOneId, note: 'visible note');
    await forwardTo(writer, senderId: blockedSenderId, note: 'hidden note');
    await watchRequest(writer);
    await block(writer, blocker: viewerId, blocked: blockedSenderId);

    final provenance = await provenanceOf(query);
    expect(
      senderIds(provenance),
      [senderOneId],
      reason: 'the viewer blocked them; their forward must not name them',
    );
    expect(
      noteText(provenance),
      isNot(contains('hidden note')),
      reason: 'the note is the person speaking — dropping the row is not '
          'enough if the words survive',
    );
  }, skip: skipReason);

  test(
    'the blocked forwarder does not survive in totalDistinctSenders either',
    () async {
      await forwardTo(writer, senderId: senderOneId, note: 'visible note');
      await forwardTo(writer, senderId: blockedSenderId, note: 'hidden note');
      await watchRequest(writer);
      await block(writer, blocker: viewerId, blocked: blockedSenderId);

      expect(
        (await provenanceOf(query))['totalDistinctSenders'],
        1,
        reason:
            '«ещё N переслали» renders this number. A 2 next to one visible '
            'sender tells the viewer exactly that somebody is being hidden — '
            'a count that reveals a hidden person is still a leak',
      );
    },
    skip: skipReason,
  );

  test('blocking is symmetric — the blocker is hidden too', () async {
    await forwardTo(writer, senderId: senderOneId, note: 'visible note');
    await forwardTo(writer, senderId: blockedSenderId, note: 'hidden note');
    await watchRequest(writer);
    // The *other* direction: they blocked the viewer.
    await block(writer, blocker: blockedSenderId, blocked: viewerId);

    final provenance = await provenanceOf(query);
    expect(senderIds(provenance), [senderOneId]);
    expect(provenance['totalDistinctSenders'], 1);
  }, skip: skipReason);

  test(
    'a forwarder on a Request the viewer cannot read is absent, and so is '
    'the Request identity',
    () async {
      // The viewer reached this Request through a forward and was watching
      // it; the author then withdrew it, which closes
      // `beacon_can_read_content` behind them and leaves a tombstone. Set up
      // the way `attention_activity_stream_pg_test.dart` does it — through
      // `inbox_item_apply_tombstone_after_withdraw`, the live path.
      await writer.execute(
        Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @beacon'),
        parameters: {'beacon': unreadableBeaconId},
      );
      await forwardTo(
        writer,
        senderId: senderOneId,
        note: 'note on an unreadable Request',
        targetBeaconId: unreadableBeaconId,
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@user, @beacon, 1, 1, now(), '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = 1
'''),
        parameters: {'user': viewerId, 'beacon': unreadableBeaconId},
      );
      await writer.execute(
        Sql.named(
          'SELECT public.inbox_item_apply_tombstone_after_withdraw('
          '@user, @beacon)',
        ),
        parameters: {'user': viewerId, 'beacon': unreadableBeaconId},
      );

      final row = await unreadableGroupedRow(query);
      expect(
        row.provenanceJson,
        isNull,
        reason:
            'no senders, no notes and no count for a Request whose content '
            'the viewer may not read',
      );
      expect(row.beaconAuthorId, isNull);
      expect(row.beaconAuthorName, isNull);
      expect(row.beaconEndAt, isNull);
      expect(
        row.allowsForward,
        isFalse,
        reason: 'and no affordance to pass it on',
      );
      expect(
        row.title,
        isNot(contains('Unreadable')),
        reason: 'the projection already renders tombstone copy here',
      );
    },
    skip: skipReason,
  );

  test('the readable Request is unaffected by the other one', () async {
    // The non-vacuity guard for the test above: the same fixture shape,
    // readable, must still carry everything.
    await forwardTo(writer, senderId: senderOneId, note: 'readable note');
    await watchRequest(writer);

    final row = await groupedRow(query);
    expect(row.provenanceJson, isNotNull);
    expect(row.beaconAuthorId, authorId);
    expect(row.allowsForward, isTrue);
  }, skip: skipReason);
}

Future<Map<String, Object?>> provenanceOf(AttentionRepository query) async {
  final row = await groupedRow(query);
  expect(row.provenanceJson, isNotNull);
  return jsonDecode(row.provenanceJson!) as Map<String, Object?>;
}

List<Object?> senderIds(Map<String, Object?> provenance) => [
  for (final sender in (provenance['senders']! as List))
    (sender as Map<String, Object?>)['id'],
];

String noteText(Map<String, Object?> provenance) => jsonEncode(provenance);

Future<AttentionReceipt> unreadableGroupedRow(AttentionRepository query) async {
  final feed = await query.attentionFeed(
    accountId: viewerId,
    view: AttentionFeedView.all,
    surface: AttentionSurface.activity,
  );
  final grouped = feed.page.items.where(
    (item) =>
        item.beaconId == unreadableBeaconId &&
        (item.itemKind == AttentionItemKind.forward ||
            item.itemKind == AttentionItemKind.requestActivity),
  );
  expect(
    grouped,
    hasLength(1),
    reason:
        'the tombstoned Request must still produce a grouped row — otherwise '
        'this test proves nothing about what that row carries',
  );
  return grouped.single;
}

Future<void> block(
  Connection writer, {
  required String blocker,
  required String blocked,
}) => writer.execute(
  Sql.named(
    'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
    'VALUES (@blocker, @blocked, @blocked)',
  ),
  parameters: {'blocker': blocker, 'blocked': blocked},
);
