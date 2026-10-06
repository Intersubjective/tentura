@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/room_message_snapshot_lookup.dart';
import 'package:tentura_server/domain/entity/room_message_snapshot.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// tentura-617.19 (issue #181 plan §8.7 items 1–3): realtime WS paint for fact
/// system lines and quoted messages.
///
/// `RoomMessageSnapshotLookup.findEligibleInsert` paints:
/// * plain text (unchanged),
/// * markers 10 (`factEdited`) / 11 (`factUnpinned`) carrying
///   `system_payload`, even with an empty body → `semanticMarker` +
///   `systemPayload` on the snapshot,
/// * quoted messages (`quoted_fact_card_id` + `quoted_fact_revision_seq`),
///   quote-only included → `quotedFact` mirroring the `listMessagesEnriched`
///   quote snapshot (quoted revision text, head `currentSeq`).
///
/// It still returns null (client refetch) for pin lines (markers 2/3), rows
/// with `linked_fact_card_id`, and rows with attachments.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_SNAPSHOT_FACT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_snapshot_fact',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('RoomMessageSnapshotLookup fact paint — disposable Postgres', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    late TenturaDb db;
    late RoomMessageSnapshotLookup lookup;
    final notifications = <Map<String, dynamic>>[];

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await _seed(writer);
        db = openDisposablePgDatabase(target);
        lookup = RoomMessageSnapshotLookup(db);

        listener = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        await listener.execute('LISTEN entity_changes');
        notificationSubscription = listener.channels['entity_changes'].listen(
          (payload) =>
              notifications.add(jsonDecode(payload) as Map<String, dynamic>),
        );
      });

      tearDown(notifications.clear);

      tearDownAll(() async {
        await notificationSubscription.cancel();
        await listener.close();
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    Future<RoomMessageSnapshot?> find(String messageId) =>
        lookup.findEligibleInsert(messageId: messageId, beaconId: _beaconId);

    test(
      'marker-10 fact-edited line with empty body is painted with its '
      'systemPayload',
      () async {
        final snapshot = await find(_editedLineId);
        expect(snapshot, isNotNull, reason: 'marker 10 must be painted');
        expect(snapshot!.id, _editedLineId);
        expect(snapshot.beaconId, _beaconId);
        expect(snapshot.authorId, _ownerId);
        expect(snapshot.body, '');
        expect(snapshot.semanticMarker, BeaconRoomSemanticMarker.factEdited);
        expect(snapshot.systemPayload, <String, Object?>{
          'factCardId': _roomFactId,
          'revisionSeq': 2,
          'pinnedBy': _ownerId,
          'factText': 'Gate code is 4412',
        });
        expect(snapshot.quotedFact, isNull);
      },
      skip: skipReason,
    );

    test(
      'marker-11 fact-unpinned line with empty body is painted with its '
      'systemPayload',
      () async {
        final snapshot = await find(_unpinnedLineId);
        expect(snapshot, isNotNull, reason: 'marker 11 must be painted');
        expect(snapshot!.body, '');
        expect(
          snapshot.semanticMarker,
          BeaconRoomSemanticMarker.factUnpinned,
        );
        expect(snapshot.systemPayload, <String, Object?>{
          'factCardId': _publicFactId,
          'pinnedBy': _ownerId,
          'factText': 'Tap water is on',
        });
        expect(snapshot.quotedFact, isNull);
      },
      skip: skipReason,
    );

    test(
      'a quoted message is painted with quotedFact (quoted revision text, '
      'head currentSeq)',
      () async {
        final snapshot = await find(_quoteMsgId);
        expect(snapshot, isNotNull, reason: 'quoted message must be painted');
        expect(snapshot!.body, 'see this fact');
        expect(snapshot.semanticMarker, isNull);
        expect(snapshot.systemPayload, isNull);
        final quoted = snapshot.quotedFact;
        expect(quoted, isNotNull);
        expect(quoted!.factCardId, _roomFactId);
        expect(quoted.seq, 1);
        expect(quoted.currentSeq, 2);
        expect(
          quoted.factText,
          'Gate code is 1234',
          reason: 'quoted revision text, not the current head text',
        );
        expect(quoted.pinnedById, _ownerId);
        expect(quoted.pinnedByTitle, 'Owner Person');
        expect(quoted.visibility, BeaconFactCardVisibilityBits.room);
        expect(quoted.status, BeaconFactCardStatusBits.corrected);
        expect(quoted.attachmentsJson, '[]');
      },
      skip: skipReason,
    );

    test(
      'a quote-only message (empty body) is painted with quotedFact',
      () async {
        final snapshot = await find(_quoteOnlyMsgId);
        expect(snapshot, isNotNull, reason: 'quote-only must be painted');
        expect(snapshot!.body, '');
        final quoted = snapshot.quotedFact;
        expect(quoted, isNotNull);
        expect(quoted!.factCardId, _publicFactId);
        expect(quoted.seq, 1);
        expect(quoted.currentSeq, 1);
        expect(quoted.factText, 'Tap water is on');
        expect(quoted.visibility, BeaconFactCardVisibilityBits.public);
        expect(quoted.status, BeaconFactCardStatusBits.active);
      },
      skip: skipReason,
    );

    test(
      'a plain-text message is still painted without fact fields',
      () async {
        final snapshot = await find(_plainMsgId);
        expect(snapshot, isNotNull);
        expect(snapshot!.body, 'plain hello');
        expect(snapshot.semanticMarker, isNull);
        expect(snapshot.systemPayload, isNull);
        expect(snapshot.quotedFact, isNull);
      },
      skip: skipReason,
    );

    test(
      'Request plan lines (#220: kind 5, markers 13..16, no author) are '
      'painted with payload and systemMessageKind; a plan marker without '
      'kind 5 is not',
      () async {
        Future<void> insert(
          String id, {
          required int marker,
          required int? kind,
          String? author,
        }) => writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, mentions, thread_item_id, created_at,
   semantic_marker, system_payload, system_message_kind)
VALUES (@id, @beacon, @author, '', ARRAY[]::text[], NULL, @at,
        @marker::smallint, @payload::jsonb, @kind::smallint)
'''),
          parameters: {
            'id': id,
            'beacon': _beaconId,
            'author': author,
            'at': _t0.add(const Duration(days: 1)),
            'marker': marker,
            'kind': kind,
            'payload': jsonEncode({
              'ticks': [
                {'stepId': 'PS000000000001', 'title': 'Bring boards'},
              ],
            }),
          },
        );

        await insert(
          'Rsfplantick',
          marker: BeaconRoomSemanticMarker.planStepsDone,
          kind: 5,
        );
        await insert(
          'Rsfplanrevs',
          marker: BeaconRoomSemanticMarker.planRevised,
          kind: 5,
          author: _ownerId,
        );
        await insert(
          'Rsfplannokd',
          marker: BeaconRoomSemanticMarker.planRevised,
          kind: null,
          author: _ownerId,
        );

        final tick = await find('Rsfplantick');
        expect(tick, isNotNull);
        expect(tick!.authorId, '', reason: 'a null author paints as empty');
        expect(tick.systemMessageKind, 5);
        expect(tick.semanticMarker, BeaconRoomSemanticMarker.planStepsDone);
        expect(
          (tick.systemPayload!['ticks']! as List).single,
          containsPair('title', 'Bring boards'),
        );
        final revised = await find('Rsfplanrevs');
        expect(revised!.authorId, _ownerId);
        expect(revised.semanticMarker, BeaconRoomSemanticMarker.planRevised);
        expect(await find('Rsfplannokd'), isNull);
      },
      skip: skipReason,
    );

    test(
      'a marker-2 pin line is not painted (client refetch)',
      () async {
        expect(await find(_pinLineId), isNull);
      },
      skip: skipReason,
    );

    test(
      'a message with linked_fact_card_id is not painted',
      () async {
        expect(await find(_linkedMsgId), isNull);
      },
      skip: skipReason,
    );

    test(
      'a message with an attachment is not painted',
      () async {
        expect(await find(_attachmentMsgId), isNull);
      },
      skip: skipReason,
    );

    test(
      'a poll message (marker 8 + linked_polling_id) is not painted',
      () async {
        expect(await find(_pollMsgId), isNull);
      },
      skip: skipReason,
    );

    test(
      'a message with linked_item_id / linked_event_kind is not painted',
      () async {
        expect(await find(_linkedItemMsgId), isNull);
        expect(await find(_linkedEventMsgId), isNull);
      },
      skip: skipReason,
    );

    test(
      'a message with linked_next_move_id is not painted',
      () async {
        expect(await find(_nextMoveMsgId), isNull);
      },
      skip: skipReason,
    );

    test(
      'other semantic markers with system_payload (empty or non-empty body) '
      'are not painted',
      () async {
        for (final marker in _otherMarkers) {
          expect(
            await find(_otherMarkerMsgId(marker)),
            isNull,
            reason: 'marker $marker with empty body must stay refetch',
          );
          expect(
            await find(_otherMarkerTextMsgId(marker)),
            isNull,
            reason: 'marker $marker with body must stay refetch',
          );
        }
      },
      skip: skipReason,
    );

    test(
      'a quote or a marker-10 line does not override rejection '
      '(quote + poll, quote + next move, quote + attachment, '
      'marker 10 + attachment, marker 10 + linked_fact_card_id)',
      () async {
        expect(await find(_quotePollMsgId), isNull);
        expect(await find(_quoteNextMoveMsgId), isNull);
        expect(await find(_quoteAttachmentMsgId), isNull);
        expect(await find(_editedAttachmentMsgId), isNull);
        expect(await find(_editedLinkedFactMsgId), isNull);
      },
      skip: skipReason,
    );

    test(
      'a blank plain message and a marker-10 line without system_payload are '
      'not painted',
      () async {
        expect(await find(_blankMsgId), isNull);
        expect(await find(_editedNoPayloadId), isNull);
      },
      skip: skipReason,
    );

    test(
      'a painted quote of a room-only fact reaches only '
      'realtime_room_recipients ∪ admitted mentions',
      () async {
        const messageId = 'Rsfquotemnt1';
        await writer.execute('BEGIN');
        await writer.execute(
          Sql.named(
            "SELECT set_config('tentura.mutating_user_id', @actor, true)",
          ),
          parameters: {'actor': _authorId},
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, mentions, thread_item_id,
   quoted_fact_card_id, quoted_fact_revision_seq)
VALUES (@id, @beacon, @author, 'ping about this', ARRAY[@mention]::text[],
        NULL, @fact, 1)
'''),
          parameters: {
            'id': messageId,
            'beacon': _beaconId,
            'author': _authorId,
            'mention': _mentionedId,
            'fact': _roomFactId,
          },
        );
        await writer.execute('COMMIT');

        final change = await _waitForRoomMessage(notifications, messageId);
        expect(change['entity'], 'room_message');
        expect(change['event'], 'insert');
        expect(change['id'], _beaconId);

        final roomRecipients =
            (await writer.execute(
                  Sql.named('SELECT public.realtime_room_recipients(@beacon)'),
                  parameters: {'beacon': _beaconId},
                )).single.single!
                as List;
        final beaconRecipients =
            (await writer.execute(
                  Sql.named(
                    'SELECT public.realtime_beacon_recipients(@beacon)',
                  ),
                  parameters: {'beacon': _beaconId},
                )).single.single!
                as List;
        final admitted = (await writer.execute(
          Sql.named('''
SELECT user_id FROM public.beacon_admitted_helper WHERE beacon_id = @beacon
'''),
          parameters: {'beacon': _beaconId},
        )).map((r) => r.single! as String).toSet();

        // Preconditions: the mention is an admitted room member, the author
        // too; the watcher is a beacon recipient but not admitted to the room.
        expect(admitted, {_authorId, _mentionedId});
        expect(
          roomRecipients.cast<String>().toSet(),
          {_ownerId, _authorId, _mentionedId},
        );
        expect(beaconRecipients.cast<String>(), contains(_watcherId));
        expect(admitted, isNot(contains(_watcherId)));

        final recipients = (change['user_ids']! as List).cast<String>().toSet();
        expect(recipients, {
          ...roomRecipients.cast<String>(),
          _authorId,
          _mentionedId,
        });
        expect(
          recipients,
          {_ownerId, ...admitted},
          reason: 'owner ∪ admitted members (author and admitted mention)',
        );
        expect(
          recipients,
          isNot(contains(_watcherId)),
          reason:
              'room-only quoted fact must not widen to '
              'realtime_beacon_recipients',
        );

        final snapshot = await find(messageId);
        expect(snapshot, isNotNull, reason: 'the quote must be painted');
        expect(snapshot!.mentions, [_mentionedId]);
        expect(snapshot.quotedFact, isNotNull);
        expect(snapshot.quotedFact!.factCardId, _roomFactId);
        expect(
          snapshot.quotedFact!.visibility,
          BeaconFactCardVisibilityBits.room,
        );
      },
      skip: skipReason,
    );
  });
}

Future<Map<String, dynamic>> _waitForRoomMessage(
  List<Map<String, dynamic>> notifications,
  String messageId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    for (final message in notifications) {
      if (message['entity'] == 'room_message' &&
          message['message_id'] == messageId) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for room_message notification for $messageId');
}

// ---------------------------------------------------------------------------
// Fixture: the owner owns the beacon and pinned both facts. The author and the
// mentioned user are admitted room participants (room_access = 3); the watcher
// is a beacon participant without room access, so it is a
// realtime_beacon_recipients member but not a realtime_room_recipients one.
// The room fact is room-only, corrected, head seq 2; the public fact is active
// at head seq 1.

const _ownerId = 'Usfowner001';
const _authorId = 'Usfauthor01';
const _mentionedId = 'Usfmention1';
const _watcherId = 'Usfwatcher1';

const _beaconId = 'Bsfbeacon01';

const _roomFactId = 'Fsfroomfct1';
const _publicFactId = 'Fsfpublicf1';

const _editedLineId = 'Rsfedited01';
const _editedNoPayloadId = 'Rsfeditnop1';
const _unpinnedLineId = 'Rsfunpinned';
const _quoteMsgId = 'Rsfquote001';
const _quoteOnlyMsgId = 'Rsfquoteonl';
const _plainMsgId = 'Rsfplain001';
const _blankMsgId = 'Rsfblank001';
const _pinLineId = 'Rsfpinline1';
const _linkedMsgId = 'Rsflinked01';
const _attachmentMsgId = 'Rsfattach01';
const _pollMsgId = 'Rsfpoll0001';
const _linkedItemMsgId = 'Rsflinkitem';
const _linkedEventMsgId = 'Rsflinkevnt';
const _nextMoveMsgId = 'Rsfnextmove';
const _quotePollMsgId = 'Rsfquotepol';
const _quoteNextMoveMsgId = 'Rsfquotenmv';
const _quoteAttachmentMsgId = 'Rsfquoteatt';
const _editedAttachmentMsgId = 'Rsfeditatt1';
const _editedLinkedFactMsgId = 'Rsfeditlnk1';

const _pollId = 'Osfpoll0001';
const _itemId = 'Isfitem0001';

/// Semantic markers other than 10/11 that must stay unpainted.
const _otherMarkers = [
  BeaconRoomSemanticMarker.updatePlan,
  BeaconRoomSemanticMarker.pinFactPrivate,
  BeaconRoomSemanticMarker.participantStatusChanged,
  BeaconRoomSemanticMarker.blocker,
  BeaconRoomSemanticMarker.needInfo,
  BeaconRoomSemanticMarker.done,
  BeaconRoomSemanticMarker.participantJoined,
];
String _otherMarkerMsgId(int marker) =>
    'Rsfmark${marker.toString().padLeft(2, '0')}e';
String _otherMarkerTextMsgId(int marker) =>
    'Rsfmark${marker.toString().padLeft(2, '0')}t';

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@owner, 'Owner Person', @ownerKey),
       (@author, 'Author Person', @authorKey),
       (@mention, 'Mentioned Person', @mentionKey),
       (@watcher, 'Watcher Person', @watcherKey)
'''),
    parameters: {
      'owner': _ownerId,
      'ownerKey': pgTestPublicKey('roomsnapshotfact', 1),
      'author': _authorId,
      'authorKey': pgTestPublicKey('roomsnapshotfact', 2),
      'mention': _mentionedId,
      'mentionKey': pgTestPublicKey('roomsnapshotfact', 3),
      'watcher': _watcherId,
      'watcherKey': pgTestPublicKey('roomsnapshotfact', 4),
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @owner, 't', 'd', 0, @t0, false)
'''),
    parameters: {'beacon': _beaconId, 'owner': _ownerId, 't0': _t0},
  );
  for (final (userId, role, roomAccess) in [
    (_authorId, BeaconParticipantRoleBits.helper, 3),
    (_mentionedId, BeaconParticipantRoleBits.helper, 3),
    (_watcherId, BeaconParticipantRoleBits.watcher, 0),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES (@beacon, @user, @role::smallint, @access::smallint)
'''),
      parameters: {
        'beacon': _beaconId,
        'user': userId,
        'role': role,
        'access': roomAccess,
      },
    );
  }

  final cards = <(String, String, int, int, int)>[
    (
      _roomFactId,
      'Gate code is 4412',
      BeaconFactCardVisibilityBits.room,
      BeaconFactCardStatusBits.corrected,
      2,
    ),
    (
      _publicFactId,
      'Tap water is on',
      BeaconFactCardVisibilityBits.public,
      BeaconFactCardStatusBits.active,
      1,
    ),
  ];
  for (final (id, text, visibility, status, head) in cards) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, source_message_id,
   status, revision_seq, other_editor_count, history_truncated,
   created_at, updated_at)
VALUES
  (@id, @beacon, @text, @visibility, @owner, NULL, @status,
   @head::integer, 0, false, @t0, @t0)
'''),
      parameters: {
        'id': id,
        'beacon': _beaconId,
        'text': text,
        'visibility': visibility,
        'owner': _ownerId,
        'status': status,
        'head': head,
        't0': _t0,
      },
    );
  }

  final revisions = <(String, String, int, String, int)>[
    (
      'Vsfroom1',
      _roomFactId,
      1,
      'Gate code is 1234',
      BeaconFactCardRevisionKindBits.created,
    ),
    (
      'Vsfroom2',
      _roomFactId,
      2,
      'Gate code is 4412',
      BeaconFactCardRevisionKindBits.edited,
    ),
    (
      'Vsfpub1',
      _publicFactId,
      1,
      'Tap water is on',
      BeaconFactCardRevisionKindBits.created,
    ),
  ];
  for (final (id, factId, seq, text, kind) in revisions) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (id, fact_card_id, seq, fact_text, actor_id, kind, created_at)
VALUES (@id, @fact, @seq::integer, @text, @actor, @kind::integer, @at)
'''),
      parameters: {
        'id': id,
        'fact': factId,
        'seq': seq,
        'text': text,
        'actor': _ownerId,
        'kind': kind,
        'at': _t0.add(Duration(seconds: seq)),
      },
    );
  }

  final messages =
      <
        (
          String id,
          String author,
          String body,
          int? marker,
          Map<String, Object?>? payload,
          String? quotedFact,
          int? quotedSeq,
          String? linkedFact,
        )
      >[
        (
          _editedLineId,
          _ownerId,
          '',
          BeaconRoomSemanticMarker.factEdited,
          {
            'factCardId': _roomFactId,
            'revisionSeq': 2,
            'pinnedBy': _ownerId,
            'factText': 'Gate code is 4412',
          },
          null,
          null,
          null,
        ),
        (
          _editedNoPayloadId,
          _ownerId,
          '',
          BeaconRoomSemanticMarker.factEdited,
          null,
          null,
          null,
          null,
        ),
        (
          _unpinnedLineId,
          _ownerId,
          '',
          BeaconRoomSemanticMarker.factUnpinned,
          {
            'factCardId': _publicFactId,
            'pinnedBy': _ownerId,
            'factText': 'Tap water is on',
          },
          null,
          null,
          null,
        ),
        (
          _pinLineId,
          _ownerId,
          '',
          BeaconRoomSemanticMarker.pinFactPublic,
          {'factCardId': _publicFactId, 'factText': 'Tap water is on'},
          null,
          null,
          null,
        ),
        (
          _quoteMsgId,
          _authorId,
          'see this fact',
          null,
          null,
          _roomFactId,
          1,
          null,
        ),
        (_quoteOnlyMsgId, _authorId, '', null, null, _publicFactId, 1, null),
        (_plainMsgId, _authorId, 'plain hello', null, null, null, null, null),
        (_blankMsgId, _authorId, '   ', null, null, null, null, null),
        (
          _linkedMsgId,
          _authorId,
          'the source of a pin',
          null,
          null,
          null,
          null,
          _publicFactId,
        ),
        (
          _attachmentMsgId,
          _authorId,
          'with a file',
          null,
          null,
          null,
          null,
          null,
        ),
      ];
  for (final (i, m) in messages.indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, mentions, thread_item_id, created_at,
   semantic_marker, system_payload, quoted_fact_card_id,
   quoted_fact_revision_seq, linked_fact_card_id)
VALUES (@id, @beacon, @author, @body, ARRAY[]::text[], NULL, @at,
        @marker::smallint, @payload::jsonb, @quotedFact,
        @quotedSeq::integer, @linkedFact)
'''),
      parameters: {
        'id': m.$1,
        'beacon': _beaconId,
        'author': m.$2,
        'body': m.$3,
        'at': _t0.add(Duration(minutes: i + 1)),
        'marker': m.$4,
        'payload': m.$5 == null ? null : jsonEncode(m.$5),
        'quotedFact': m.$6,
        'quotedSeq': m.$7,
        'linkedFact': m.$8,
      },
    );
  }

  await writer.execute(
    Sql.named('''
INSERT INTO public.polling (id, author_id, question)
VALUES (@id, @author, 'Which day?')
'''),
    parameters: {'id': _pollId, 'author': _authorId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id,
  published, created_at, updated_at, published_at, source, ordering
) VALUES (
  @id, @beacon, @kind::smallint, @status::smallint, 'Ask', '', @creator,
  true, @t0, @t0, @t0, @source::smallint, 0
)
'''),
    parameters: {
      'id': _itemId,
      'beacon': _beaconId,
      'kind': coordinationItemKindAsk,
      'status': coordinationItemStatusOpen,
      'creator': _authorId,
      'source': coordinationItemSourceDefault,
      't0': _t0,
    },
  );

  const editedPayload = <String, Object?>{
    'factCardId': _roomFactId,
    'revisionSeq': 2,
    'pinnedBy': _ownerId,
    'factText': 'Gate code is 4412',
  };
  final rejected =
      <
        ({
          String id,
          String body,
          int? marker,
          Map<String, Object?>? payload,
          String? quotedFact,
          String? pollId,
          String? itemId,
          int? eventKind,
          String? nextMoveId,
          String? linkedFact,
        })
      >[
        (
          id: _pollMsgId,
          body: '',
          marker: BeaconRoomSemanticMarker.poll,
          payload: null,
          quotedFact: null,
          pollId: _pollId,
          itemId: null,
          eventKind: null,
          nextMoveId: null,
          linkedFact: null,
        ),
        (
          id: _linkedItemMsgId,
          body: 'ask created',
          marker: null,
          payload: null,
          quotedFact: null,
          pollId: null,
          itemId: _itemId,
          eventKind: coordinationEventKindCreated,
          nextMoveId: null,
          linkedFact: null,
        ),
        (
          id: _linkedEventMsgId,
          body: 'item updated',
          marker: null,
          payload: null,
          quotedFact: null,
          pollId: null,
          itemId: null,
          eventKind: coordinationEventKindUpdated,
          nextMoveId: null,
          linkedFact: null,
        ),
        (
          id: _nextMoveMsgId,
          body: 'my next move',
          marker: null,
          payload: null,
          quotedFact: null,
          pollId: null,
          itemId: null,
          eventKind: null,
          nextMoveId: 'Psfnextmove1',
          linkedFact: null,
        ),
        (
          id: _quotePollMsgId,
          body: '',
          marker: BeaconRoomSemanticMarker.poll,
          payload: null,
          quotedFact: _publicFactId,
          pollId: _pollId,
          itemId: null,
          eventKind: null,
          nextMoveId: null,
          linkedFact: null,
        ),
        (
          id: _quoteNextMoveMsgId,
          body: 'quote with a next move',
          marker: null,
          payload: null,
          quotedFact: _publicFactId,
          pollId: null,
          itemId: null,
          eventKind: null,
          nextMoveId: 'Psfnextmove2',
          linkedFact: null,
        ),
        (
          id: _quoteAttachmentMsgId,
          body: 'quote with a file',
          marker: null,
          payload: null,
          quotedFact: _publicFactId,
          pollId: null,
          itemId: null,
          eventKind: null,
          nextMoveId: null,
          linkedFact: null,
        ),
        (
          id: _editedAttachmentMsgId,
          body: '',
          marker: BeaconRoomSemanticMarker.factEdited,
          payload: editedPayload,
          quotedFact: null,
          pollId: null,
          itemId: null,
          eventKind: null,
          nextMoveId: null,
          linkedFact: null,
        ),
        (
          id: _editedLinkedFactMsgId,
          body: '',
          marker: BeaconRoomSemanticMarker.factEdited,
          payload: editedPayload,
          quotedFact: null,
          pollId: null,
          itemId: null,
          eventKind: null,
          nextMoveId: null,
          linkedFact: _roomFactId,
        ),
        for (final marker in _otherMarkers) ...[
          (
            id: _otherMarkerMsgId(marker),
            body: '',
            marker: marker,
            payload: const {'factCardId': _publicFactId, 'reason': 'x'},
            quotedFact: null,
            pollId: null,
            itemId: null,
            eventKind: null,
            nextMoveId: null,
            linkedFact: null,
          ),
          (
            id: _otherMarkerTextMsgId(marker),
            body: 'system line text',
            marker: marker,
            payload: const {'factCardId': _publicFactId, 'reason': 'x'},
            quotedFact: null,
            pollId: null,
            itemId: null,
            eventKind: null,
            nextMoveId: null,
            linkedFact: null,
          ),
        ],
      ];
  for (final (i, m) in rejected.indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, mentions, thread_item_id, created_at,
   semantic_marker, system_payload, quoted_fact_card_id,
   quoted_fact_revision_seq, linked_polling_id, linked_item_id,
   linked_event_kind, linked_next_move_id, linked_fact_card_id)
VALUES (@id, @beacon, @author, @body, ARRAY[]::text[], NULL, @at,
        @marker::smallint, @payload::jsonb, @quotedFact,
        @quotedSeq::integer, @poll, @item, @eventKind::smallint,
        @nextMove, @linkedFact)
'''),
      parameters: {
        'id': m.id,
        'beacon': _beaconId,
        'author': _authorId,
        'body': m.body,
        'at': _t0.add(Duration(hours: 1, minutes: i)),
        'marker': m.marker,
        'payload': m.payload == null ? null : jsonEncode(m.payload),
        'quotedFact': m.quotedFact,
        'quotedSeq': m.quotedFact == null ? null : 1,
        'poll': m.pollId,
        'item': m.itemId,
        'eventKind': m.eventKind,
        'nextMove': m.nextMoveId,
        'linkedFact': m.linkedFact,
      },
    );
  }

  for (final messageId in [
    _attachmentMsgId,
    _quoteAttachmentMsgId,
    _editedAttachmentMsgId,
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message_attachment
  (message_id, kind, file_url, mime, size_bytes, file_name)
VALUES (@message, @kind::smallint, 'https://files.test/a.pdf',
        'application/pdf', 10, 'a.pdf')
'''),
      parameters: {
        'message': messageId,
        'kind': BeaconRoomMessageAttachmentKind.file,
      },
    );
  }
}
