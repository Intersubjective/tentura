@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

/// tentura-617.6 (issue #181 plan §8.3 "Pin", §14.3 pinFact, §14.4, §14.5):
/// pinning is one `ON CONFLICT` CTE inside `withMutatingUser` that writes the
/// fact, its seq-1 revision, the source link, the pin line and the
/// `factPinned` event (with `fact_card_id`). Source ownership is an EXISTS
/// inside the CTE; `DO NOTHING` costs one extra read for the existing id and
/// surfaces as [BeaconFactCardAlreadyPinnedException]. The empty-text check
/// runs in the use case, before any statement.
///
/// `BeaconFactCardCase.pin` costs exactly 5 statements: the fused
/// `loadRoomAccess` preflight, BEGIN, the `set_config` actor line, the CTE and
/// COMMIT.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_PIN_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_pin',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardCase.pin — disposable Postgres', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late QueryCounter counter;
    late BeaconFactCardCase useCase;

    BeaconFactCardCase buildUseCase(TenturaDb database) {
      final room = BeaconRoomRepository(database);
      return BeaconFactCardCase(
        BeaconFactCardRepository(database, room),
        room,
        BeaconHierarchyRepository(database),
        BeaconAccessRepository(database),
        env: Env(environment: Environment.test),
        logger: Logger('BeaconFactCardPinPgTest'),
      );
    }

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await _seed(writer);

        counter = QueryCounter();
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ).interceptWith(counter),
        );
        useCase = buildUseCase(db);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    Future<int> countOf(String sql, Map<String, Object?> parameters) async {
      final rows = await writer.execute(Sql.named(sql), parameters: parameters);
      return rows.single.single! as int;
    }

    Future<int> liveFactsForSource(String sourceId) => countOf(
      '''
SELECT count(*)::integer FROM public.beacon_fact_card
WHERE source_message_id = @src AND status IN (0, 1)
''',
      {'src': sourceId},
    );

    test(
      'pin writes 1 fact, a seq-1 created revision by the pinner, the source '
      'link, the pin line and a factPinned event carrying fact_card_id',
      () async {
        final result = await useCase.pin(
          beaconId: _beaconId,
          factText: '  Water is on at the corner tap  ',
          visibility: BeaconFactCardVisibilityBits.public,
          userId: _pinnerId,
          sourceMessageId: _sourceLinkId,
        );
        final factId = result['id']! as String;
        expect(result['beaconId'], _beaconId);

        final facts = await writer.execute(
          Sql.named('''
SELECT fact_text, visibility, pinned_by, source_message_id, status,
       revision_seq
FROM public.beacon_fact_card
WHERE source_message_id = @src
'''),
          parameters: {'src': _sourceLinkId},
        );
        expect(facts, hasLength(1), reason: 'exactly one fact per pin');
        final fact = facts.single;
        expect(fact[0], 'Water is on at the corner tap');
        expect(fact[1], BeaconFactCardVisibilityBits.public);
        expect(fact[2], _pinnerId);
        expect(fact[3], _sourceLinkId);
        expect(fact[4], BeaconFactCardStatusBits.active);
        expect(fact[5], 1);

        final revisions = await writer.execute(
          Sql.named('''
SELECT seq, kind, actor_id, fact_text
FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id
'''),
          parameters: {'id': factId},
        );
        expect(revisions, hasLength(1), reason: 'exactly one revision');
        final revision = revisions.single;
        expect(revision[0], 1, reason: 'seq');
        expect(
          revision[1],
          BeaconFactCardRevisionKindBits.created,
          reason: 'kind',
        );
        expect(revision[2], _pinnerId, reason: 'actor = pinner');
        expect(revision[3], 'Water is on at the corner tap');

        final link = await writer.execute(
          Sql.named(
            'SELECT linked_fact_card_id FROM public.beacon_room_message '
            'WHERE id = @src',
          ),
          parameters: {'src': _sourceLinkId},
        );
        expect(link.single.single, factId, reason: 'source message linked');

        final pinLines = await countOf(
          '''
SELECT count(*)::integer FROM public.beacon_room_message
WHERE beacon_id = @beacon
  AND semantic_marker = ${BeaconRoomSemanticMarker.pinFactPublic}
  AND system_payload->>'factCardId' = @id
''',
          {'beacon': _beaconId, 'id': factId},
        );
        expect(pinLines, 1, reason: 'one pin line in the room');

        final events = await writer.execute(
          Sql.named('''
SELECT fact_card_id, actor_id, visibility, source_message_id,
       diff->>'factCardId'
FROM public.beacon_activity_event
WHERE beacon_id = @beacon
  AND type = ${BeaconActivityEventTypeBits.factPinned}
  AND diff->>'factCardId' = @id
'''),
          parameters: {'beacon': _beaconId, 'id': factId},
        );
        expect(events, hasLength(1), reason: 'one factPinned event');
        final event = events.single;
        expect(
          event[0],
          factId,
          reason: 'factPinned event must carry the fact_card_id column',
        );
        expect(event[1], _pinnerId);
        expect(event[2], BeaconActivityEventVisibilityBits.public);
        expect(event[3], _sourceLinkId);
        expect(event[4], factId);
      },
      skip: skipReason,
    );

    test(
      'pin through the use case costs exactly 5 statements',
      () async {
        counter.reset();
        await useCase.pin(
          beaconId: _beaconId,
          factText: 'Counted pin',
          visibility: BeaconFactCardVisibilityBits.room,
          userId: _pinnerId,
          sourceMessageId: _sourceCountId,
        );
        expect(
          counter.count,
          5,
          reason:
              'loadRoomAccess + BEGIN + set_config + one pin CTE + COMMIT',
        );
        expect(await liveFactsForSource(_sourceCountId), 1);
      },
      skip: skipReason,
    );

    test(
      're-pinning the same source throws '
      'BeaconFactCardAlreadyPinnedException with the existing id',
      () async {
        final first = await useCase.pin(
          beaconId: _beaconId,
          factText: 'First pin',
          visibility: BeaconFactCardVisibilityBits.public,
          userId: _pinnerId,
          sourceMessageId: _sourceRepinId,
        );
        final existingId = first['id']! as String;

        await expectLater(
          useCase.pin(
            beaconId: _beaconId,
            factText: 'Second pin',
            visibility: BeaconFactCardVisibilityBits.public,
            userId: _pinnerId,
            sourceMessageId: _sourceRepinId,
          ),
          throwsA(
            isA<BeaconFactCardAlreadyPinnedException>().having(
              (e) => e.existingFactCardId,
              'existingFactCardId',
              existingId,
            ),
          ),
        );
        expect(await liveFactsForSource(_sourceRepinId), 1);
        final revisions = await countOf(
          '''
SELECT count(*)::integer FROM public.beacon_fact_card_revision r
JOIN public.beacon_fact_card f ON f.id = r.fact_card_id
WHERE f.source_message_id = @src
''',
          {'src': _sourceRepinId},
        );
        expect(revisions, 1, reason: 'the refused pin writes no revision');
      },
      skip: skipReason,
    );

    test(
      'two concurrent pins of one source on two connections leave exactly '
      'one live fact; the loser gets the winner id',
      () async {
        final otherDb = openDisposablePgDatabase(target);
        try {
          final otherUseCase = buildUseCase(otherDb);
          Future<Object> attempt(BeaconFactCardCase c, String text) => c
              .pin(
                beaconId: _beaconId,
                factText: text,
                visibility: BeaconFactCardVisibilityBits.public,
                userId: _pinnerId,
                sourceMessageId: _sourceRaceId,
              )
              .then<Object>((r) => r, onError: (Object e) => e);

          final outcomes = await Future.wait([
            attempt(useCase, 'Race A'),
            attempt(otherUseCase, 'Race B'),
          ]);

          final winners = outcomes.whereType<Map<String, Object?>>().toList();
          final losers = outcomes
              .whereType<BeaconFactCardAlreadyPinnedException>()
              .toList();
          expect(
            winners,
            hasLength(1),
            reason: 'outcomes: $outcomes',
          );
          expect(
            losers,
            hasLength(1),
            reason: 'the losing pin must map to FactAlreadyPinned, '
                'not a raw unique violation; outcomes: $outcomes',
          );
          expect(losers.single.existingFactCardId, winners.single['id']);
          expect(await liveFactsForSource(_sourceRaceId), 1);
        } finally {
          await otherDb.close();
        }
      },
      skip: skipReason,
    );

    test(
      'a source message of another beacon writes no fact',
      () async {
        await expectLater(
          useCase.pin(
            beaconId: _beaconId,
            factText: 'Foreign source',
            visibility: BeaconFactCardVisibilityBits.public,
            userId: _pinnerId,
            sourceMessageId: _foreignSourceId,
          ),
          throwsA(isA<ExceptionBase>()),
        );
        expect(
          await countOf(
            '''
SELECT count(*)::integer FROM public.beacon_fact_card
WHERE source_message_id = @src OR fact_text = 'Foreign source'
''',
            {'src': _foreignSourceId},
          ),
          0,
        );
        final link = await writer.execute(
          Sql.named(
            'SELECT linked_fact_card_id FROM public.beacon_room_message '
            'WHERE id = @src',
          ),
          parameters: {'src': _foreignSourceId},
        );
        expect(link.single.single, isNull);
      },
      skip: skipReason,
    );

    test(
      'whitespace-only text throws BeaconCreateException with 0 statements',
      () async {
        counter.reset();
        await expectLater(
          useCase.pin(
            beaconId: _beaconId,
            factText: ' \n\t  ',
            visibility: BeaconFactCardVisibilityBits.public,
            userId: _pinnerId,
            sourceMessageId: _sourceBlankId,
          ),
          throwsA(isA<BeaconCreateException>()),
        );
        expect(counter.count, 0, reason: 'empty text is refused up front');
        expect(await liveFactsForSource(_sourceBlankId), 0);
      },
      skip: skipReason,
    );
  });
}

// ---------------------------------------------------------------------------
// Fixture: one published beacon authored by the pinner (so the pinner can use
// the room), another beacon by the same author, one room message per test on
// the main beacon and one message on the other beacon.

const _pinnerId = 'Ufppinner01';

const _beaconId = 'Bfpbeacon01';
const _otherBeaconId = 'Bfpbeacon02';

const _sourceLinkId = 'Rfpsrclink1';
const _sourceCountId = 'Rfpsrccnt01';
const _sourceRepinId = 'Rfpsrcrepin';
const _sourceRaceId = 'Rfpsrcrace1';
const _sourceBlankId = 'Rfpsrcblank';
const _foreignSourceId = 'Rfpsrcforgn';

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Fact Pinner', @key)
'''),
    parameters: {'id': _pinnerId, 'key': pgTestPublicKey('factpin', 1)},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES
  (@beacon, @author, 't', 'd', 0, @t0, false),
  (@other, @author, 't2', 'd2', 0, @t0, false)
'''),
    parameters: {
      'beacon': _beaconId,
      'other': _otherBeaconId,
      'author': _pinnerId,
      't0': _t0,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  (@link, @beacon, @author, 'link source'),
  (@count, @beacon, @author, 'count source'),
  (@repin, @beacon, @author, 'repin source'),
  (@race, @beacon, @author, 'race source'),
  (@blank, @beacon, @author, 'blank source'),
  (@foreign, @other, @author, 'foreign source')
'''),
    parameters: {
      'link': _sourceLinkId,
      'count': _sourceCountId,
      'repin': _sourceRepinId,
      'race': _sourceRaceId,
      'blank': _sourceBlankId,
      'foreign': _foreignSourceId,
      'beacon': _beaconId,
      'other': _otherBeaconId,
      'author': _pinnerId,
    },
  );
}
