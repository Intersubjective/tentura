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

/// U10d — §0.1a grouped-row provenance (card spec §4).
///
/// The card's whole premise is the forward note, and until this unit the note
/// existed only on the Inbox query. These tests state the contract U14 and U16
/// will build against: a grouped `beacon:` row carries the *verbatim*
/// `inbox_provenance_data` document, the header's Request identity, and a
/// forward affordance that tracks the live status gate.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_PROVENANCE_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_prov',
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

  test('a grouped forward row carries the verbatim provenance document', () async {
    await forwardTo(writer, senderId: senderOneId, note: 'Ты же с этим возился');
    await forwardTo(writer, senderId: senderTwoId, note: 'Могу подвезти');
    await watchRequest(writer);

    final row = await groupedRow(query);
    expect(row.provenanceJson, isNotNull);

    final provenance = jsonDecode(row.provenanceJson!) as Map<String, Object?>;
    // CHANGES IN U15R-b: `latestNoteForward` joins the document (R4,
    // D-171-5a). The rule this case defends is unchanged — one shape, no
    // second DTO — and the addition is additive precisely so that
    // `InboxProvenance.parse` and `withoutViewer` keep working on both
    // callers. What would still be a violation is a *different* document for
    // the attention path, which is why the key set stays pinned exactly.
    expect(
      provenance.keys.toSet(),
      {
        'senders',
        'totalDistinctSenders',
        'strongestNotePreview',
        'latestNoteForward',
      },
      reason:
          'the shape is the one InboxProvenance.parse already consumes — '
          'a second provenance DTO is forbidden by the card spec',
    );

    final senders = (provenance['senders']! as List).cast<Map<String, Object?>>();
    expect(senders.map((s) => s['id']), containsAll([senderOneId, senderTwoId]));
    expect(
      senders.first.keys.toSet(),
      {'id', 'displayName', 'mr', 'imageId', 'notePreview', 'reasonSlugs'},
    );
    expect(provenance['totalDistinctSenders'], 2);
    expect(
      provenance['strongestNotePreview'],
      anyOf('Ты же с этим возился', 'Могу подвезти'),
      reason:
          'the note is already MR-ranked server-side; this unit plumbs it, '
          'it does not re-rank it',
    );
    expect(
      senders.map((s) => s['notePreview']),
      containsAll(['Ты же с этим возился', 'Могу подвезти']),
    );
  }, skip: skipReason);

  test('the row carries the header identity the card needs', () async {
    await forwardTo(writer, senderId: senderOneId, note: 'note');
    await watchRequest(writer);

    final row = await groupedRow(query);
    expect(row.beaconAuthorId, authorId);
    expect(row.beaconAuthorName, 'Author Name');
    expect(row.beaconEndAt, DateTime.parse(beaconEndAt));
    expect(row.title, 'Наши требования');
  }, skip: skipReason);

  test('allowsForward is the live gate, not a constant', () async {
    await forwardTo(writer, senderId: senderOneId, note: 'note');
    await watchRequest(writer);

    expect(
      (await groupedRow(query)).allowsForward,
      isTrue,
      reason: 'status 0 is the open family',
    );

    // 8 = enoughHelp, still open family: forwarding stays available.
    await setBeaconStatus(writer, 8);
    expect((await groupedRow(query)).allowsForward, isTrue);

    // 5 = reviewOpen — coordination continues, forwarding does not.
    await setBeaconStatus(writer, 5);
    expect(
      (await groupedRow(query)).allowsForward,
      isFalse,
      reason:
          'BeaconStatus.allowsForward is isOpenFamily; reviewOpen allows '
          'coordination but not a new forward (forward_case.dart)',
    );
  }, skip: skipReason);

  test('a plain receipt carries no provenance at all', () async {
    await forwardTo(writer, senderId: senderOneId, note: 'note');
    await watchRequest(writer);

    final feed = await query.attentionFeed(
      accountId: viewerId,
      view: AttentionFeedView.all,
      surface: AttentionSurface.activity,
    );
    for (final item in feed.page.items) {
      if (item.itemKind == AttentionItemKind.receipt ||
          item.itemKind == AttentionItemKind.watchingDigest) {
        expect(item.provenanceJson, isNull);
        expect(item.allowsForward, isNull);
        expect(item.beaconAuthorId, isNull);
      }
    }
  }, skip: skipReason);
}

const viewerId = 'Uu10dprv01';
const authorId = 'Uu10dprv02';
const senderOneId = 'Uu10dprv03';
const senderTwoId = 'Uu10dprv04';
const blockedSenderId = 'Uu10dprv05';
const beaconId = 'Bu10dprv01';
const unreadableBeaconId = 'Bu10dprv02';
const beaconEndAt = '2026-12-31T10:00:00Z';

/// The single grouped `beacon:` row the fixtures produce.
Future<AttentionReceipt> groupedRow(AttentionRepository query) async {
  final feed = await query.attentionFeed(
    accountId: viewerId,
    view: AttentionFeedView.all,
    surface: AttentionSurface.activity,
  );
  final grouped = feed.page.items.where(
    (item) =>
        item.beaconId == beaconId &&
        (item.itemKind == AttentionItemKind.forward ||
            item.itemKind == AttentionItemKind.requestActivity),
  );
  expect(
    grouped,
    hasLength(1),
    reason: 'the fixture must actually produce one grouped row to assert on',
  );
  return grouped.single;
}

Future<void> setBeaconStatus(Connection writer, int status) => writer.execute(
  Sql.named('UPDATE public.beacon SET status = @status WHERE id = @beacon'),
  parameters: {'status': status, 'beacon': beaconId},
);

/// A forward edge, as in life — the trigger writes the inbox row.
Future<void> forwardTo(
  Connection writer, {
  required String senderId,
  required String note,
  String targetBeaconId = beaconId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, note, created_at, cancelled_at
) VALUES (@id, @beacon, @sender, @recipient, @note, now(), NULL)
'''),
  parameters: {
    'id': 'FE$targetBeaconId$senderId',
    'beacon': targetBeaconId,
    'sender': senderId,
    'recipient': viewerId,
    'note': note,
  },
);

/// Watching (status 1) takes the Request out of the pinned zone and into the
/// grouped forward row this unit is about.
Future<void> watchRequest(
  Connection writer, {
  String targetBeaconId = beaconId,
}) => writer.execute(
  Sql.named(
    'UPDATE public.inbox_item SET status = 1 '
    'WHERE user_id = @user AND beacon_id = @beacon',
  ),
  parameters: {'user': viewerId, 'beacon': targetBeaconId},
);

Future<void> resetProvenanceFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.user_block,
  public.inbox_item,
  public.beacon_forward_edge,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  final names = {
    viewerId: 'Viewer',
    authorId: 'Author Name',
    senderOneId: 'Sender One',
    senderTwoId: 'Sender Two',
    blockedSenderId: 'Blocked Sender',
  };
  for (final entry in names.entries) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @name, @key)',
      ),
      parameters: {
        'id': entry.key,
        'name': entry.value,
        'key': '${entry.key}-key',
      },
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status, end_at)
VALUES
  (@beacon, @author, 'Наши требования', 'Request body', 0, @endAt),
  (@other, @author, 'Unreadable', 'Request body', 0, NULL)
'''),
    parameters: {
      'beacon': beaconId,
      'other': unreadableBeaconId,
      'author': authorId,
      'endAt': DateTime.parse(beaconEndAt),
    },
  );
}
