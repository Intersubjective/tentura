@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/prepared_fact_copy.dart';
import 'package:tentura_server/domain/exception.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _actor = 'Uprepcopy001';

const _pubTwo = 'Bprepcopy001';
const _pubMixed = 'Bprepcopy002';
const _pubSingle = 'Bprepcopy003';
const _pubPartial = 'Bprepcopy004';
const _pubAllThere = 'Bprepcopy005';
const _pubRemovedThere = 'Bprepcopy006';
const _draftRequest = 'Bprepcopy007';
const _rootlessPost = 'Bprepcopy008';
const _deletedRequest = 'Bprepcopy009';
const _pubAmbient = 'Bprepcopy010';
const _missingBeacon = 'Bprepcopy404';

const _imageId = '0d6f0c39-8a0b-4c1e-9d43-0b2f9a6e7c11';

/// Copies of facts from other Requests and Posts are written in one
/// transaction by `insertPreparedCopies`: each copy becomes a live fact with
/// its origin and a «copied» revision 1; a published destination gets one
/// «facts brought» chat line and one factPinned event per new fact; a draft
/// destination gets neither; an origin that already has a live copy there is
/// not copied again and its existing id is returned.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_INSERT_PREPARED_COPIES_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_prepared_copies',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardRepository.insertPreparedCopies', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconFactCardRepository repository;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await _seed(writer);
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ),
        );
        repository = BeaconFactCardRepository(db, BeaconRoomRepository(db));
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    Future<List<Map<String, Object?>>> rows(
      String sql,
      Map<String, Object?> parameters,
    ) async {
      final result = await writer.execute(
        Sql.named(sql),
        parameters: parameters,
      );
      return [for (final r in result) r.toColumnMap()];
    }

    Future<List<Map<String, Object?>>> factsOf(String beaconId) => rows(
      '''
SELECT id, beacon_id, fact_text, visibility::integer AS visibility,
       pinned_by, source_message_id, status::integer AS status,
       revision_seq, origin_fact_card_id, origin_revision_seq,
       origin_beacon_kind::integer AS origin_beacon_kind
FROM public.beacon_fact_card
WHERE beacon_id = @b
ORDER BY created_at, id
''',
      {'b': beaconId},
    );

    Future<List<Map<String, Object?>>> revisionsOf(String factId) => rows(
      '''
SELECT seq, kind::integer AS kind, actor_id, fact_text, attachments_json
FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id
ORDER BY seq
''',
      {'id': factId},
    );

    Future<List<Map<String, Object?>>> factsBroughtLines(String beaconId) =>
        rows(
          '''
SELECT id, author_id, beacon_id, semantic_marker::integer AS semantic_marker,
       system_payload
FROM public.beacon_room_message
WHERE beacon_id = @b
  AND semantic_marker = ${BeaconRoomSemanticMarker.factsBrought}
''',
          {'b': beaconId},
        );

    Future<List<Map<String, Object?>>> factPinnedEvents(String beaconId) =>
        rows(
          '''
SELECT type::integer AS type, visibility::integer AS visibility, actor_id,
       fact_card_id, source_message_id, diff
FROM public.beacon_activity_event
WHERE beacon_id = @b
  AND type = ${BeaconActivityEventTypeBits.factPinned}
ORDER BY fact_card_id
''',
          {'b': beaconId},
        );

    Future<int> countRows(String table, String beaconId) async {
      final r = await rows(
        'SELECT count(*)::integer AS n FROM public.$table WHERE beacon_id = @b',
        {'b': beaconId},
      );
      return r.single['n']! as int;
    }

    /// Row counts of every table a copy writes, across all beacons.
    Future<Map<String, Object?>> totals() async => (await rows(
      '''
SELECT
  (SELECT count(*)::integer FROM public.beacon_fact_card) AS facts,
  (SELECT count(*)::integer FROM public.beacon_fact_card_revision)
    AS revisions,
  (SELECT count(*)::integer FROM public.beacon_room_message) AS lines,
  (SELECT count(*)::integer FROM public.beacon_activity_event) AS events
''',
      const {},
    )).single;

    Future<int> revisionsOnBeacon(String beaconId) async {
      final r = await rows(
        '''
SELECT count(*)::integer AS n
FROM public.beacon_fact_card_revision r
JOIN public.beacon_fact_card f ON f.id = r.fact_card_id
WHERE f.beacon_id = @b
''',
        {'b': beaconId},
      );
      return r.single['n']! as int;
    }

    Future<void> seedLiveCopy({
      required String id,
      required String beaconId,
      required String originId,
      int status = BeaconFactCardStatusBits.active,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status,
   origin_fact_card_id, origin_revision_seq, origin_beacon_kind)
VALUES (@id, @b, 'earlier copy', 1, @u, @s, @o, 1, 0)
'''),
      parameters: {
        'id': id,
        'b': beaconId,
        'u': _actor,
        's': status,
        'o': originId,
      },
    );

    Map<String, Object?> payloadOf(Map<String, Object?> line) {
      final raw = line['system_payload'];
      return (raw is String ? jsonDecode(raw) : raw)! as Map<String, Object?>;
    }

    Object? decodeJson(Object? raw) => raw is String ? jsonDecode(raw) : raw;

    /// The new fact row and its only revision match [prepared].
    Future<void> expectCopiedFact({
      required String beaconId,
      required String factId,
      required PreparedFactCopy prepared,
    }) async {
      final fact = (await factsOf(beaconId)).singleWhere(
        (f) => f['id'] == factId,
      );
      expect(fact['fact_text'], prepared.factText);
      expect(fact['visibility'], BeaconFactCardVisibilityBits.room);
      expect(fact['pinned_by'], _actor);
      expect(fact['source_message_id'], isNull);
      expect(fact['status'], BeaconFactCardStatusBits.active);
      expect(fact['origin_fact_card_id'], prepared.originFactCardId);
      expect(fact['origin_revision_seq'], prepared.originRevisionSeq);
      expect(fact['revision_seq'], 1, reason: 'head is revision 1');
      expect(fact['origin_beacon_kind'], prepared.originBeaconKind);
      final revisions = await revisionsOf(factId);
      expect(revisions, hasLength(1), reason: 'only revision 1');
      final revision = revisions.single;
      expect(revision['seq'], 1);
      expect(revision['kind'], BeaconFactCardRevisionKindBits.copied);
      expect(revision['actor_id'], _actor);
      expect(revision['fact_text'], prepared.factText);
      expect(
        decodeJson(revision['attachments_json']),
        jsonDecode(prepared.attachmentsJson),
      );
    }

    /// The facts-brought line is by the actor in [beaconId].
    void expectLineMeta(Map<String, Object?> line, String beaconId) {
      expect(line['semantic_marker'], BeaconRoomSemanticMarker.factsBrought);
      expect(line['author_id'], _actor);
      expect(line['beacon_id'], beaconId);
    }

    /// One factPinned event for [factId], pointing at [lineId].
    void expectFactPinnedEvent({
      required List<Map<String, Object?>> events,
      required String factId,
      required String factText,
      required Object? lineId,
    }) {
      final event = events.singleWhere((e) => e['fact_card_id'] == factId);
      expect(event['type'], BeaconActivityEventTypeBits.factPinned);
      expect(event['visibility'], BeaconActivityEventVisibilityBits.room);
      expect(event['actor_id'], _actor);
      expect(event['source_message_id'], lineId);
      expect(decodeJson(event['diff']), {
        'factCardId': factId,
        'factText': factText,
      });
    }

    test(
      'two copies into a published Request: two live facts with origin, '
      'a copied revision 1 with the prepared attachments, one facts-brought '
      'line listing both and one factPinned event per fact',
      () async {
        final first = _copy(
          origin: 'Fsrcorig0001',
          seq: 3,
          text: 'Tap water is safe again',
          attachmentsJson: _imageAttachmentsJson('Aprepnew0001'),
        );
        final second = _copy(
          origin: 'Fsrcorig0002',
          text: 'Bridge reopens Monday',
        );

        final ids = await repository.insertPreparedCopies(
          destinationBeaconId: _pubTwo,
          actorUserId: _actor,
          prepared: [first, second],
        );

        expect(ids, hasLength(2));
        expect(ids.toSet(), hasLength(2), reason: 'two distinct new facts');
        final facts = await factsOf(_pubTwo);
        expect(facts.map((f) => f['id']).toSet(), ids.toSet());

        for (final (index, prepared) in [first, second].indexed) {
          final fact = facts.singleWhere((f) => f['id'] == ids[index]);
          expect(fact['beacon_id'], _pubTwo);
          expect(fact['fact_text'], prepared.factText);
          expect(fact['visibility'], BeaconFactCardVisibilityBits.room);
          expect(fact['pinned_by'], _actor);
          expect(fact['source_message_id'], isNull);
          expect(fact['status'], BeaconFactCardStatusBits.active);
          expect(fact['origin_fact_card_id'], prepared.originFactCardId);
          expect(fact['origin_revision_seq'], prepared.originRevisionSeq);
          expect(fact['revision_seq'], 1, reason: 'head is revision 1');
          expect(fact['origin_beacon_kind'], prepared.originBeaconKind);

          final revisions = await revisionsOf(ids[index]);
          expect(revisions, hasLength(1), reason: 'only revision 1');
          final revision = revisions.single;
          expect(revision['seq'], 1);
          expect(revision['kind'], BeaconFactCardRevisionKindBits.copied);
          expect(revision['actor_id'], _actor);
          expect(revision['fact_text'], prepared.factText);
          expect(
            decodeJson(revision['attachments_json']),
            jsonDecode(prepared.attachmentsJson),
            reason: 'revision 1 holds the prepared attachments',
          );
        }

        final lines = await factsBroughtLines(_pubTwo);
        expect(lines, hasLength(1), reason: 'exactly one facts-brought line');
        final line = lines.single;
        expect(line['semantic_marker'], BeaconRoomSemanticMarker.factsBrought);
        expect(line['author_id'], _actor);
        expect(line['beacon_id'], _pubTwo);
        final payload = payloadOf(line);
        expect(
          (payload['factCardIds']! as List).toSet(),
          ids.toSet(),
          reason: 'line lists both new fact ids',
        );
        expect(payload['count'], 2);
        expect(payload['originBeaconKind'], 0);
        expect(
          payload.containsKey('factText'),
          isFalse,
          reason: 'no factText when more than one fact was brought',
        );

        final events = await factPinnedEvents(_pubTwo);
        expect(events, hasLength(2), reason: 'one factPinned per new fact');
        for (final (index, prepared) in [first, second].indexed) {
          final event = events.singleWhere(
            (e) => e['fact_card_id'] == ids[index],
          );
          expect(event['type'], BeaconActivityEventTypeBits.factPinned);
          expect(event['visibility'], BeaconActivityEventVisibilityBits.room);
          expect(event['actor_id'], _actor);
          expect(event['source_message_id'], line['id']);
          expect(decodeJson(event['diff']), {
            'factCardId': ids[index],
            'factText': prepared.factText,
          });
        }
      },
      skip: skipReason,
    );

    test(
      'copies from both a Request and a Post give a line whose '
      'originBeaconKind is null',
      () async {
        final prepared = [
          _copy(origin: 'Fsrcmixed001', text: 'From a Request'),
          _copy(origin: 'Fsrcmixed002', kind: 1, text: 'From a Post'),
        ];
        final ids = await repository.insertPreparedCopies(
          destinationBeaconId: _pubMixed,
          actorUserId: _actor,
          prepared: prepared,
        );

        expect(ids, hasLength(2));
        expect(await factsOf(_pubMixed), hasLength(2));
        for (final (index, copy) in prepared.indexed) {
          await expectCopiedFact(
            beaconId: _pubMixed,
            factId: ids[index],
            prepared: copy,
          );
        }
        final lines = await factsBroughtLines(_pubMixed);
        expect(lines, hasLength(1));
        expectLineMeta(lines.single, _pubMixed);
        final payload = payloadOf(lines.single);
        expect((payload['factCardIds']! as List).toSet(), ids.toSet());
        expect(payload['count'], 2);
        expect(payload.containsKey('factText'), isFalse);
        expect(payload.containsKey('originBeaconKind'), isTrue);
        expect(payload['originBeaconKind'], isNull);
        final events = await factPinnedEvents(_pubMixed);
        expect(events, hasLength(2));
        for (final (index, copy) in prepared.indexed) {
          expectFactPinnedEvent(
            events: events,
            factId: ids[index],
            factText: copy.factText,
            lineId: lines.single['id'],
          );
        }
      },
      skip: skipReason,
    );

    test(
      'a single copy gives a line whose factText is the first 160 '
      'characters of the fact',
      () async {
        final longText = List.generate(200, (i) => 'abcdefghij'[i % 10]).join();
        final copy = _copy(
          origin: 'Fsrcsingle01',
          seq: 2,
          kind: 1,
          text: longText,
          attachmentsJson: _imageAttachmentsJson('Aprepsingle1'),
        );
        final ids = await repository.insertPreparedCopies(
          destinationBeaconId: _pubSingle,
          actorUserId: _actor,
          prepared: [copy],
        );

        expect(ids, hasLength(1));
        expect(await factsOf(_pubSingle), hasLength(1));
        await expectCopiedFact(
          beaconId: _pubSingle,
          factId: ids.single,
          prepared: copy,
        );
        final lines = await factsBroughtLines(_pubSingle);
        expect(lines, hasLength(1));
        expectLineMeta(lines.single, _pubSingle);
        final payload = payloadOf(lines.single);
        expect(payload['factCardIds'], [ids.single]);
        expect(payload['count'], 1);
        expect(payload['originBeaconKind'], 1);
        expect(payload['factText'], longText.substring(0, 160));
        final events = await factPinnedEvents(_pubSingle);
        expect(events, hasLength(1));
        expectFactPinnedEvent(
          events: events,
          factId: ids.single,
          factText: longText,
          lineId: lines.single['id'],
        );
      },
      skip: skipReason,
    );

    test(
      'an origin that already has a live copy is not copied again; only the '
      'other fact is announced and both ids come back in prepared order',
      () async {
        await seedLiveCopy(
          id: 'Fexisting001',
          beaconId: _pubPartial,
          originId: 'Fsrcpartial1',
        );
        final fresh = _copy(origin: 'Fsrcpartial2', text: 'Only this is new');

        final ids = await repository.insertPreparedCopies(
          destinationBeaconId: _pubPartial,
          actorUserId: _actor,
          prepared: [
            _copy(origin: 'Fsrcpartial1', text: 'Already brought'),
            fresh,
          ],
        );

        expect(ids, hasLength(2));
        expect(ids.first, 'Fexisting001');
        final newId = ids.last;
        expect(newId, isNot('Fexisting001'));

        final facts = await factsOf(_pubPartial);
        expect(facts, hasLength(2), reason: 'one existing + one new fact');
        final existing = facts.singleWhere((f) => f['id'] == ids.first);
        expect(existing['origin_fact_card_id'], 'Fsrcpartial1');
        expect(existing['fact_text'], 'earlier copy');
        await expectCopiedFact(
          beaconId: _pubPartial,
          factId: newId,
          prepared: fresh,
        );

        final lines = await factsBroughtLines(_pubPartial);
        expect(lines, hasLength(1));
        expectLineMeta(lines.single, _pubPartial);
        final payload = payloadOf(lines.single);
        expect(payload['factCardIds'], [newId]);
        expect(payload['count'], 1);
        expect(payload['factText'], fresh.factText);

        final events = await factPinnedEvents(_pubPartial);
        expect(events, hasLength(1));
        expectFactPinnedEvent(
          events: events,
          factId: newId,
          factText: fresh.factText,
          lineId: lines.single['id'],
        );
      },
      skip: skipReason,
    );

    test(
      'when every origin already has a live copy nothing is written and the '
      'existing id is returned',
      () async {
        await seedLiveCopy(
          id: 'Fexisting002',
          beaconId: _pubAllThere,
          originId: 'Fsrcallthr01',
        );

        final ids = await repository.insertPreparedCopies(
          destinationBeaconId: _pubAllThere,
          actorUserId: _actor,
          prepared: [_copy(origin: 'Fsrcallthr01', text: 'Again')],
        );

        expect(ids, ['Fexisting002']);
        expect(await factsOf(_pubAllThere), hasLength(1));
        expect(await factsBroughtLines(_pubAllThere), isEmpty);
        expect(await factPinnedEvents(_pubAllThere), isEmpty);
      },
      skip: skipReason,
    );

    test(
      'a removed earlier copy does not block a new copy of the same origin',
      () async {
        await seedLiveCopy(
          id: 'Fremoved0001',
          beaconId: _pubRemovedThere,
          originId: 'Fsrcremoved1',
          status: BeaconFactCardStatusBits.removed,
        );

        final copy = _copy(origin: 'Fsrcremoved1', text: 'Brought back');
        final ids = await repository.insertPreparedCopies(
          destinationBeaconId: _pubRemovedThere,
          actorUserId: _actor,
          prepared: [copy],
        );

        expect(ids, hasLength(1));
        expect(ids.single, isNot('Fremoved0001'));
        expect(await factsOf(_pubRemovedThere), hasLength(2));
        await expectCopiedFact(
          beaconId: _pubRemovedThere,
          factId: ids.single,
          prepared: copy,
        );
        final lines = await factsBroughtLines(_pubRemovedThere);
        expect(lines, hasLength(1), reason: 'the new copy is announced');
        expectLineMeta(lines.single, _pubRemovedThere);
        final payload = payloadOf(lines.single);
        expect(payload['factCardIds'], [ids.single]);
        expect(payload['count'], 1);
        expect(payload['originBeaconKind'], 0);
        expect(payload['factText'], copy.factText);
        final events = await factPinnedEvents(_pubRemovedThere);
        expect(events, hasLength(1));
        expectFactPinnedEvent(
          events: events,
          factId: ids.single,
          factText: copy.factText,
          lineId: lines.single['id'],
        );
      },
      skip: skipReason,
    );

    for (final (label, beaconId) in [
      ('a draft Request', _draftRequest),
      ('a Post without a root message', _rootlessPost),
    ]) {
      test(
        'into $label the facts and copied revisions are written but no '
        'facts-brought line and no factPinned event',
        () async {
          final prepared = [
            _copy(
              origin: 'Fsrcdraft${beaconId.substring(9)}a',
              text: 'Draft fact one',
              attachmentsJson: _imageAttachmentsJson('Aprepdraft01'),
            ),
            _copy(
              origin: 'Fsrcdraft${beaconId.substring(9)}b',
              kind: 1,
              text: 'Draft fact two',
            ),
          ];

          final ids = await repository.insertPreparedCopies(
            destinationBeaconId: beaconId,
            actorUserId: _actor,
            prepared: prepared,
          );

          expect(ids, hasLength(2));
          final facts = await factsOf(beaconId);
          expect(facts.map((f) => f['id']).toSet(), ids.toSet());
          for (final (index, copy) in prepared.indexed) {
            final fact = facts.singleWhere((f) => f['id'] == ids[index]);
            expect(fact['fact_text'], copy.factText);
            expect(fact['visibility'], BeaconFactCardVisibilityBits.room);
            expect(fact['pinned_by'], _actor);
            expect(fact['source_message_id'], isNull);
            expect(fact['status'], BeaconFactCardStatusBits.active);
            expect(fact['origin_fact_card_id'], copy.originFactCardId);
            expect(fact['origin_revision_seq'], copy.originRevisionSeq);
            expect(fact['revision_seq'], 1, reason: 'head is revision 1');
            expect(fact['origin_beacon_kind'], copy.originBeaconKind);
            final revision = (await revisionsOf(ids[index])).single;
            expect(revision['seq'], 1);
            expect(revision['kind'], BeaconFactCardRevisionKindBits.copied);
            expect(revision['actor_id'], _actor);
            expect(revision['fact_text'], copy.factText);
            expect(
              decodeJson(revision['attachments_json']),
              jsonDecode(copy.attachmentsJson),
            );
          }
          expect(await factsBroughtLines(beaconId), isEmpty);
          expect(await factPinnedEvents(beaconId), isEmpty);
        },
        skip: skipReason,
      );
    }

    for (final (label, beaconId) in [
      ('a missing destination', _missingBeacon),
      ('a deleted destination', _deletedRequest),
    ]) {
      test(
        '$label throws UnauthorizedException and writes nothing',
        () async {
          final before = await totals();
          await expectLater(
            repository.insertPreparedCopies(
              destinationBeaconId: beaconId,
              actorUserId: _actor,
              prepared: [
                _copy(
                  origin: 'Fsrcgone${beaconId.substring(9)}',
                  text: 'Nowhere to go',
                ),
              ],
            ),
            throwsA(isA<UnauthorizedException>()),
          );
          expect(await countRows('beacon_fact_card', beaconId), 0);
          expect(await revisionsOnBeacon(beaconId), 0);
          expect(await countRows('beacon_room_message', beaconId), 0);
          expect(await countRows('beacon_activity_event', beaconId), 0);
          expect(
            await totals(),
            before,
            reason: 'no fact, revision, line or event written on any beacon',
          );
        },
        skip: skipReason,
      );
    }

    test(
      'joins the ambient transaction of the same actor, so rolling it back '
      'removes the copies',
      () async {
        List<String>? idsInside;
        await expectLater(
          db.withMutatingUser(_actor, () async {
            idsInside = await repository.insertPreparedCopies(
              destinationBeaconId: _pubAmbient,
              actorUserId: _actor,
              prepared: [
                _copy(origin: 'Fsrcambient1', text: 'Rolled back'),
              ],
            );
            final seen = await db
                .customSelect(
                  'SELECT count(*)::integer AS n FROM public.beacon_fact_card '
                  r'WHERE beacon_id = $1::text',
                  variables: [const Variable<String>(_pubAmbient)],
                )
                .getSingle();
            expect(seen.read<int>('n'), 1, reason: 'visible inside the tx');
            throw const _Rollback();
          }),
          throwsA(isA<_Rollback>()),
        );

        expect(idsInside, hasLength(1));
        expect(await factsOf(_pubAmbient), isEmpty);
        expect(await revisionsOf(idsInside!.single), isEmpty);
        expect(await factsBroughtLines(_pubAmbient), isEmpty);
        expect(await factPinnedEvents(_pubAmbient), isEmpty);
      },
      skip: skipReason,
    );
  });
}

PreparedFactCopy _copy({
  required String origin,
  required String text,
  int seq = 1,
  int kind = 0,
  String attachmentsJson = '[]',
}) => PreparedFactCopy(
  originFactCardId: origin,
  originRevisionSeq: seq,
  originBeaconKind: kind,
  factText: text,
  attachmentsJson: attachmentsJson,
  newImageIds: attachmentsJson == '[]' ? const <String>[] : const [_imageId],
);

String _imageAttachmentsJson(String attachmentId) => jsonEncode([
  {
    'id': attachmentId,
    'kind': 'image',
    'position': 0,
    'mime': 'image/jpeg',
    'sizeBytes': 1024,
    'fileName': 'tap.jpg',
    'imageId': _imageId,
    'imageAuthorId': _actor,
    'blurHash': 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
    'width': 640,
    'height': 480,
  },
]);

final class _Rollback implements Exception {
  const _Rollback();
}

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Fact Copier', @key)
'''),
    parameters: {'id': _actor, 'key': pgTestPublicKey('factprepcopy', 1)},
  );
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES ('$_pubTwo', '$_actor', 'Two', '', 0, 0, now(), false),
       ('$_pubMixed', '$_actor', 'Mixed', '', 0, 0, now(), false),
       ('$_pubSingle', '$_actor', 'Single', '', 0, 0, now(), false),
       ('$_pubPartial', '$_actor', 'Partial', '', 0, 0, now(), false),
       ('$_pubAllThere', '$_actor', 'All there', '', 0, 0, now(), false),
       ('$_pubRemovedThere', '$_actor', 'Removed', '', 0, 0, now(), false),
       ('$_deletedRequest', '$_actor', 'Deleted', '', 0, 0, now(), false),
       ('$_pubAmbient', '$_actor', 'Ambient', '', 0, 0, now(), false),
       ('$_draftRequest', '$_actor', 'Draft', '', 3, 0, NULL, false)
''');
  await writer.execute(
    "UPDATE public.beacon SET status = 2 WHERE id = '$_deletedRequest'",
  );
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES ('$_rootlessPost', '$_actor', '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours')
''');
}
