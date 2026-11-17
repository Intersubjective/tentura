@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

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

// «Take it on together» (docs/plans/baton-together-plan.md §2.4, §2.8):
// a candidate names a partner, the partner joins or declines, one confirmed
// pair per person, the shared all-answered rule, receipts and the invite cap.

const _author = 'Ubatonpair_au1';
const _candA = 'Ubatonpair_ca1';
const _candB = 'Ubatonpair_cb1';
const _partnerX = 'Ubatonpair_px1';
const _partnerY = 'Ubatonpair_py1';
const _partnerZ = 'Ubatonpair_pz1';
const _partnerW = 'Ubatonpair_pw1';
const _outsider = 'Ubatonpair_ou1';

const _request = 'Bbatonpair_rq1';
const _ask = 'Who can bring the ladder?';

const _asked = 'batonPartnerAsked';
const _answered = 'batonPartnerAnswered';
const _allAnswered = 'batonAllAnswered';

// smallint values (beacon_room_baton_candidate)
const _waiting = 0;
const _canHelp = 1;
const _cantHelp = 2;
const _pending = 0;
const _accepted = 1;
const _declined = 2;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_BATON_PAIR_CASE_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_baton_pair_case',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('RoomBatonCase take it on together', () {
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
          candidates ?? [(userId: _candA, tier: 1), (userId: _candB, tier: 2)],
    );

    // Called dynamically so the file compiles before the partner API exists;
    // the call shape is the one the GraphQL mutations use.
    Future<void> respond(
      String actorId,
      RoomBaton baton, {
      required bool canHelp,
      String? partnerUserId,
    }) =>
        (batonCase as dynamic).respond(
              actorId: actorId,
              batonId: baton.id,
              canHelp: canHelp,
              partnerUserId: partnerUserId,
            )
            as Future<void>;

    Future<void> partnerRespond(
      String actorId,
      RoomBaton baton, {
      required String inviter,
      required bool accept,
    }) =>
        (batonCase as dynamic).partnerRespond(
              actorId: actorId,
              batonId: baton.id,
              inviterUserId: inviter,
              accept: accept,
            )
            as Future<void>;

    Future<void> block(String blocker, String blocked) => writer.execute(
      Sql.named(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        'VALUES (@x, @y, @x)',
      ),
      parameters: {'x': blocker, 'y': blocked},
    );

    group('naming a partner', () {
      test(
        'stores a pending invitation and asks only the named person',
        () async {
          final baton = await createBaton();
          final eventsBefore = await _count(writer, 'attention_occurrence');

          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);

          final row = (await _rows(writer, baton.id))[_candA]!;
          expect(row.response, _canHelp);
          expect(row.partner, _partnerX);
          expect(row.partnerResponse, _pending);
          expect(row.invites, 1);
          expect(await _recipients(writer, _asked), [_partnerX]);
          expect(
            await _keys(writer, _asked),
            ['baton_partner_asked:${baton.id}:$_candA:$_partnerX'],
          );
          expect(
            await _count(writer, 'attention_occurrence'),
            eventsBefore + 1,
            reason: 'the author and other candidates get no new event',
          );
          final blob = await _eventBlob(writer, _asked, _partnerX);
          expect(
            blob,
            contains(_candA),
            reason: "X's receipt names the person who asked",
          );
          final userIds = RegExp(
            'Ubatonpair_[a-z0-9]+',
          ).allMatches(blob).map((m) => m[0]!).toSet();
          expect(
            userIds.difference({_candA, _partnerX, _author}),
            isEmpty,
            reason:
                "X's receipt carries no user id besides the asker, the "
                'recipient and the author: no other candidate, no bystander',
          );
          expect(userIds, isNot(contains(_candB)));
        },
      );

      for (final (label, partner, blocker, blocked) in [
        ('not admitted to the room', _outsider, null, null),
        ('the baton author', _author, null, null),
        ('the actor themself', _candA, null, null),
        ('someone who blocked the actor', _partnerX, _partnerX, _candA),
        ('someone the actor blocked', _partnerX, _candA, _partnerX),
      ]) {
        test('a partner who is $label is rejected generically '
            'with nothing written', () async {
          final baton = await createBaton();
          if (blocker != null) await block(blocker, blocked!);
          final rowsBefore = await _rows(writer, baton.id);
          final eventsBefore = await _count(writer, 'attention_occurrence');

          final error = await _errorOf(
            respond(_candA, baton, canHelp: true, partnerUserId: partner),
          );

          expect(error, isA<BatonPartnerInvalidException>());
          final invalid = error! as BatonPartnerInvalidException;
          expect(
            invalid.code.codeNumber,
            const BatonPartnerInvalidException().code.codeNumber,
          );
          expect(
            invalid.description,
            const BatonPartnerInvalidException().description,
            reason: 'one generic description, so a block is not revealed',
          );
          expect(await _rows(writer, baton.id), rowsBefore);
          expect(await _count(writer, 'attention_occurrence'), eventsBefore);
        });
      }

      test(
        'naming a partner while answering cannot help is rejected',
        () async {
          final baton = await createBaton();
          final rowsBefore = await _rows(writer, baton.id);

          await expectLater(
            respond(_candA, baton, canHelp: false, partnerUserId: _partnerX),
            throwsA(isA<BatonPartnerInvalidException>()),
          );
          expect(await _rows(writer, baton.id), rowsBefore);
          expect(await _recipients(writer, _asked), isEmpty);
        },
      );

      test('at most three distinct partners can be named per baton', () async {
        final baton = await createBaton();

        for (final partner in [_partnerX, _partnerY, _partnerZ]) {
          await respond(_candA, baton, canHelp: true, partnerUserId: partner);
        }
        expect((await _rows(writer, baton.id))[_candA]!.invites, 3);
        final rowsBefore = await _rows(writer, baton.id);
        final eventsBefore = await _count(writer, 'attention_occurrence');
        final keysBefore = await _keys(writer, _asked);

        await expectLater(
          respond(_candA, baton, canHelp: true, partnerUserId: _partnerW),
          throwsA(isA<BatonPartnerInvalidException>()),
        );
        expect(await _rows(writer, baton.id), rowsBefore);
        final row = (await _rows(writer, baton.id))[_candA]!;
        expect(row.partner, _partnerZ);
        expect(row.invites, 3);
        expect(await _count(writer, 'attention_occurrence'), eventsBefore);
        expect(await _keys(writer, _asked), keysBefore);
        expect(await _recipients(writer, _asked), isNot(contains(_partnerW)));
      });

      test('naming the same person again after a decline shows the '
          'invitation again without a second receipt', () async {
        final baton = await createBaton();
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
        await partnerRespond(_partnerX, baton, inviter: _candA, accept: false);

        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);

        final row = (await _rows(writer, baton.id))[_candA]!;
        expect(row.response, _canHelp);
        expect(row.partner, _partnerX);
        expect(row.partnerResponse, _pending);
        expect(
          await _recipients(writer, _asked),
          [_partnerX],
          reason: 'one batonPartnerAsked per (baton, A, X)',
        );
      });
    });

    group('the named person answers', () {
      test('joining confirms the pair and tells the inviter', () async {
        final baton = await createBaton();
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);

        await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);

        final row = (await _rows(writer, baton.id))[_candA]!;
        expect(row.response, _canHelp);
        expect(row.partner, _partnerX);
        expect(row.partnerResponse, _accepted);
        expect(await _recipients(writer, _answered), [_candA]);
        expect(
          await _eventBlob(writer, _answered, _candA),
          matches(RegExp(r'"accepted"\s*:\s*true')),
        );
      });

      test('declining a pending invitation sends the inviter back to '
          'waiting with the declined marker', () async {
        final baton = await createBaton();
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);

        await partnerRespond(_partnerX, baton, inviter: _candA, accept: false);

        final row = (await _rows(writer, baton.id))[_candA]!;
        expect(row.response, _waiting);
        expect(row.partnerResponse, _declined);
        expect(row.respondedAt, isNull);
        expect(await _recipients(writer, _answered), [_candA]);
        expect(
          await _eventBlob(writer, _answered, _candA),
          matches(RegExp(r'"accepted"\s*:\s*false')),
        );
      });

      test('withdrawing after joining resets the inviter and reopens the '
          'all-answered round', () async {
        final baton = await createBaton();
        await respond(_candB, baton, canHelp: true);
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
        await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);
        expect(await _allAnsweredStamp(writer, baton.id), isNotNull);

        await partnerRespond(_partnerX, baton, inviter: _candA, accept: false);

        final row = (await _rows(writer, baton.id))[_candA]!;
        expect(row.response, _waiting);
        expect(row.partnerResponse, _declined);
        expect(row.respondedAt, isNull);
        expect(await _allAnsweredStamp(writer, baton.id), isNull);
        final answers = await _eventBlobs(writer, _answered, _candA);
        expect(answers, hasLength(2));
        expect(
          answers.where((b) => RegExp(r'"accepted"\s*:\s*false').hasMatch(b)),
          hasLength(1),
        );
      });

      test('answering by someone nobody named is refused', () async {
        final baton = await createBaton();
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
        final rowsBefore = await _rows(writer, baton.id);

        await expectLater(
          partnerRespond(_partnerY, baton, inviter: _candA, accept: true),
          throwsA(isA<BatonNotPartnerException>()),
        );
        await expectLater(
          partnerRespond(_candB, baton, inviter: _candA, accept: true),
          throwsA(isA<BatonNotPartnerException>()),
        );
        expect(await _rows(writer, baton.id), rowsBefore);
        expect(await _recipients(writer, _answered), isEmpty);
      });

      for (final (label, setUpLoss) in <(String, Future<void> Function())>[
        (
          'is no longer admitted',
          () => writer.execute(
            "DELETE FROM public.beacon_participant WHERE user_id = '$_partnerX'",
          ),
        ),
        ('blocked the inviter', () => block(_partnerX, _candA)),
        ('was blocked by the inviter', () => block(_candA, _partnerX)),
      ]) {
        test('an invited person who $label cannot join', () async {
          final baton = await createBaton();
          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
          await setUpLoss();
          final rowsBefore = await _rows(writer, baton.id);

          final error = await _errorOf(
            partnerRespond(_partnerX, baton, inviter: _candA, accept: true),
          );

          expect(
            error,
            isA<ExceptionBase>(),
            reason: 'the join is rejected with a baton domain error',
          );
          expect(
            error,
            anyOf(
              isA<BatonPartnerInvalidException>(),
              isA<BatonNotPartnerException>(),
              isA<BatonNotCandidateException>(),
              isA<UnauthorizedException>(),
            ),
          );
          expect(await _rows(writer, baton.id), rowsBefore);
          expect(await _recipients(writer, _answered), isEmpty);
        });
      }
    });

    group('one confirmed pair per person', () {
      test('choosing someone who already named you confirms both rows '
          'without asking them', () async {
        final baton = await createBaton();
        await respond(_candB, baton, canHelp: true, partnerUserId: _candA);
        final askedBefore = await _recipients(writer, _asked);

        await respond(_candA, baton, canHelp: true, partnerUserId: _candB);

        final rows = await _rows(writer, baton.id);
        expect(rows[_candA]!.partner, _candB);
        expect(rows[_candA]!.partnerResponse, _accepted);
        expect(rows[_candB]!.partner, _candA);
        expect(rows[_candB]!.partnerResponse, _accepted);
        expect(
          await _recipients(writer, _asked),
          askedBefore,
          reason: 'the mutual answer sends B no batonPartnerAsked',
        );
        expect(await _recipients(writer, _answered), [_candA]);
        expect(
          await _eventBlob(writer, _answered, _candA),
          matches(RegExp(r'"accepted"\s*:\s*true')),
        );
      });

      test(
        'joining a second pair releases the first one with a receipt',
        () async {
          final baton = await createBaton();
          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
          await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);
          await respond(_candB, baton, canHelp: true, partnerUserId: _partnerX);

          await partnerRespond(_partnerX, baton, inviter: _candB, accept: true);

          final rows = await _rows(writer, baton.id);
          expect(rows[_candB]!.partner, _partnerX);
          expect(rows[_candB]!.partnerResponse, _accepted);
          expect(rows[_candA]!.response, _waiting);
          expect(rows[_candA]!.partnerResponse, _declined);
          final released = await _eventBlobs(writer, _answered, _candA);
          expect(
            released.where(
              (b) => RegExp(r'"accepted"\s*:\s*false').hasMatch(b),
            ),
            hasLength(1),
          );
          expect(await _peopleInSeveralPairs(writer, baton.id), isEmpty);
        },
      );
    });

    group('after the baton is resolved', () {
      test('a selected baton refuses partner changes', () async {
        final baton = await createBaton();
        await respond(_candB, baton, canHelp: true);
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerY);
        await batonCase.select(
          actorId: _author,
          batonId: baton.id,
          userId: _candB,
        );

        await expectLater(
          respond(_candA, baton, canHelp: true, partnerUserId: _partnerX),
          throwsA(isA<BatonNotCollectingException>()),
        );
        await expectLater(
          partnerRespond(_partnerY, baton, inviter: _candA, accept: true),
          throwsA(isA<BatonNotCollectingException>()),
        );
      });

      test('a cancelled baton refuses partner changes', () async {
        final baton = await createBaton();
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerY);
        await batonCase.cancel(actorId: _author, batonId: baton.id);

        await expectLater(
          respond(_candA, baton, canHelp: true, partnerUserId: _partnerX),
          throwsA(isA<BatonNotCollectingException>()),
        );
        await expectLater(
          partnerRespond(_partnerY, baton, inviter: _candA, accept: true),
          throwsA(isA<BatonNotCollectingException>()),
        );
      });
    });

    group('all answered', () {
      test('a pending partner holds the author notice until they answer, '
          'then exactly one is sent', () async {
        final baton = await createBaton();
        await respond(_candB, baton, canHelp: true);
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
        expect(
          await _recipients(writer, _allAnswered),
          isEmpty,
          reason: 'A is not answered while X has not answered',
        );

        await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);
        expect(await _recipients(writer, _allAnswered), [_author]);

        await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);
        await respond(_candB, baton, canHelp: true);
        expect(await _recipients(writer, _allAnswered), [_author]);
      });
    });

    test('racing join against withdrawal always ends consistent', () async {
      for (var round = 0; round < 10; round++) {
        final baton = await createBaton(
          candidates: [(userId: _candA, tier: 1)],
        );
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);

        Future<void> tolerate(Future<void> call) async {
          try {
            await call;
          } on BatonNotPartnerException {
            // The withdrawal won: nothing left to join.
          }
        }

        // Any other error (a CHECK or unique violation surfacing as a
        // Postgres error, a lock error) fails the round.
        await Future.wait([
          tolerate(
            partnerRespond(_partnerX, baton, inviter: _candA, accept: true),
          ),
          respond(_candA, baton, canHelp: false),
        ]);
        expect(
          await _partnerConstraintViolations(writer, baton.id),
          isEmpty,
          reason: 'round $round: every row satisfies the partner CHECKs',
        );
        expect(await _peopleInSeveralPairs(writer, baton.id), isEmpty);

        final row = (await _rows(writer, baton.id))[_candA]!;
        final withdrawn =
            row.response == _cantHelp &&
            row.partner == null &&
            row.partnerResponse == null;
        final paired =
            row.response == _canHelp &&
            row.partner == _partnerX &&
            row.partnerResponse == _accepted;
        expect(
          withdrawn || paired,
          isTrue,
          reason: 'round $round ended as $row',
        );
      }
    });
  });
}

/// Blocks are real `public.user_block` rows read through the real
/// [UserBlockRepository] (`block_hides`), the same port instance the
/// attention intents use; the case must see blocks through it too.
RoomBatonCase _buildCase(TenturaDb db, Env env) {
  final logger = Logger('RoomBatonPairCasePgTest');
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

Future<Object?> _errorOf(Future<void> call) async {
  try {
    await call;
  } on Object catch (e) {
    return e;
  }
  return null;
}

Future<int> _count(Connection writer, String table) async {
  final rows = await writer.execute('SELECT count(*) FROM public.$table');
  return rows.single[0]! as int;
}

typedef _Row = ({
  int response,
  DateTime? respondedAt,
  String? partner,
  int? partnerResponse,
  int invites,
});

Future<Map<String, _Row>> _rows(Connection writer, String batonId) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT user_id, response, responded_at, partner_user_id, partner_response,
  partner_invites
FROM public.beacon_room_baton_candidate WHERE baton_id = @id
'''),
    parameters: {'id': batonId},
  );
  return {
    for (final r in rows)
      r[0]! as String: (
        response: r[1]! as int,
        respondedAt: r[2] as DateTime?,
        partner: r[3] as String?,
        partnerResponse: r[4] as int?,
        invites: r[5]! as int,
      ),
  };
}

Future<DateTime?> _allAnsweredStamp(Connection writer, String batonId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT all_answered_notified_at FROM public.beacon_room_baton '
      'WHERE id = @id',
    ),
    parameters: {'id': batonId},
  );
  return rows.single[0] as DateTime?;
}

/// Candidate rows of the baton that break the partner CHECK constraints
/// (`baton_candidate_partner_not_self`, `baton_candidate_partner_state`,
/// the `partner_invites` range), re-evaluated on the stored rows, plus a
/// pending or accepted answer that has lost its partner.
Future<List<String>> _partnerConstraintViolations(
  Connection writer,
  String batonId,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT user_id || ': response=' || response
  || ' partner=' || COALESCE(partner_user_id, 'null')
  || ' partner_response=' || COALESCE(partner_response::text, 'null')
  || ' invites=' || partner_invites
FROM public.beacon_room_baton_candidate
WHERE baton_id = @id AND NOT (
  partner_user_id IS DISTINCT FROM user_id
  AND (partner_response IS NULL
    OR (partner_response IN (0, 1) AND response = 1)
    OR (partner_response = 2 AND response = 0))
  AND partner_invites BETWEEN 0 AND 3
  AND (partner_response IS NULL OR partner_user_id IS NOT NULL
    OR partner_response = 2)
)
'''),
    parameters: {'id': batonId},
  );
  return rows.map((r) => r[0]! as String).toList();
}

/// Users who sit in more than one accepted pair on the baton (a mutual pair
/// is one pair).
Future<List<String>> _peopleInSeveralPairs(
  Connection writer,
  String batonId,
) async {
  final rows = await writer.execute(
    Sql.named('''
WITH pairs AS (
  SELECT DISTINCT LEAST(user_id, partner_user_id) AS a,
    GREATEST(user_id, partner_user_id) AS b
  FROM public.beacon_room_baton_candidate
  WHERE baton_id = @id AND partner_response = 1
), members AS (
  SELECT a AS user_id FROM pairs UNION ALL SELECT b FROM pairs
)
SELECT user_id FROM members GROUP BY user_id HAVING count(*) > 1
'''),
    parameters: {'id': batonId},
  );
  return rows.map((r) => r[0]! as String).toList();
}

/// Recipients of every stored event of [eventType], one entry per event.
Future<List<String>> _recipients(Connection writer, String eventType) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT recipient.account_id
FROM public.attention_occurrence_recipient AS recipient
JOIN public.attention_occurrence AS occ ON occ.id = recipient.occurrence_id
WHERE occ.event_type = @type
ORDER BY recipient.account_id
'''),
    parameters: {'type': eventType},
  );
  return rows.map((r) => r[0]! as String).toList();
}

Future<List<String>> _keys(Connection writer, String eventType) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT source_event_key FROM public.attention_occurrence
WHERE event_type = @type ORDER BY source_event_key
'''),
    parameters: {'type': eventType},
  );
  return rows.map((r) => r[0]! as String).toList();
}

/// Everything persisted for each of [recipient]'s events of [eventType]
/// (occurrence, recipient row, outbox receipt), as text.
Future<List<String>> _eventBlobs(
  Connection writer,
  String eventType,
  String recipient,
) async {
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
    parameters: {'type': eventType, 'recipient': recipient},
  );
  return rows.map((r) => r[0]! as String).toList();
}

Future<String> _eventBlob(
  Connection writer,
  String eventType,
  String recipient,
) async => (await _eventBlobs(writer, eventType, recipient)).join();

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
    _partnerX,
    _partnerY,
    _partnerZ,
    _partnerW,
    _outsider,
  ];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('batonpair', i + 1)},
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
VALUES ('Pbatonpair${(n++).toString().padLeft(3, '0')}', '$_request', '$user', 0, 0, 3)
''');
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
