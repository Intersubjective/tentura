@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/room_baton_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/room_baton_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/mocks/invite_seed_prompt_repository_mock.dart';

// «Take it on together» selection (docs/plans/baton-together-plan.md §2.4,
// §2.8): a pick resolves the baton to an accepted pair, writes the pair into
// the marker-12 message and tells both people.

const _author = 'Ubatonpairsel_au1';
const _candA = 'Ubatonpairsel_ca1';
const _candB = 'Ubatonpairsel_cb1';
const _candC = 'Ubatonpairsel_cc1';
const _partnerX = 'Ubatonpairsel_px1';
const _partnerY = 'Ubatonpairsel_py1';
const _outsider = 'Ubatonpairsel_ou1';

const _request = 'Bbatonpairsel_rq1';
const _ask = 'Who can bring the ladder?';

const _taken = 'batonTaken';
const _collecting = 0;
const _selected = 1;
const _cancelled = 2;
const _manual = 2;
const _auto = 1;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_BATON_PAIR_SELECT_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_baton_pair_select',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('RoomBatonCase.select with pairs', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late RoomBatonCase batonCase;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      batonCase = _buildCase(database, target.databaseEnv);
    });

    setUp(() => _resetFixture(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<RoomBaton> createBaton({
      List<({String userId, int tier})>? candidates,
    }) => batonCase.create(
      actorId: _author,
      beaconId: _request,
      text: _ask,
      candidates:
          candidates ?? [(userId: _candA, tier: 1), (userId: _candB, tier: 1)],
    );

    Future<void> respond(
      String actorId,
      RoomBaton baton, {
      required bool canHelp,
      String? partnerUserId,
    }) => batonCase.respond(
      actorId: actorId,
      batonId: baton.id,
      canHelp: canHelp,
      partnerUserId: partnerUserId,
    );

    Future<void> partnerRespond(
      String actorId,
      RoomBaton baton, {
      required String inviter,
      required bool accept,
    }) => batonCase.partnerRespond(
      actorId: actorId,
      batonId: baton.id,
      inviterUserId: inviter,
      accept: accept,
    );

    Future<RoomBaton> acceptedPair({
      List<({String userId, int tier})>? candidates,
    }) async {
      final baton = await createBaton(candidates: candidates);
      await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
      await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);
      return baton;
    }

    group('an accepted pair', () {
      for (final (label, picked) in [
        ('the asked person', _candA),
        ('the partner', _partnerX),
      ]) {
        test('picking $label records taker and co-taker, manual', () async {
          final baton = await acceptedPair();

          await batonCase.select(
            actorId: _author,
            batonId: baton.id,
            userId: picked,
          );

          final row = await _batonRow(writer, baton.id);
          expect(row.status, _selected);
          expect(row.taker, _candA);
          expect(row.coTaker, _partnerX);
          expect(row.mode, _manual);
          expect(row.resolvedAt, isNotNull);
        });
      }

      for (final (label, picked) in [
        ('the asked person', _candA),
        ('the partner', _partnerX),
      ]) {
        test('picking $label writes a marker naming both people and nothing '
            'else', () async {
          final baton = await acceptedPair();

          await batonCase.select(
            actorId: _author,
            batonId: baton.id,
            userId: picked,
          );

          final markers = await _markerPayloads(writer);
          expect(markers, hasLength(1));
          expect(markers.single.keys.toSet(), {
            'batonId',
            'sourceMessageId',
            'takerUserId',
            'coTakerUserId',
          });
          expect(markers.single['takerUserId'], _candA);
          expect(markers.single['coTakerUserId'], _partnerX);
        });

        test('picking $label sends each of the two a batonTaken receipt '
            'naming the other', () async {
          final baton = await acceptedPair();
          final before = await _receiptCount(writer, _taken);

          await batonCase.select(
            actorId: _author,
            batonId: baton.id,
            userId: picked,
          );

          expect(await _receiptCount(writer, _taken), before + 2);
          expect(await _receiptRecipients(writer, _taken), [
            _candA,
            _partnerX,
          ]);
          expect(await _withUserId(writer, _candA), _partnerX);
          expect(await _withUserId(writer, _partnerX), _candA);
        });
      }

      test('pick for me prefers the tier-1 pair over a tier-2 solo', () async {
        final baton = await createBaton(
          candidates: [(userId: _candA, tier: 1), (userId: _candC, tier: 2)],
        );
        await respond(_candC, baton, canHelp: true);
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
        await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);

        await batonCase.select(actorId: _author, batonId: baton.id);

        final row = await _batonRow(writer, baton.id);
        expect(row.status, _selected);
        expect(row.taker, _candA);
        expect(row.coTaker, _partnerX);
        expect(row.mode, _auto);
      });

      test(
        'a mutual pair gives the taker role to whoever answered first',
        () async {
          final baton = await createBaton();
          await respond(_candA, baton, canHelp: true, partnerUserId: _candB);
          await respond(_candB, baton, canHelp: true, partnerUserId: _candA);
          final states = await _partnerStates(writer, baton.id);
          expect(states[_candA], (_candB, 1));
          expect(states[_candB], (_candA, 1));

          await batonCase.select(
            actorId: _author,
            batonId: baton.id,
            userId: _candB,
          );

          final row = await _batonRow(writer, baton.id);
          expect(row.taker, _candA);
          expect(row.coTaker, _candB);
          final payload = (await _markerPayloads(writer)).single;
          expect(payload['takerUserId'], _candA);
          expect(payload['coTakerUserId'], _candB);
        },
      );
    });

    group('a pair that cannot be picked', () {
      Future<void> expectNotPickable(RoomBaton baton, String userId) async {
        await expectLater(
          batonCase.select(
            actorId: _author,
            batonId: baton.id,
            userId: userId,
          ),
          throwsA(isA<BatonTakerNotAvailableException>()),
        );
        final row = await _batonRow(writer, baton.id);
        expect(row.status, _collecting);
        expect(row.taker, isNull);
        expect(row.coTaker, isNull);
        expect(await _markerPayloads(writer), isEmpty);
      }

      test('a pending partner makes neither person pickable', () async {
        final baton = await createBaton();
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);

        await expectNotPickable(baton, _candA);
        await expectNotPickable(baton, _partnerX);
      });

      test('a partner who left the room makes the pair not pickable', () async {
        final baton = await acceptedPair();
        await writer.execute('''
UPDATE public.beacon_participant SET room_access = ${RoomAccessBits.left}
WHERE beacon_id = '$_request' AND user_id = '$_partnerX'
''');

        await expectNotPickable(baton, _candA);
        await expectNotPickable(baton, _partnerX);
      });

      test('a block between the pair makes it not pickable', () async {
        final baton = await acceptedPair();
        await writer.execute(
          Sql.named(
            'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
            'VALUES (@x, @y, @x)',
          ),
          parameters: {'x': _candA, 'y': _partnerX},
        );

        await expectNotPickable(baton, _candA);
        await expectNotPickable(baton, _partnerX);
      });
    });

    group('editing and cancelling', () {
      for (final accept in [false, true]) {
        test(
          'removing the asker drops their '
          '${accept ? 'accepted' : 'pending'} invitation',
          () async {
            final baton = await createBaton();
            await respond(
              _candA,
              baton,
              canHelp: true,
              partnerUserId: _partnerX,
            );
            if (accept) {
              await partnerRespond(
                _partnerX,
                baton,
                inviter: _candA,
                accept: true,
              );
            }
            final before = await _receiptsOf(writer, _partnerX);

            await batonCase.update(
              actorId: _author,
              batonId: baton.id,
              text: _ask,
              candidates: [(userId: _candB, tier: 1)],
            );

            expect(
              await _partnerNames(writer, baton.id),
              isNot(contains(_partnerX)),
            );
            expect(await _receiptsOf(writer, _partnerX), before);
          },
        );
      }

      test(
        'cancelling an accepted pair writes no marker and no receipt',
        () async {
          final baton = await acceptedPair();
          final before = await _receiptCount(writer, _taken);

          await batonCase.cancel(actorId: _author, batonId: baton.id);

          final row = await _batonRow(writer, baton.id);
          expect(row.status, _cancelled);
          expect(row.taker, isNull);
          expect(row.coTaker, isNull);
          expect(await _markerPayloads(writer), isEmpty);
          expect(await _receiptCount(writer, _taken), before);
        },
      );
    });

    test('a solo pick keeps the old shape', () async {
      final baton = await createBaton();
      await respond(_candB, baton, canHelp: true);

      await batonCase.select(
        actorId: _author,
        batonId: baton.id,
        userId: _candB,
      );

      final row = await _batonRow(writer, baton.id);
      expect(row.taker, _candB);
      expect(row.coTaker, isNull);
      final payload = (await _markerPayloads(writer)).single;
      expect(payload.keys.toSet(), {
        'batonId',
        'sourceMessageId',
        'takerUserId',
      });
      expect(await _receiptRecipients(writer, _taken), [_candB]);
      expect(
        await _blob(writer, _taken, _candB),
        isNot(contains('withUserId')),
      );
    });
  });
}

/// Blocks are real `public.user_block` rows read through the real
/// [UserBlockRepository] (`block_hides`), the same port instance the
/// attention intents use; the case must see blocks through it too.
RoomBatonCase _buildCase(TenturaDb db, Env env) {
  final logger = Logger('RoomBatonPairSelectPgTest');
  final blocks = UserBlockRepository(env, db);
  final room = BeaconRoomRepository(db);
  final attention = TransactionalAttentionCase(
    MutatingUnitOfWork(db),
    AttentionDispatchRepository(db, logger),
  );
  final attentionIntents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      room,
      db,
      HelpOfferRepository(db),
      CommitmentRepository(db),
    ),
    UserRepository(
      env,
      db,
      _NoopInviteGenealogyRepository(),
      InviteSeedPromptRepositoryMock(),
    ),
    BeaconAccessRepository(db),
    blocks,
  );
  return RoomBatonCase(
    RoomBatonRepository(db),
    room,
    BeaconHierarchyRepository(db),
    PostLockRepository(db),
    attention,
    attentionIntents,
    env: env,
    logger: logger,
  );
}

typedef _BatonRow = ({
  int status,
  int? mode,
  String? taker,
  String? coTaker,
  Object? resolvedAt,
});

Future<_BatonRow> _batonRow(Connection writer, String batonId) async {
  final r = (await writer.execute(
    Sql.named('''
SELECT status, selection_mode, taker_id, co_taker_id, resolved_at
FROM public.beacon_room_baton WHERE id = @id
'''),
    parameters: {'id': batonId},
  )).single;
  return (
    status: r[0]! as int,
    mode: r[1] as int?,
    taker: r[2] as String?,
    coTaker: r[3] as String?,
    resolvedAt: r[4],
  );
}

Future<List<Map<String, Object?>>> _markerPayloads(Connection writer) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT system_payload::text FROM public.beacon_room_message
WHERE semantic_marker = @marker
'''),
    parameters: {'marker': BeaconRoomSemanticMarker.batonTaken},
  );
  return [
    for (final r in rows)
      (jsonDecode(r[0]! as String) as Map).cast<String, Object?>(),
  ];
}

Future<int> _receiptCount(Connection writer, String eventType) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT count(*) FROM public.attention_occurrence_recipient AS recipient
JOIN public.attention_occurrence AS occ ON occ.id = recipient.occurrence_id
WHERE occ.event_type = @type
'''),
    parameters: {'type': eventType},
  );
  return rows.single[0]! as int;
}

Future<List<String>> _receiptRecipients(Connection writer, String type) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT recipient.account_id
FROM public.attention_occurrence_recipient AS recipient
JOIN public.attention_occurrence AS occ ON occ.id = recipient.occurrence_id
WHERE occ.event_type = @type ORDER BY recipient.account_id
'''),
    parameters: {'type': type},
  );
  return rows.map((r) => r[0]! as String).toList();
}

/// Every receipt [recipient] holds, as `eventType:sourceEventKey`.
Future<List<String>> _receiptsOf(Connection writer, String recipient) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT occ.event_type || ':' || occ.source_event_key
FROM public.attention_occurrence_recipient AS recipient
JOIN public.attention_occurrence AS occ ON occ.id = recipient.occurrence_id
WHERE recipient.account_id = @recipient ORDER BY 1
'''),
    parameters: {'recipient': recipient},
  );
  return rows.map((r) => r[0]! as String).toList();
}

Future<List<String>> _partnerNames(Connection writer, String batonId) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT partner_user_id FROM public.beacon_room_baton_candidate
WHERE baton_id = @id AND partner_user_id IS NOT NULL
'''),
    parameters: {'id': batonId},
  );
  return rows.map((r) => r[0]! as String).toList();
}

/// `withUserId` fact of [recipient]'s batonTaken receipt (outbox payload).
Future<String?> _withUserId(Connection writer, String recipient) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT outbox.presentation_payload ->> 'withUserId'
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = 'batonTaken' AND outbox.account_id = @recipient
'''),
    parameters: {'recipient': recipient},
  );
  return rows.single[0] as String?;
}

Future<Map<String, (String?, int?)>> _partnerStates(
  Connection writer,
  String batonId,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT user_id, partner_user_id, partner_response
FROM public.beacon_room_baton_candidate WHERE baton_id = @id
'''),
    parameters: {'id': batonId},
  );
  return {
    for (final r in rows) r[0]! as String: (r[1] as String?, r[2] as int?),
  };
}

Future<String> _blob(Connection writer, String type, String recipient) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT row_to_json(occ)::text || row_to_json(recipient)::text
  || COALESCE((SELECT string_agg(row_to_json(outbox)::text, '')
     FROM public.notification_outbox AS outbox
     WHERE outbox.occurrence_id = occ.id
       AND outbox.account_id = recipient.account_id), '')
FROM public.attention_occurrence_recipient AS recipient
JOIN public.attention_occurrence AS occ ON occ.id = recipient.occurrence_id
WHERE occ.event_type = @type AND recipient.account_id = @recipient
'''),
    parameters: {'type': type, 'recipient': recipient},
  );
  return rows.map((r) => r[0]! as String).join();
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_room_baton_candidate,
  public.beacon_room_baton,
  public.beacon_room_message,
  public.user_block,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [
    _author,
    _candA,
    _candB,
    _candC,
    _partnerX,
    _partnerY,
    _outsider,
  ];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {
        'id': users[i],
        'key': pgTestPublicKey('batonpairsel', i + 1),
      },
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  var n = 0;
  for (final user in users.where((u) => u != _outsider)) {
    await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pbatonpairselsel${(n++).toString().padLeft(3, '0')}', '$_request', '$user', 0, 0, 3)
''');
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
