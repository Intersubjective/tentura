@Tags(['pg', 'mr'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

/// U15R-b — R4: the card's first collapsed slot (D-171-5a, card spec §7.3).
///
/// The spec pins the first slot to **the latest forward carrying a note**. What
/// U10d's payload offers instead is three senders ranked by MeritRank plus a
/// `strongestNotePreview` taken from the highest-ranked sender *without*
/// requiring a non-empty note. Those are different selections, and the
/// difference is not a sort order the card can repair: a recent note from the
/// fourth-ranked sender is absent from the payload entirely.
///
/// The fixture is the one Astra named: four senders, the top-ranked one silent,
/// the newest note on the fourth. Everything below asserts what U16 needs —
/// the note, **who** wrote it and **when** — and each authorization case
/// asserts that the new selection path is not a way around the walls the list
/// and the count already respect.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_LATEST_NOTE_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_latest_note',
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
      await _resetFixtures(writer);
    });
  }

  test(
    'the fourth-ranked sender really is outside the MR top three',
    () async {
      // Non-vacuity for everything below: if the fixture ever ranked the
      // note-bearing sender into the top three, the cases that follow would
      // pass on the old payload and prove nothing.
      await _fourSenderFixture(writer);

      final provenance = await _provenanceOf(query);
      expect(
        _senderIds(provenance),
        [rankOneSilentId, rankTwoId, rankThreeId],
        reason: 'the MR-ranked window the old contract offers',
      );
      expect(provenance['totalDistinctSenders'], 4);
      expect(
        jsonEncode(provenance['senders']),
        isNot(contains('Я знаю, кто это починит')),
        reason:
            'the newest note is the fourth sender’s, and the window cannot '
            'reach it — this is the defect, stated as a fact about the payload',
      );
    },
    skip: skipReason,
  );

  test(
    'the payload names the latest note-bearing forward, with identity and time',
    () async {
      await _fourSenderFixture(writer);

      final latest = _latestNoteForward(await _provenanceOf(query));
      expect(
        latest,
        isNotNull,
        reason:
            'D-171-5a pins the first collapsed slot to the latest forward '
            'carrying a note; the card cannot derive it from senders[]',
      );
      expect(latest!['senderId'], rankFourNewestNoteId);
      expect(latest['notePreview'], 'Я знаю, кто это починит');
      expect(latest['displayName'], 'Rank Four');
      expect(
        latest['forwardId'],
        _forwardId(rankFourNewestNoteId),
        reason: 'the forward identity, so the card can key and open the row',
      );
      expect(
        DateTime.parse(latest['forwardedAt']! as String).toUtc(),
        DateTime.parse('2026-09-18T12:00:00Z'),
        reason: 'the timestamp, so «<age>» on the mini-card is not invented',
      );
      expect(
        latest['reasonSlugs'],
        ['plumbing'],
        reason:
            '§7.1 hangs the capability chips on the forwarder of *this* note',
      );
    },
    skip: skipReason,
  );

  test(
    'a silent top-ranked sender never supplies the first slot',
    () async {
      await _fourSenderFixture(writer);

      final provenance = await _provenanceOf(query);
      expect(
        provenance['strongestNotePreview'],
        '',
        reason:
            'today the strongest note is read off the top-ranked sender even '
            'when that sender wrote nothing — pinned here so the new field is '
            'visibly a different selection, not a rename of this one',
      );
      final latest = _latestNoteForward(provenance)!;
      expect(latest['senderId'], isNot(rankOneSilentId));
      expect((latest['notePreview']! as String).trim(), isNotEmpty);
    },
    skip: skipReason,
  );

  test(
    'the newest note wins over an older one from a higher-ranked sender',
    () async {
      await _fourSenderFixture(writer);
      // `bfe_active_unique` allows one live forward per sender, so the way a
      // higher-ranked sender becomes the newest voice is that their own
      // forward is the later one.
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon_forward_edge '
          "SET created_at = '2026-09-18T18:00:00Z', "
          "    note = 'Свежее, и от более близкого' "
          'WHERE id = @id',
        ),
        parameters: {'id': _forwardId(rankTwoId)},
      );

      final latest = _latestNoteForward(await _provenanceOf(query))!;
      expect(
        latest['senderId'],
        rankTwoId,
        reason: 'latest means latest — this selection is by time, not by MR',
      );
      expect(latest['notePreview'], 'Свежее, и от более близкого');
    },
    skip: skipReason,
  );

  test('no note anywhere means no first slot to pin', () async {
    await _user(writer, rankOneSilentId, 'Rank One');
    await _forward(
      writer,
      senderId: rankOneSilentId,
      note: '',
      createdAt: '2026-09-18T09:00:00Z',
    );
    await _watch(writer);

    final provenance = await _provenanceOf(query);
    expect(_latestNoteForward(provenance), isNull);
    expect(
      provenance['totalDistinctSenders'],
      1,
      reason: 'the silent forward is still a forward; only the note is absent',
    );
  }, skip: skipReason);

  test(
    'a blocked sender never becomes the first slot, however recent the note',
    () async {
      await _fourSenderFixture(writer);
      await _user(writer, blockedSenderId, 'Blocked Sender');
      await _forward(
        writer,
        senderId: blockedSenderId,
        note: 'скрытая записка',
        createdAt: '2026-09-18T23:00:00Z',
      );
      await _block(writer, blocker: viewerId, blocked: blockedSenderId);

      final provenance = await _provenanceOf(query);
      final latest = _latestNoteForward(provenance)!;
      expect(
        latest['senderId'],
        rankFourNewestNoteId,
        reason:
            'the blocked forward is newer, and must not be reachable through '
            'a selection path that bypasses the senders CTE',
      );
      expect(
        jsonEncode(provenance),
        isNot(contains('скрытая записка')),
        reason: 'the note is the person speaking; the words must not survive',
      );
      expect(
        provenance['totalDistinctSenders'],
        4,
        reason: 'and the count still does not reveal them',
      );
    },
    skip: skipReason,
  );

  test('blocking is symmetric for the first slot too', () async {
    await _fourSenderFixture(writer);
    await _user(writer, blockedSenderId, 'Blocked Sender');
    await _forward(
      writer,
      senderId: blockedSenderId,
      note: 'скрытая записка',
      createdAt: '2026-09-18T23:00:00Z',
    );
    // The other direction: they blocked the viewer.
    await _block(writer, blocker: blockedSenderId, blocked: viewerId);

    final provenance = await _provenanceOf(query);
    expect(_latestNoteForward(provenance)!['senderId'], rankFourNewestNoteId);
    expect(jsonEncode(provenance), isNot(contains('скрытая записка')));
  }, skip: skipReason);

  test(
    'a note on a Request the viewer may not read is not carried at all',
    () async {
      await _user(writer, rankOneSilentId, 'Rank One');
      await writer.execute(
        Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @beacon'),
        parameters: {'beacon': unreadableBeaconId},
      );
      await _forward(
        writer,
        senderId: rankOneSilentId,
        note: 'записка на закрытом запросе',
        createdAt: '2026-09-18T12:00:00Z',
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

      final row = await _groupedRowFor(query, unreadableBeaconId);
      expect(
        row.provenanceJson,
        isNull,
        reason:
            'the content wall already answers for the whole document — the '
            'first slot must live inside it, not beside it',
      );
    },
    skip: skipReason,
  );

  test(
    'the cancelled and rejected forwards the senders CTE drops stay dropped',
    () async {
      await _fourSenderFixture(writer);
      await _user(writer, cancelledSenderId, 'Cancelled Sender');
      await _forward(
        writer,
        senderId: cancelledSenderId,
        note: 'отозванная записка',
        createdAt: '2026-09-18T22:00:00Z',
      );
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon_forward_edge SET cancelled_at = now() '
          'WHERE sender_id = @sender',
        ),
        parameters: {'sender': cancelledSenderId},
      );

      final provenance = await _provenanceOf(query);
      expect(_latestNoteForward(provenance)!['senderId'], rankFourNewestNoteId);
      expect(jsonEncode(provenance), isNot(contains('отозванная записка')));
    },
    skip: skipReason,
  );

  test(
    'the committed cross-layer fixture is this exact server response',
    () async {
      // The client's assertion about this contract is driven by a real
      // response, not by hand-written JSON that merely looks right. The
      // captured bytes live in docs/contracts/ next to the other two
      // cross-layer contracts, and this case is what keeps them honest.
      await _fourSenderFixture(writer);
      final raw = (await _groupedRowFor(query, beaconId)).provenanceJson!;

      final file = File(_fixturePath());
      if (Platform.environment['TENTURA_REGENERATE_PROVENANCE_FIXTURE'] ==
          '1') {
        file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({
            'description':
                'Captured from attention_provenance_data by '
                'attention_latest_note_forward_pg_test.dart: four forwarders, '
                'the MR-top-ranked one silent, the newest note on the sender '
                'outside the top three (D-171-5a / R4).',
            'rawPayload': raw,
          })}\n',
        );
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run with TENTURA_REGENERATE_PROVENANCE_FIXTURE=1 to capture',
      );
      expect(
        (jsonDecode(file.readAsStringSync()) as Map)['rawPayload'],
        raw,
        reason:
            'the committed fixture has drifted from what the server returns; '
            'regenerate it rather than editing it by hand',
      );
    },
    skip: skipReason,
  );
}

const viewerId = 'Uu15rbn000';
const authorId = 'Uu15rbn001';

/// Ids ascend with descending rank, so the ordering the payload shows is the
/// intended one whether MR separates these users or leaves them tied at zero
/// (`ORDER BY mr DESC, sender_id ASC`).
const rankOneSilentId = 'Uu15rbn002';
const rankTwoId = 'Uu15rbn003';
const rankThreeId = 'Uu15rbn004';
const rankFourNewestNoteId = 'Uu15rbn005';
const blockedSenderId = 'Uu15rbn006';
const cancelledSenderId = 'Uu15rbn007';

const beaconId = 'Bu15rbn001';
const unreadableBeaconId = 'Bu15rbn002';

String _fixturePath() {
  for (final candidate in const [
    '../../docs/contracts/attention-provenance-latest-note.json',
    'docs/contracts/attention-provenance-latest-note.json',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return '../../docs/contracts/attention-provenance-latest-note.json';
}

String _forwardId(String senderId, [String suffix = 'a']) =>
    'FE$beaconId$senderId$suffix';

Future<void> _fourSenderFixture(Connection writer) async {
  await _user(writer, rankOneSilentId, 'Rank One');
  await _user(writer, rankTwoId, 'Rank Two');
  await _user(writer, rankThreeId, 'Rank Three');
  await _user(writer, rankFourNewestNoteId, 'Rank Four');

  // The top-ranked sender forwarded without saying anything.
  await _forward(
    writer,
    senderId: rankOneSilentId,
    note: '',
    createdAt: '2026-09-18T09:00:00Z',
  );
  await _forward(
    writer,
    senderId: rankTwoId,
    note: 'Посмотри, вдруг твоё',
    createdAt: '2026-09-18T10:00:00Z',
  );
  await _forward(
    writer,
    senderId: rankThreeId,
    note: 'Кажется, это по твоей части',
    createdAt: '2026-09-18T11:00:00Z',
  );
  // Outside the MR window, and the only recent voice on the card.
  await _forward(
    writer,
    senderId: rankFourNewestNoteId,
    note: 'Я знаю, кто это починит',
    createdAt: '2026-09-18T12:00:00Z',
  );
  await _capabilityEvent(writer, rankFourNewestNoteId, 'plumbing');
  await _watch(writer);
}

Future<void> _user(Connection writer, String id, String name) =>
    writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @name, @key) ON CONFLICT (id) DO NOTHING',
      ),
      parameters: {'id': id, 'name': name, 'key': '$id-key'},
    );

Future<void> _forward(
  Connection writer, {
  required String senderId,
  required String note,
  required String createdAt,
  String targetBeaconId = beaconId,
  String suffix = 'a',
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, note, created_at, cancelled_at
) VALUES (@id, @beacon, @sender, @recipient, @note, @createdAt, NULL)
'''),
  parameters: {
    'id': 'FE$targetBeaconId$senderId$suffix',
    'beacon': targetBeaconId,
    'sender': senderId,
    'recipient': viewerId,
    'note': note,
    'createdAt': DateTime.parse(createdAt),
  },
);

Future<void> _capabilityEvent(
  Connection writer,
  String senderId,
  String slug,
) => writer.execute(
  Sql.named('''
INSERT INTO public.person_capability_event (
  id, observer_user_id, subject_user_id, beacon_id, tag_slug, source_type,
  is_negative
) VALUES (@id, @observer, @subject, @beacon, @slug, 1, false)
'''),
  parameters: {
    'id': 'PCE$senderId$slug',
    'observer': senderId,
    'subject': viewerId,
    'beacon': beaconId,
    'slug': slug,
  },
);

Future<void> _watch(Connection writer, {String targetBeaconId = beaconId}) =>
    writer.execute(
      Sql.named(
        'UPDATE public.inbox_item SET status = 1 '
        'WHERE user_id = @user AND beacon_id = @beacon',
      ),
      parameters: {'user': viewerId, 'beacon': targetBeaconId},
    );

Future<void> _block(
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

Future<AttentionReceipt> _groupedRowFor(
  AttentionRepository query,
  String targetBeaconId,
) async {
  final feed = await query.attentionFeed(
    accountId: viewerId,
    view: AttentionFeedView.all,
    surface: AttentionSurface.activity,
  );
  final grouped = feed.page.items.where(
    (item) =>
        item.beaconId == targetBeaconId &&
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

Future<Map<String, Object?>> _provenanceOf(AttentionRepository query) async {
  final row = await _groupedRowFor(query, beaconId);
  expect(row.provenanceJson, isNotNull);
  return jsonDecode(row.provenanceJson!) as Map<String, Object?>;
}

Map<String, Object?>? _latestNoteForward(Map<String, Object?> provenance) =>
    provenance['latestNoteForward'] as Map<String, Object?>?;

List<Object?> _senderIds(Map<String, Object?> provenance) => [
  for (final sender in (provenance['senders']! as List))
    (sender as Map<String, Object?>)['id'],
];

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.user_block,
  public.inbox_item,
  public.beacon_forward_edge,
  public.person_capability_event,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  await _user(writer, viewerId, 'Viewer');
  await _user(writer, authorId, 'Author Name');
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status, end_at)
VALUES
  (@beacon, @author, 'Течёт кран', 'Request body', 0, @endAt),
  (@other, @author, 'Unreadable', 'Request body', 0, NULL)
'''),
    parameters: {
      'beacon': beaconId,
      'other': unreadableBeaconId,
      'author': authorId,
      'endAt': DateTime.parse('2026-12-31T10:00:00Z'),
    },
  );
}
