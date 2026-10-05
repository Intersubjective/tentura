@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/room_baton_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/room_baton_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ubatonsel_au1';
const _a = 'Ubatonsel_ca1';
const _b = 'Ubatonsel_cb1';
const _c = 'Ubatonsel_cc1';
const _d = 'Ubatonsel_cd1';

const _request = 'Bbatonsel_rq1';
const _message = 'Rbatonsel_rq1';

/// Random whose every draw returns [pick] (clamped into range).
final class _FixedRandom implements Random {
  _FixedRandom(this.pick);
  final int pick;

  @override
  int nextInt(int max) => pick < max ? pick : max - 1;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_BATON_SELECT_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_baton_select',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('RoomBatonCase.select / cancel', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
    });

    setUp(() => _resetFixture(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    RoomBatonCase build([Random? random]) =>
        _buildCase(database, target.databaseEnv, random);

    /// Tier 1: A, B; tier 2: C.
    Future<RoomBaton> createBaton(
      RoomBatonCase batonCase, {
      List<({String userId, int tier})>? candidates,
    }) => batonCase.create(
      actorId: _author,
      messageId: _message,
      candidates:
          candidates ??
          [(userId: _a, tier: 1), (userId: _b, tier: 1), (userId: _c, tier: 2)],
    );

    Future<void> answer(
      RoomBatonCase batonCase,
      RoomBaton baton,
      Map<String, bool> answers,
    ) async {
      for (final e in answers.entries) {
        await batonCase.respond(
          actorId: e.key,
          batonId: baton.id,
          canHelp: e.value,
        );
      }
    }

    test(
      'pick for me chooses a can-help person from the lowest tier',
      () async {
        final batonCase = build();
        final baton = await createBaton(
          batonCase,
          candidates: [
            (userId: _a, tier: 1),
            (userId: _b, tier: 1),
            (userId: _c, tier: 2),
          ],
        );
        await answer(batonCase, baton, {_a: true, _b: false, _c: true});

        await batonCase.select(actorId: _author, batonId: baton.id);

        final row = await _batonRow(writer);
        expect(row.status, 1);
        expect(row.taker, _a);
        expect(row.resolvedAt, isNotNull);
        expect(row.mode, BatonSelectionMode.auto.smallintValue);
      },
    );

    test(
      'pick for me with a seeded Random picks the seeded person in the tier',
      () async {
        for (final (index, expected) in [(0, _a), (1, _d)]) {
          await _resetFixture(writer);
          final batonCase = build(_FixedRandom(index));
          final baton = await createBaton(
            batonCase,
            candidates: [(userId: _a, tier: 1), (userId: _d, tier: 1)],
          );
          await answer(batonCase, baton, {_a: true, _d: true});

          await batonCase.select(actorId: _author, batonId: baton.id);

          expect(
            (await _batonRow(writer)).taker,
            expected,
            reason: 'draw $index',
          );
        }
      },
    );

    test('pick for me with nobody who can help is rejected', () async {
      final batonCase = build();
      final baton = await createBaton(batonCase);
      await answer(batonCase, baton, {_a: false, _b: false});

      await expectLater(
        batonCase.select(actorId: _author, batonId: baton.id),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
      expect((await _batonRow(writer)).status, 0);
      expect(await _markerMessages(writer), isEmpty);
    });

    test(
      'manual pick of a tier-2 can-help person works while others wait',
      () async {
        final batonCase = build();
        final baton = await createBaton(batonCase);
        await answer(batonCase, baton, {_c: true});

        await batonCase.select(actorId: _author, batonId: baton.id, userId: _c);

        final row = await _batonRow(writer);
        expect(row.status, 1);
        expect(row.taker, _c);
        expect(row.mode, BatonSelectionMode.manual.smallintValue);
      },
    );

    test('manual pick of a waiting person is rejected', () async {
      final batonCase = build();
      final baton = await createBaton(batonCase);
      await answer(batonCase, baton, {_c: true});

      await expectLater(
        batonCase.select(actorId: _author, batonId: baton.id, userId: _a),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
      expect((await _batonRow(writer)).status, 0);
      expect(await _markerMessages(writer), isEmpty);
    });

    test('manual pick of a cannot-help person is rejected', () async {
      final batonCase = build();
      final baton = await createBaton(batonCase);
      await answer(batonCase, baton, {_a: false});

      await expectLater(
        batonCase.select(actorId: _author, batonId: baton.id, userId: _a),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
      expect((await _batonRow(writer)).status, 0);
    });

    test(
      'manual pick of a can-help person who left the room is rejected',
      () async {
        final batonCase = build();
        final baton = await createBaton(batonCase);
        await answer(batonCase, baton, {_a: true});
        await writer.execute('''
UPDATE public.beacon_participant SET room_access = ${RoomAccessBits.left}
WHERE beacon_id = '$_request' AND user_id = '$_a'
''');

        await expectLater(
          batonCase.select(actorId: _author, batonId: baton.id, userId: _a),
          throwsA(isA<BatonTakerNotAvailableException>()),
        );
        expect((await _batonRow(writer)).status, 0);
        expect(await _markerMessages(writer), isEmpty);
      },
    );

    test('select and cancel by a non-author are rejected', () async {
      final batonCase = build();
      final baton = await createBaton(batonCase);
      await answer(batonCase, baton, {_a: true});

      await expectLater(
        batonCase.select(actorId: _a, batonId: baton.id),
        throwsA(isA<BatonNotAuthorException>()),
      );
      await expectLater(
        batonCase.cancel(actorId: _a, batonId: baton.id),
        throwsA(isA<BatonNotAuthorException>()),
      );
      expect((await _batonRow(writer)).status, 0);
    });

    test('select after select is rejected', () async {
      final batonCase = build();
      final baton = await createBaton(batonCase);
      await answer(batonCase, baton, {_a: true});
      await batonCase.select(actorId: _author, batonId: baton.id);

      await expectLater(
        batonCase.select(actorId: _author, batonId: baton.id),
        throwsA(isA<BatonNotCollectingException>()),
      );
      expect(await _markerMessages(writer), hasLength(1));
    });

    test('select after cancel is rejected', () async {
      final batonCase = build();
      final baton = await createBaton(batonCase);
      await answer(batonCase, baton, {_a: true});
      await batonCase.cancel(actorId: _author, batonId: baton.id);

      await expectLater(
        batonCase.select(actorId: _author, batonId: baton.id),
        throwsA(isA<BatonNotCollectingException>()),
      );
    });

    test('cancel after select is rejected', () async {
      final batonCase = build();
      final baton = await createBaton(batonCase);
      await answer(batonCase, baton, {_a: true});
      await batonCase.select(actorId: _author, batonId: baton.id);

      await expectLater(
        batonCase.cancel(actorId: _author, batonId: baton.id),
        throwsA(isA<BatonNotCollectingException>()),
      );
      expect((await _batonRow(writer)).status, 1);
    });

    test('respond after select is rejected', () async {
      final batonCase = build();
      final baton = await createBaton(batonCase);
      await answer(batonCase, baton, {_a: true});
      await batonCase.select(actorId: _author, batonId: baton.id);

      await expectLater(
        batonCase.respond(actorId: _b, batonId: baton.id, canHelp: true),
        throwsA(isA<BatonNotCollectingException>()),
      );
    });

    test('select on an unknown baton is rejected', () async {
      await expectLater(
        build().select(actorId: _author, batonId: 'Xbatonsel_none'),
        throwsA(isA<BatonNotFoundException>()),
      );
    });

    test(
      'select writes one marker message with only the three payload keys',
      () async {
        final batonCase = build();
        final baton = await createBaton(batonCase);
        await answer(batonCase, baton, {_a: true, _b: false});

        await batonCase.select(actorId: _author, batonId: baton.id);

        final messages = await _markerMessages(writer);
        expect(messages, hasLength(1));
        final m = messages.single;
        expect(m.author, _author);
        expect(m.body, '');
        expect(m.beaconId, _request);
        expect(m.payload.keys.toSet(), {
          'batonId',
          'sourceMessageId',
          'takerUserId',
        });
        expect(m.payload['batonId'], baton.id);
        expect(m.payload['sourceMessageId'], _message);
        expect(m.payload['takerUserId'], _a);
      },
    );

    test('select sends one batonTaken receipt to the taker only', () async {
      final batonCase = build();
      final baton = await createBaton(batonCase);
      await answer(batonCase, baton, {_a: true, _b: true, _c: false});
      final before = await _receiptRecipients(writer, 'batonTaken');
      expect(before, isEmpty);

      await batonCase.select(actorId: _author, batonId: baton.id, userId: _b);

      expect(await _receiptRecipients(writer, 'batonTaken'), [_b]);
    });

    test(
      'cancel writes no message and no receipt, and frees the message',
      () async {
        final batonCase = build();
        final baton = await createBaton(batonCase);
        await answer(batonCase, baton, {_a: true});
        final outboxBefore = await _count(writer, 'notification_outbox');
        final messagesBefore = await _count(writer, 'beacon_room_message');

        await batonCase.cancel(actorId: _author, batonId: baton.id);

        final row = await _batonRow(writer);
        expect(row.status, 2);
        expect(row.resolvedAt, isNotNull);
        expect(await _count(writer, 'notification_outbox'), outboxBefore);
        expect(await _count(writer, 'beacon_room_message'), messagesBefore);
        expect(await _markerMessages(writer), isEmpty);

        final again = await createBaton(
          batonCase,
          candidates: [(userId: _b, tier: 1)],
        );
        expect(again.status, BatonStatus.collecting);
      },
    );

    test('select and cancel racing leave exactly one winner', () async {
      for (var round = 0; round < 10; round++) {
        await _resetFixture(writer);
        final batonCase = build();
        final baton = await createBaton(batonCase);
        await answer(batonCase, baton, {_a: true});

        var wins = 0;
        Future<void> attempt(Future<void> Function() run) async {
          try {
            await run();
            wins++;
          } on BatonNotCollectingException {
            // lost the race
          }
        }

        await Future.wait([
          attempt(() => batonCase.select(actorId: _author, batonId: baton.id)),
          attempt(() => batonCase.cancel(actorId: _author, batonId: baton.id)),
        ]);

        expect(wins, 1, reason: 'round $round');
        final row = await _batonRow(writer);
        final markers = await _markerMessages(writer);
        expect(markers.length, row.status == 1 ? 1 : 0, reason: 'round $round');
        expect(
          await _receiptRecipients(writer, 'batonTaken'),
          row.status == 1 ? [_a] : isEmpty,
          reason: 'round $round',
        );
      }
    });
  });
}

typedef _BatonRow = ({
  int status,
  int? mode,
  String? taker,
  Object? resolvedAt,
});

Future<_BatonRow> _batonRow(Connection writer) async {
  final r = (await writer.execute('''
SELECT status, selection_mode, taker_id, resolved_at
FROM public.beacon_room_baton
''')).single;
  return (
    status: r[0]! as int,
    mode: r[1] as int?,
    taker: r[2] as String?,
    resolvedAt: r[3],
  );
}

typedef _Marker = ({
  String author,
  String body,
  String beaconId,
  Map<String, Object?> payload,
});

Future<List<_Marker>> _markerMessages(Connection writer) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT author_id, body, beacon_id, system_payload::text
FROM public.beacon_room_message
WHERE semantic_marker = @marker
'''),
    parameters: {'marker': BeaconRoomSemanticMarker.batonTaken},
  );
  return [
    for (final r in rows)
      (
        author: r[0]! as String,
        body: r[1]! as String,
        beaconId: r[2]! as String,
        payload: (jsonDecode(r[3]! as String) as Map).cast<String, Object?>(),
      ),
  ];
}

RoomBatonCase _buildCase(TenturaDb db, Env env, Random? random) {
  final logger = Logger('RoomBatonSelectPgTest');
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
    FakeUserBlockRepository(),
  );
  return RoomBatonCase(
    RoomBatonRepository(db),
    room,
    BeaconHierarchyRepository(db),
    PostLockRepository(db),
    attention,
    attentionIntents,
    random: random ?? Random.secure(),
    env: env,
    logger: logger,
  );
}

Future<int> _count(Connection writer, String table) async {
  final rows = await writer.execute('SELECT count(*) FROM public.$table');
  return rows.single[0]! as int;
}

Future<List<String>> _receiptRecipients(
  Connection writer,
  String eventType,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT outbox.account_id
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = @type
ORDER BY outbox.account_id
'''),
    parameters: {'type': eventType},
  );
  return rows.map((r) => r[0]! as String).toList();
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
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _a, _b, _c, _d];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('batonsel', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  var n = 0;
  for (final user in users) {
    await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pbatonsel${(n++).toString().padLeft(3, '0')}', '$_request', '$user', 0, 0, 3)
''');
  }
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_message', '$_request', '$_author', 'Can someone take this?')
''');
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
