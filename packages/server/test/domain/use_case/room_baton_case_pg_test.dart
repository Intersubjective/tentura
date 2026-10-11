@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
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

const _author = 'Ubatoncase_au1';
const _candA = 'Ubatoncase_ca1';
const _candB = 'Ubatoncase_cb1';
const _member = 'Ubatoncase_mb1';
const _outsider = 'Ubatoncase_ou1';

const _request = 'Bbatoncase_rq1';
const _post = 'Bbatoncase_ps1';
const _requestMessage = 'Rbatoncase_rq1';
const _postMessage = 'Rbatoncase_ps1';
const _foreignMessage = 'Rbatoncase_fo1';
const _pollMessage = 'Rbatoncase_pl1';
const _systemMessage = 'Rbatoncase_sy1';
const _noticeMessage = 'Rbatoncase_nt1';
const _threadMessage = 'Rbatoncase_th1';

const _ask = 'Who can bring the ladder?';
const _requestBody = 'Can someone take this?';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_BATON_CASE_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_baton_case',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('RoomBatonCase.create / respond', () {
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

    Future<RoomBaton> createOnRequest({
      List<({String userId, int tier})>? candidates,
      String text = _ask,
      String? replyToMessageId,
    }) => batonCase.create(
      actorId: _author,
      beaconId: _request,
      text: text,
      replyToMessageId: replyToMessageId,
      candidates:
          candidates ?? [(userId: _candA, tier: 1), (userId: _candB, tier: 2)],
    );

    test('create stores the baton and its candidates', () async {
      final baton = await createOnRequest();

      expect(baton.status, BatonStatus.collecting);
      expect(baton.authorId, _author);
      expect(baton.beaconId, _request);
      expect(await _count(writer, 'beacon_room_baton'), 1);
      expect(await _count(writer, 'beacon_room_baton_candidate'), 2);
      final tiers = await writer.execute('''
SELECT user_id, tier, response FROM public.beacon_room_baton_candidate
ORDER BY user_id
''');
      expect(
        tiers.map((r) => [r[0], r[1], r[2]]).toList(),
        [
          [_candA, 1, 0],
          [_candB, 2, 0],
        ],
      );
    });

    test(
      'create posts a new baton message and hangs the baton off it',
      () async {
        final messagesBefore = await _count(writer, 'beacon_room_message');

        final baton = await createOnRequest(text: '  $_ask  ');

        expect(
          await _count(writer, 'beacon_room_message'),
          messagesBefore + 1,
        );
        expect(baton.messageId, isNot(_requestMessage));
        final message = await _message(writer, baton.messageId);
        expect(message.beaconId, _request);
        expect(message.author, _author);
        expect(message.body, _ask, reason: 'body is the trimmed ask');
        expect(message.replyTo, isNull);
        expect(message.marker, BeaconRoomSemanticMarker.baton);
        final stored = await writer.execute('''
SELECT message_id FROM public.beacon_room_baton WHERE id = '${baton.id}'
''');
        expect(stored.single[0], baton.messageId);
      },
    );

    test(
      'create with empty text replying to a message posts a reply',
      () async {
        final baton = await createOnRequest(
          text: '   ',
          replyToMessageId: _requestMessage,
        );

        final message = await _message(writer, baton.messageId);
        expect(message.body, '');
        expect(message.replyTo, _requestMessage);
        expect(message.marker, BeaconRoomSemanticMarker.baton);
        expect(
          await _receiptBlob(writer, 'batonAsked', _candA),
          contains(_requestBody),
          reason: 'with no ask, the replied-to message is the excerpt',
        );
      },
    );

    test('create with text and a reply keeps both and uses the text', () async {
      final baton = await createOnRequest(replyToMessageId: _requestMessage);

      final message = await _message(writer, baton.messageId);
      expect(message.body, _ask);
      expect(message.replyTo, _requestMessage);
      expect(await _receiptBlob(writer, 'batonAsked', _candA), contains(_ask));
    });

    test("create replying to someone else's message is allowed", () async {
      final baton = await createOnRequest(
        text: '',
        replyToMessageId: _foreignMessage,
      );

      final message = await _message(writer, baton.messageId);
      expect(message.author, _author, reason: 'the actor authors the baton');
      expect(message.replyTo, _foreignMessage);
      expect(await _receiptRecipients(writer, 'batonAsked'), [_candA, _candB]);
    });

    for (final replyTo in [_pollMessage, _systemMessage, _noticeMessage]) {
      test(
        'create replying to the non-plain message $replyTo is allowed',
        () async {
          final baton = await createOnRequest(replyToMessageId: replyTo);

          expect((await _message(writer, baton.messageId)).replyTo, replyTo);
        },
      );
    }

    test('create sends exactly one batonAsked receipt per candidate', () async {
      await createOnRequest();

      expect(
        await _receiptRecipients(writer, 'batonAsked'),
        [_candA, _candB],
        reason: 'one receipt per candidate; none for the author or members',
      );
      expect(await _count(writer, 'notification_outbox'), 2);
      expect(await _count(writer, 'attention_occurrence'), 2);
    });

    test('batonAsked receipts never carry another candidate id', () async {
      await createOnRequest();

      for (final (recipient, other) in [(_candA, _candB), (_candB, _candA)]) {
        final blob = await _receiptBlob(writer, 'batonAsked', recipient);
        expect(blob, isNotEmpty);
        expect(blob, isNot(contains(other)));
      }
    });

    test('create in a Post room works', () async {
      final baton = await batonCase.create(
        actorId: _author,
        beaconId: _post,
        text: _ask,
        candidates: [(userId: _candA, tier: 1)],
      );

      expect(baton.beaconId, _post);
      expect((await _message(writer, baton.messageId)).beaconId, _post);
      expect(await _receiptRecipients(writer, 'batonAsked'), [_candA]);
    });

    for (final beaconId in [_request, _post]) {
      test('author without participant row can create on $beaconId', () async {
        await writer.execute('''
DELETE FROM public.beacon_participant
WHERE beacon_id = '$beaconId' AND user_id = '$_author'
''');

        final baton = await batonCase.create(
          actorId: _author,
          beaconId: beaconId,
          text: _ask,
          candidates: [(userId: _candA, tier: 1)],
        );

        expect(baton.beaconId, beaconId);
        expect(baton.authorId, _author);
        expect(baton.status, BatonStatus.collecting);
        expect(await _receiptRecipients(writer, 'batonAsked'), [_candA]);
      });
    }

    test(
      'create with empty text and no reply is rejected without rows',
      () async {
        await expectLater(
          createOnRequest(text: '  '),
          throwsA(isA<BatonMessageNotEligibleException>()),
        );
        await _expectNothingWritten(writer);
      },
    );

    test('create replying to a message of another room is rejected', () async {
      await expectLater(
        createOnRequest(replyToMessageId: _postMessage),
        throwsA(isA<BatonMessageNotEligibleException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create replying to an unknown message is rejected', () async {
      await expectLater(
        createOnRequest(replyToMessageId: 'Rbatoncase_none'),
        throwsA(isA<BatonMessageNotEligibleException>()),
      );
      await _expectNothingWritten(writer);
    });

    test(
      'create replying to a message outside the General room is rejected',
      () async {
        await expectLater(
          createOnRequest(replyToMessageId: _threadMessage),
          throwsA(isA<BatonMessageNotEligibleException>()),
        );
        await _expectNothingWritten(writer);
      },
    );

    test('create with an over-long ask is rejected without rows', () async {
      await expectLater(
        createOnRequest(text: 'x' * (kMaxRoomMessageBodyLength + 1)),
        throwsA(isA<BeaconCreateException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create is rate-limited like ordinary room messages', () async {
      final limited = _buildCase(
        database,
        _withRoomMessageLimit(target.databaseEnv, 2),
      );
      // The fixture already holds more than two recent messages by the author.
      await expectLater(
        limited.create(
          actorId: _author,
          beaconId: _request,
          text: _ask,
          candidates: [(userId: _candA, tier: 1)],
        ),
        throwsA(isA<RateLimitedException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create with the author as a candidate is rejected', () async {
      await expectLater(
        createOnRequest(candidates: [(userId: _author, tier: 1)]),
        throwsA(isA<BatonInvalidCandidatesException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create with a non-admitted candidate is rejected', () async {
      await expectLater(
        createOnRequest(
          candidates: [(userId: _candA, tier: 1), (userId: _outsider, tier: 1)],
        ),
        throwsA(isA<BatonInvalidCandidatesException>()),
      );
      await _expectNothingWritten(writer);
    });

    test(
      'two batons replying to one message each get their own message',
      () async {
        final first = await createOnRequest(replyToMessageId: _requestMessage);
        final second = await createOnRequest(
          candidates: [(userId: _member, tier: 1)],
          replyToMessageId: _requestMessage,
        );

        expect(second.messageId, isNot(first.messageId));
        expect(await _count(writer, 'beacon_room_baton'), 2);
        expect(
          await _receiptRecipients(writer, 'batonAsked'),
          [_candA, _candB, _member],
        );
      },
    );

    test(
      'create in a closed room is rejected like posting a message',
      () async {
        await writer.execute('''
UPDATE public.beacon SET status = ${BeaconStatus.closed.smallintValue}
WHERE id = '$_request'
''');

        await expectLater(
          createOnRequest(),
          throwsA(isA<BeaconCreateException>()),
          reason: 'same rejection as posting a message in a read-only room',
        );
        await _expectNothingWritten(writer);
      },
    );

    test('respond by a non-candidate is rejected', () async {
      final baton = await createOnRequest();

      await expectLater(
        batonCase.respond(actorId: _member, batonId: baton.id, canHelp: true),
        throwsA(isA<BatonNotCandidateException>()),
      );
      expect(await _responses(writer), {_candA: 0, _candB: 0});
    });

    test('a candidate can switch from can-help to cannot-help', () async {
      final baton = await createOnRequest();

      await batonCase.respond(
        actorId: _candA,
        batonId: baton.id,
        canHelp: true,
      );
      expect((await _responses(writer))[_candA], 1);

      await batonCase.respond(
        actorId: _candA,
        batonId: baton.id,
        canHelp: false,
      );
      expect((await _responses(writer))[_candA], 2);
      final respondedAt = await writer.execute('''
SELECT responded_at FROM public.beacon_room_baton_candidate
WHERE user_id = '$_candA'
''');
      expect(respondedAt.single[0], isNotNull);
    });

    test(
      'switching an answer that completes the set notifies the author once',
      () async {
        final baton = await createOnRequest();
        await batonCase.respond(
          actorId: _candA,
          batonId: baton.id,
          canHelp: true,
        );
        await batonCase.respond(
          actorId: _candB,
          batonId: baton.id,
          canHelp: true,
        );
        expect(await _receiptRecipients(writer, 'batonAllAnswered'), [_author]);

        await batonCase.respond(
          actorId: _candB,
          batonId: baton.id,
          canHelp: false,
        );

        expect((await _responses(writer))[_candB], 2);
        expect(await _receiptRecipients(writer, 'batonAllAnswered'), [_author]);
      },
    );

    for (final (label, setStatus) in [
      (
        'taken',
        "status = 1, selection_mode = 1, resolved_at = now(), taker_id = '$_candA'",
      ),
      ('cancelled', 'status = 2, resolved_at = now()'),
    ]) {
      test(
        'respond on a $label baton is rejected and changes nothing',
        () async {
          final baton = await createOnRequest();
          await writer.execute(
            'UPDATE public.beacon_room_baton SET $setStatus',
          );

          await expectLater(
            batonCase.respond(
              actorId: _candB,
              batonId: baton.id,
              canHelp: true,
            ),
            throwsA(isA<BatonNotCollectingException>()),
          );

          expect(await _responses(writer), {_candA: 0, _candB: 0});
          expect(await _receiptRecipients(writer, 'batonAllAnswered'), isEmpty);
        },
      );
    }

    test('a candidate who lost room admission cannot respond', () async {
      final baton = await createOnRequest();
      await writer.execute('''
UPDATE public.beacon_participant SET room_access = 0
WHERE beacon_id = '$_request' AND user_id = '$_candB'
''');

      await expectLater(
        batonCase.respond(actorId: _candB, batonId: baton.id, canHelp: true),
        throwsA(isA<BatonNotCandidateException>()),
      );

      expect(await _responses(writer), {_candA: 0, _candB: 0});
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), isEmpty);
    });

    test('the last answer notifies the author exactly once', () async {
      final baton = await createOnRequest();

      await batonCase.respond(
        actorId: _candA,
        batonId: baton.id,
        canHelp: true,
      );
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), isEmpty);

      await batonCase.respond(
        actorId: _candB,
        batonId: baton.id,
        canHelp: false,
      );
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), [_author]);

      // Changing an answer afterwards must not notify again.
      await batonCase.respond(
        actorId: _candA,
        batonId: baton.id,
        canHelp: false,
      );
      await batonCase.respond(
        actorId: _candB,
        batonId: baton.id,
        canHelp: true,
      );
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), [_author]);
      final stamp = await writer.execute(
        'SELECT all_answered_notified_at FROM public.beacon_room_baton',
      );
      expect(stamp.single[0], isNotNull);
    });

    test('concurrent final answers notify the author exactly once', () async {
      for (var round = 0; round < 10; round++) {
        await _resetFixture(writer);
        final baton = await createOnRequest();

        await Future.wait([
          batonCase.respond(actorId: _candA, batonId: baton.id, canHelp: true),
          batonCase.respond(actorId: _candB, batonId: baton.id, canHelp: false),
        ]);

        expect(
          await _receiptRecipients(writer, 'batonAllAnswered'),
          [_author],
          reason: 'round $round',
        );
        expect(
          await _count(writer, 'notification_outbox'),
          2 + 1,
          reason: 'round $round: two batonAsked plus one batonAllAnswered',
        );
      }
    });

    group('update', () {
      const newAsk = 'Who can bring the big ladder?';

      Future<void> update(
        RoomBaton baton, {
        String actorId = _author,
        String text = newAsk,
        List<({String userId, int tier})>? candidates,
      }) => batonCase.update(
        actorId: actorId,
        batonId: baton.id,
        text: text,
        candidates:
            candidates ??
            [(userId: _candA, tier: 1), (userId: _candB, tier: 2)],
      );

      /// Everything [update] may change, to assert an unchanged snapshot.
      Future<String> snapshot(RoomBaton baton) async {
        final rows = await writer.execute('''
SELECT
  (SELECT json_agg(c ORDER BY c.user_id)
     FROM public.beacon_room_baton_candidate c)::text,
  (SELECT row_to_json(b) FROM public.beacon_room_baton b)::text,
  (SELECT row_to_json(m) FROM public.beacon_room_message m
    WHERE m.id = '${baton.messageId}')::text,
  (SELECT count(*) FROM public.attention_occurrence)
''');
        return rows.single.join('|');
      }

      test('kept candidates keep their answers; tiers can change', () async {
        final baton = await createOnRequest();
        await batonCase.respond(
          actorId: _candA,
          batonId: baton.id,
          canHelp: true,
        );
        await batonCase.respond(
          actorId: _candB,
          batonId: baton.id,
          canHelp: false,
        );
        final before = await _candidateRows(writer);

        await update(
          baton,
          candidates: [(userId: _candA, tier: 3), (userId: _candB, tier: 2)],
        );

        final after = await _candidateRows(writer);
        expect(after.keys.toSet(), {_candA, _candB});
        expect(after[_candA]!.tier, 3, reason: 'retiered');
        expect(after[_candA]!.response, 1, reason: 'can-help kept');
        expect(after[_candA]!.respondedAt, before[_candA]!.respondedAt);
        expect(after[_candB]!.tier, 2);
        expect(after[_candB]!.response, 2, reason: 'cannot-help kept');
        expect(after[_candB]!.respondedAt, before[_candB]!.respondedAt);
        expect(
          await _receiptRecipients(writer, 'batonAsked'),
          [_candA, _candB],
          reason: 'nobody new was asked, so no new receipts',
        );
      });

      test('adds, removes and retiers in one edit', () async {
        final baton = await createOnRequest();
        await batonCase.respond(
          actorId: _candA,
          batonId: baton.id,
          canHelp: true,
        );

        await update(
          baton,
          candidates: [(userId: _candA, tier: 2), (userId: _member, tier: 1)],
        );

        final rows = await _candidateRows(writer);
        expect(rows.keys.toSet(), {_candA, _member});
        expect(rows[_candA]!.tier, 2);
        expect(rows[_candA]!.response, 1);
        expect(rows[_member]!.tier, 1);
        expect(rows[_member]!.response, 0, reason: 'added people are waiting');
        expect(rows[_member]!.respondedAt, isNull);
      });

      test('only added people get a batonAsked receipt', () async {
        final baton = await createOnRequest();
        expect(await _count(writer, 'attention_occurrence'), 2);

        await update(
          baton,
          candidates: [(userId: _candA, tier: 1), (userId: _member, tier: 2)],
        );

        expect(
          await _receiptRecipients(writer, 'batonAsked'),
          [_candA, _candB, _member],
          reason:
              'one new receipt for the added member; none for kept or '
              'removed people',
        );
        expect(await _count(writer, 'attention_occurrence'), 3);
        final keys = await writer.execute('''
SELECT source_event_key FROM public.attention_occurrence
WHERE event_type = 'batonAsked' ORDER BY source_event_key
''');
        // Per-edit key, so a person removed and added back is asked again.
        expect(
          keys.map((r) => r[0]! as String),
          contains(startsWith('baton_asked:${baton.id}:$_member:')),
        );
        final blob = await _receiptBlob(writer, 'batonAsked', _member);
        expect(blob, contains(newAsk), reason: 'the excerpt is the new ask');
        expect(blob, isNot(contains(_candA)));
      });

      test('an added person on an empty-text reply baton gets the replied-to '
          'body as excerpt', () async {
        final baton = await createOnRequest(
          text: '',
          replyToMessageId: _requestMessage,
        );

        await update(
          baton,
          text: '',
          candidates: [(userId: _candA, tier: 1), (userId: _member, tier: 1)],
        );

        expect(
          await _receiptBlob(writer, 'batonAsked', _member),
          contains(_requestBody),
        );
      });

      test('adding someone resets all_answered_notified_at', () async {
        final baton = await createOnRequest();
        await batonCase.respond(
          actorId: _candA,
          batonId: baton.id,
          canHelp: true,
        );
        await batonCase.respond(
          actorId: _candB,
          batonId: baton.id,
          canHelp: true,
        );
        expect(await _allAnsweredStamp(writer), isNotNull);

        await update(
          baton,
          candidates: [
            (userId: _candA, tier: 1),
            (userId: _candB, tier: 1),
            (userId: _member, tier: 1),
          ],
        );
        expect(await _allAnsweredStamp(writer), isNull);

        await batonCase.respond(
          actorId: _member,
          batonId: baton.id,
          canHelp: false,
        );
        expect(await _allAnsweredStamp(writer), isNotNull);
        final allAnswered = await writer.execute('''
SELECT count(*) FROM public.attention_occurrence
WHERE event_type = 'batonAllAnswered'
''');
        expect(
          allAnswered.single[0],
          2,
          reason: 'the author is told again once the newcomer answers',
        );
      });

      test(
        'removing or retiering only keeps all_answered_notified_at',
        () async {
          final baton = await createOnRequest(
            candidates: [
              (userId: _candA, tier: 1),
              (userId: _candB, tier: 1),
              (userId: _member, tier: 1),
            ],
          );
          for (final user in [_candA, _candB, _member]) {
            await batonCase.respond(
              actorId: user,
              batonId: baton.id,
              canHelp: true,
            );
          }
          final stamp = await _allAnsweredStamp(writer);
          expect(stamp, isNotNull);

          await update(
            baton,
            candidates: [(userId: _candA, tier: 2), (userId: _candB, tier: 1)],
          );

          expect(await _allAnsweredStamp(writer), stamp);
        },
      );

      test(
        'rewrites the message body, sets edited_at and clears mentions',
        () async {
          final baton = await createOnRequest();
          await writer.execute('''
UPDATE public.beacon_room_message
   SET mentions = ARRAY['$_candA'],
       mention_spans = '[{"userId":"$_candA","start":0,"end":3}]'::jsonb
 WHERE id = '${baton.messageId}'
''');
          expect(await _editedAt(writer, baton.messageId), isNull);

          await update(baton, text: '  $newAsk  ');

          final message = await _message(writer, baton.messageId);
          expect(message.body, newAsk, reason: 'trimmed');
          expect(message.marker, BeaconRoomSemanticMarker.baton);
          expect(await _editedAt(writer, baton.messageId), isNotNull);
          final mentions = await writer.execute('''
SELECT mentions, mention_spans FROM public.beacon_room_message
WHERE id = '${baton.messageId}'
''');
          expect(mentions.single[0], isEmpty);
          expect(mentions.single[1], anyOf(isNull, isEmpty));
        },
      );

      test(
        'empty text is allowed on a reply baton and keeps the reply',
        () async {
          final baton = await createOnRequest(
            replyToMessageId: _requestMessage,
          );

          await update(baton, text: '   ');

          final message = await _message(writer, baton.messageId);
          expect(message.body, '');
          expect(message.replyTo, _requestMessage);
        },
      );

      test(
        'empty text on a standalone baton is rejected, nothing changes',
        () async {
          final baton = await createOnRequest();
          final before = await snapshot(baton);

          await expectLater(
            update(
              baton,
              text: '  ',
              candidates: [(userId: _member, tier: 1)],
            ),
            throwsA(isA<BatonMessageNotEligibleException>()),
          );

          expect(await snapshot(baton), before);
        },
      );

      test('an over-long ask is rejected, nothing changes', () async {
        final baton = await createOnRequest();
        final before = await snapshot(baton);

        await expectLater(
          update(baton, text: 'x' * (kMaxRoomMessageBodyLength + 1)),
          throwsA(isA<BeaconCreateException>()),
        );

        expect(await snapshot(baton), before);
      });

      test('a non-author is rejected, nothing changes', () async {
        final baton = await createOnRequest();
        final before = await snapshot(baton);

        for (final actor in [_candA, _member]) {
          await expectLater(
            update(baton, actorId: actor),
            throwsA(isA<BatonNotAuthorException>()),
            reason: actor,
          );
        }

        expect(await snapshot(baton), before);
      });

      test('an unknown baton is rejected', () async {
        await expectLater(
          batonCase.update(
            actorId: _author,
            batonId: 'Lbatoncase_none',
            text: newAsk,
            candidates: [(userId: _candA, tier: 1)],
          ),
          throwsA(isA<BatonNotFoundException>()),
        );
      });

      for (final (label, setStatus) in [
        (
          'taken',
          'status = 1, selection_mode = 1, resolved_at = now(), '
              "taker_id = '$_candA'",
        ),
        ('cancelled', 'status = 2, resolved_at = now()'),
      ]) {
        test('a $label baton cannot be edited, nothing changes', () async {
          final baton = await createOnRequest();
          await writer.execute(
            'UPDATE public.beacon_room_baton SET $setStatus',
          );
          final before = await snapshot(baton);

          await expectLater(
            update(
              baton,
              candidates: [
                (userId: _candA, tier: 1),
                (userId: _member, tier: 1),
              ],
            ),
            throwsA(isA<BatonNotCollectingException>()),
          );

          expect(await snapshot(baton), before);
        });
      }

      test('a read-only room rejects the edit, nothing changes', () async {
        final baton = await createOnRequest();
        await writer.execute('''
UPDATE public.beacon SET status = ${BeaconStatus.closed.smallintValue}
WHERE id = '$_request'
''');
        final before = await snapshot(baton);

        await expectLater(
          update(baton),
          throwsA(isA<BeaconCreateException>()),
        );

        expect(await snapshot(baton), before);
      });

      for (final (label, candidates)
          in <(String, List<({String userId, int tier})>)>[
            ('an empty list', []),
            (
              'more than twelve people',
              [
                for (var i = 0; i < 13; i++)
                  (userId: 'Ubatoncase_x$i', tier: 1),
              ],
            ),
            (
              'the author',
              [(userId: _candA, tier: 1), (userId: _author, tier: 1)],
            ),
            (
              'a non-admitted person',
              [(userId: _member, tier: 1), (userId: _outsider, tier: 1)],
            ),
            (
              'a duplicate',
              [(userId: _member, tier: 1), (userId: _member, tier: 2)],
            ),
            (
              'a bad tier',
              [(userId: _member, tier: 1), (userId: _candA, tier: 4)],
            ),
          ]) {
        test(
          'a candidate list with $label is rejected with no partial writes',
          () async {
            final baton = await createOnRequest();
            final before = await snapshot(baton);

            await expectLater(
              update(baton, candidates: candidates),
              throwsA(isA<BatonInvalidCandidatesException>()),
            );

            expect(await snapshot(baton), before);
          },
        );
      }

      test('a removed candidate now sees the observer view', () async {
        final baton = await createOnRequest();
        await batonCase.respond(
          actorId: _candB,
          batonId: baton.id,
          canHelp: true,
        );
        final room = BeaconRoomRepository(database);
        Future<Map<String, Object?>> viewOf(String viewer) async {
          final rows = await room.listMessagesEnriched(
            beaconId: _request,
            viewerUserId: viewer,
          );
          final raw = rows.singleWhere((r) => r['id'] == baton.messageId);
          return (jsonDecode(raw['batonDataJson']! as String) as Map)
              .cast<String, Object?>();
        }

        expect((await viewOf(_candB))['viewerRole'], 'candidate');

        await update(baton, candidates: [(userId: _candA, tier: 1)]);

        expect(await viewOf(_candB), {
          'id': baton.id,
          'status': 'collecting',
          'viewerRole': 'observer',
        });
        final author = await viewOf(_author);
        expect(
          (author['candidates']! as List)
              .map((c) => (c as Map)['userId'])
              .toList(),
          [_candA],
        );
      });

      test('a removed and re-added person is asked again', () async {
        final baton = await createOnRequest();
        await update(baton, candidates: [(userId: _candA, tier: 1)]);

        await update(
          baton,
          text: 'A different ask this time',
          candidates: [(userId: _candA, tier: 1), (userId: _candB, tier: 1)],
        );

        final rows = await _candidateRows(writer);
        expect(rows.keys.toSet(), {_candA, _candB});
        expect(rows[_candB]!.response, 0);
      });
    });
  });
}

RoomBatonCase _buildCase(TenturaDb db, Env env) {
  final logger = Logger('RoomBatonCasePgTest');
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
    env: env,
    logger: logger,
  );
}

Future<int> _count(Connection writer, String table) async {
  final rows = await writer.execute('SELECT count(*) FROM public.$table');
  return rows.single[0]! as int;
}

Future<void> _expectNothingWritten(Connection writer) async {
  final batonMessages = await writer.execute(
    'SELECT count(*) FROM public.beacon_room_message '
    'WHERE semantic_marker = ${BeaconRoomSemanticMarker.baton}',
  );
  expect(batonMessages.single[0], 0, reason: 'no baton message posted');
  expect(await _count(writer, 'beacon_room_baton'), 0);
  expect(await _count(writer, 'beacon_room_baton_candidate'), 0);
  expect(await _receiptRecipients(writer, 'batonAsked'), isEmpty);
  expect(await _receiptRecipients(writer, 'batonAllAnswered'), isEmpty);
}

typedef _Message = ({
  String beaconId,
  String author,
  String body,
  String? replyTo,
  int? marker,
});

Future<_Message> _message(Connection writer, String id) async {
  final r = (await writer.execute(
    Sql.named('''
SELECT beacon_id, author_id, body, reply_to_message_id, semantic_marker
FROM public.beacon_room_message WHERE id = @id
'''),
    parameters: {'id': id},
  )).single;
  return (
    beaconId: r[0]! as String,
    author: r[1]! as String,
    body: r[2]! as String,
    replyTo: r[3] as String?,
    marker: r[4] as int?,
  );
}

Env _withRoomMessageLimit(Env base, int max) => Env(
  environment: Environment.test,
  pgHost: base.pgHost,
  pgPort: base.pgPort,
  pgDatabase: base.pgDatabase,
  pgUsername: base.pgUsername,
  pgPassword: base.pgPassword,
  printEnv: false,
  isDebugModeOn: false,
  roomMessageMaxPerUser: max,
);

typedef _CandidateRow = ({int tier, int response, DateTime? respondedAt});

Future<Map<String, _CandidateRow>> _candidateRows(Connection writer) async {
  final rows = await writer.execute(
    'SELECT user_id, tier, response, responded_at '
    'FROM public.beacon_room_baton_candidate',
  );
  return {
    for (final r in rows)
      r[0]! as String: (
        tier: r[1]! as int,
        response: r[2]! as int,
        respondedAt: r[3] as DateTime?,
      ),
  };
}

Future<DateTime?> _allAnsweredStamp(Connection writer) async {
  final rows = await writer.execute(
    'SELECT all_answered_notified_at FROM public.beacon_room_baton',
  );
  return rows.single[0] as DateTime?;
}

Future<DateTime?> _editedAt(Connection writer, String messageId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT edited_at FROM public.beacon_room_message WHERE id = @id',
    ),
    parameters: {'id': messageId},
  );
  return rows.single[0] as DateTime?;
}

Future<Map<String, int>> _responses(Connection writer) async {
  final rows = await writer.execute(
    'SELECT user_id, response FROM public.beacon_room_baton_candidate',
  );
  return {for (final r in rows) r[0]! as String: r[1]! as int};
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

/// Everything persisted for one recipient's receipt, as text.
Future<String> _receiptBlob(
  Connection writer,
  String eventType,
  String recipient,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT row_to_json(outbox)::text || row_to_json(occ)::text
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = @type AND outbox.account_id = @recipient
'''),
    parameters: {'type': eventType, 'recipient': recipient},
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
  public.polling,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _candA, _candB, _member, _outsider];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('batoncase', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  var n = 0;
  for (final beacon in [_request, _post]) {
    for (final user in [_author, _candA, _candB, _member]) {
      await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pbatoncase${(n++).toString().padLeft(3, '0')}', '$beacon', '$user', 0, 0, 3)
''');
    }
  }
  await writer.execute('''
INSERT INTO public.polling (id, author_id, question)
VALUES ('Zbatoncase_pl1', '$_author', 'Which day?')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  ('$_requestMessage', '$_request', '$_author', '$_requestBody'),
  ('$_postMessage', '$_post', '$_author', 'Can someone take this?'),
  ('$_foreignMessage', '$_request', '$_member', 'Someone else wrote this')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, linked_polling_id)
VALUES ('$_pollMessage', '$_request', '$_author', 'Poll', 'Zbatoncase_pl1')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, system_message_kind)
VALUES ('$_noticeMessage', '$_request', '$_author', 'Notice', 1)
''');
  await writer.execute('''
INSERT INTO public.coordination_item (id, beacon_id, kind, creator_id)
VALUES ('Ithread000001', '$_request', 0, '$_author')
''');
  await writer.execute(
    "SET tentura.discussion_internal_fixture = 'allow_non_general'",
  );
  try {
    await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, thread_item_id)
VALUES ('$_threadMessage', '$_request', '$_author', 'Threaded', 'Ithread000001')
''');
  } finally {
    await writer.execute('RESET tentura.discussion_internal_fixture');
  }
  await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, semantic_marker)
VALUES ('$_systemMessage', '$_request', '$_author', 'Marker', 1)
''');
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
