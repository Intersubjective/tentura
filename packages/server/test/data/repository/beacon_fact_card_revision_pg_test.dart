@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// tentura-617.13 / issue #181: `pinFact` must write a `beacon_fact_card_revision`
/// row (seq 1, kind `created`, actor = pinner) alongside the `beacon_fact_card`
/// it inserts — the same shape `m0199`'s backfill gives pre-existing facts (see
/// `m0199_fact_history_migration_pg_test.dart`). Today `pinFact` only writes the
/// card, room message and activity event, so every test below fails.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_REVISION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_revision',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group(
    'BeaconFactCardRepository.pinFact revision row — disposable Postgres',
    () {
      DisposablePgWriterSession? session;
      late Connection writer;
      late TenturaDb db;
      late BeaconFactCardRepository factCards;
      var pgSetupComplete = false;

      const pinnerId = 'Ufcrpgpin01';
      const otherEditorId = 'Ufcrpgoth01';
      const beaconId = 'Bfcrpgmain1';

      setUpAll(() async {
        if (skipReason != false) return;
        session = await setUpDisposablePgWriter(target: target);
        writer = session!.writer;
        db = openDisposablePgDatabase(target);
        factCards = BeaconFactCardRepository(db, BeaconRoomRepository(db));
        for (final entry in <(String, int)>[
          (pinnerId, 1),
          (otherEditorId, 2),
        ]) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
            parameters: {
              'id': entry.$1,
              'publicKey': pgTestPublicKey('fcrpg', entry.$2),
            },
          );
        }
        await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('$beaconId', '$pinnerId', 'Fact revision PG', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
        pgSetupComplete = true;
      });

      tearDown(() async {
        if (skipReason != false) return;
        await writer.execute(
          "DELETE FROM public.beacon_fact_card_revision WHERE fact_card_id IN "
          "(SELECT id FROM public.beacon_fact_card WHERE beacon_id = '$beaconId')",
        );
        await writer.execute(
          "DELETE FROM public.beacon_activity_event WHERE beacon_id = '$beaconId'",
        );
        await writer.execute(
          "DELETE FROM public.beacon_room_message WHERE beacon_id = '$beaconId'",
        );
        await writer.execute(
          "DELETE FROM public.beacon_fact_card WHERE beacon_id = '$beaconId'",
        );
      });

      tearDownAll(() async {
        if (skipReason != false || !pgSetupComplete || session == null) {
          return;
        }
        await tearDownDisposablePgWriter(session: session!, drift: db);
      });

      Future<List<Map<String, Object?>>> revisionsFor(
        String factCardId,
      ) async {
        final rows = await writer.execute(
          Sql.named('''
SELECT seq, kind, actor_id, fact_text, id, fact_card_id
FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id
ORDER BY seq
'''),
          parameters: {'id': factCardId},
        );
        return [
          for (final r in rows)
            {
              'seq': r[0],
              'kind': r[1],
              'actor_id': r[2],
              'fact_text': r[3],
              'id': r[4],
              'fact_card_id': r[5],
            },
        ];
      }

      void expectRevisionMatchesCard(
        Map<String, Object?> revision,
        BeaconFactCardEntity card, {
        required String actorId,
      }) {
        expect(
          revision['fact_card_id'],
          card.id,
          reason: 'revision must be linked to its own fact card',
        );
        expect(revision['seq'], 1, reason: '${card.id} seq');
        expect(
          revision['kind'],
          BeaconFactCardRevisionKindBits.created,
          reason: '${card.id} kind',
        );
        expect(revision['actor_id'], actorId, reason: '${card.id} actor');
        expect(
          revision['fact_text'],
          card.factText,
          reason: '${card.id} fact_text',
        );
      }

      test(
        'pinFact records a seq-1 created revision authored by the pinner',
        () async {
          final card = await factCards.pinFact(
            beaconId: beaconId,
            factText: 'Water is on at the corner tap',
            visibility: BeaconFactCardVisibilityBits.public,
            pinnedBy: pinnerId,
          );

          final revisions = await revisionsFor(card.id);

          expect(
            revisions,
            hasLength(1),
            reason: 'pinFact must insert exactly one revision row per fact',
          );
          final revision = revisions.single;
          expect(revision['seq'], 1);
          expect(revision['kind'], BeaconFactCardRevisionKindBits.created);
          expect(revision['actor_id'], pinnerId);
          expect(revision['fact_text'], card.factText);
          expect(card.factText, 'Water is on at the corner tap');
          expect(revision['id'], isNotNull);
        },
        skip: skipReason,
      );

      test(
        'the revision text is trimmed the same way the card text is',
        () async {
          final card = await factCards.pinFact(
            beaconId: beaconId,
            factText: '  Bring your own charger  ',
            visibility: BeaconFactCardVisibilityBits.room,
            pinnedBy: otherEditorId,
          );

          expect(card.factText, 'Bring your own charger');

          final revisions = await revisionsFor(card.id);
          expect(revisions, hasLength(1));
          expect(revisions.single['fact_text'], card.factText);
        },
        skip: skipReason,
      );

      test(
        'two facts pinned on the same beacon each keep their own single '
        'revision',
        () async {
          final first = await factCards.pinFact(
            beaconId: beaconId,
            factText: 'First fact',
            visibility: BeaconFactCardVisibilityBits.public,
            pinnedBy: pinnerId,
          );
          final second = await factCards.pinFact(
            beaconId: beaconId,
            factText: 'Second fact',
            visibility: BeaconFactCardVisibilityBits.public,
            pinnedBy: otherEditorId,
          );

          final firstRevisions = await revisionsFor(first.id);
          final secondRevisions = await revisionsFor(second.id);
          expect(firstRevisions, hasLength(1));
          expect(secondRevisions, hasLength(1));

          expectRevisionMatchesCard(
            firstRevisions.single,
            first,
            actorId: pinnerId,
          );
          expectRevisionMatchesCard(
            secondRevisions.single,
            second,
            actorId: otherEditorId,
          );
        },
        skip: skipReason,
      );
    },
  );
}
