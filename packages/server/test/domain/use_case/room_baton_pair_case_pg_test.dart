@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
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

    test(
      'partner history stays isolated and index-backed after reusing an invitation',
      () async {
        final plans = _PartnerHistoryPlans();
        final instrumentedDb = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ).interceptWith(plans),
        );
        addTearDown(instrumentedDb.close);
        final history = RoomBatonRepository(instrumentedDb);
        final realCase = _buildCase(instrumentedDb, target.databaseEnv);
        final first = await createBaton();
        final second = await createBaton();

        Future<Set<String>> named(String batonId, String candidate) =>
            history.namedPartnerIds(batonId: batonId, userId: candidate);
        Future<void> name(String batonId, String candidate, String partner) =>
            realCase.respond(
              actorId: candidate,
              batonId: batonId,
              canHelp: true,
              partnerUserId: partner,
            );

        expect(await named(first.id, _candA), isEmpty);
        await name(first.id, _candA, _partnerX);
        await name(first.id, _candA, _partnerY);
        expect(await named(first.id, _candA), {_partnerX, _partnerY});

        await name(first.id, _candB, _partnerZ);
        await name(second.id, _candA, _partnerW);
        // These are valid ledger rows with misleading keys: event type and
        // every literal underscore in the prefix must still be respected.
        await writer.execute(
          Sql.named("""
INSERT INTO public.attention_occurrence
  (source_event_key, event_type, immutable_payload)
VALUES
  (@wrongTypeKey, 'batonPartnerAnswered', '{}'::jsonb),
  (@wrongPrefixKey, 'batonPartnerAsked', '{}'::jsonb)
"""),
          parameters: {
            'wrongTypeKey':
                'baton_partner_asked:${first.id}:$_candA:$_outsider',
            'wrongPrefixKey':
                'batonXpartner_asked:${first.id}:$_candA:$_author',
          },
        );
        await writer.execute("""
INSERT INTO public.attention_occurrence
  (source_event_key, event_type, immutable_payload)
SELECT 'unrelated-event:' || i::text,
  CASE WHEN i % 2 = 0 THEN 'batonPartnerAnswered'
    ELSE 'roomMessagePosted' END,
  '{}'::jsonb
FROM generate_series(1, 1200) AS i
""");
        final noiseCount = await writer.execute(
          'SELECT count(*) FROM public.attention_occurrence '
          "WHERE source_event_key LIKE 'unrelated-event:%' "
          "AND event_type <> 'batonPartnerAsked'",
        );
        expect(noiseCount.single.single, greaterThanOrEqualTo(1000));
        await writer.execute("""
INSERT INTO public.attention_occurrence
  (source_event_key, event_type, immutable_payload)
SELECT 'baton_partner_asked:noise-baton-' || i::text || ':noise-candidate:noise-partner',
  'batonPartnerAsked', '{}'::jsonb
FROM generate_series(1, 1200) AS i
""");
        final otherAskedCount = await writer.execute(
          'SELECT count(*) FROM public.attention_occurrence '
          "WHERE starts_with(source_event_key, 'baton_partner_asked:noise-baton-') "
          "AND event_type = 'batonPartnerAsked'",
        );
        expect(otherAskedCount.single.single, greaterThanOrEqualTo(1000));
        // The migrated database accepts this non-asked occurrence. Verify
        // it actually exists before testing that its suffix is excluded.
        final decoy = await writer.execute(
          Sql.named(
            'SELECT event_type, immutable_payload::text '
            'FROM public.attention_occurrence WHERE source_event_key = @key',
          ),
          parameters: {
            'key': 'baton_partner_asked:${first.id}:$_candA:$_outsider',
          },
        );
        expect(decoy, hasLength(1));
        expect(decoy.single[0], 'batonPartnerAnswered');
        expect(jsonDecode(decoy.single[1]! as String), isEmpty);
        expect(await named(first.id, _candA), isNot(contains(_outsider)));
        await writer.execute('ANALYZE public.attention_occurrence');

        expect(await named(first.id, _candA), {_partnerX, _partnerY});
        expect(await named(first.id, _candB), {_partnerZ});
        expect(await named(second.id, _candA), {_partnerW});

        await name(first.id, _candA, _partnerZ);
        Future<List<List<Object?>>> askedRows() async => (await writer.execute(
          Sql.named(
            'SELECT id, source_event_key FROM public.attention_occurrence '
            "WHERE event_type = 'batonPartnerAsked' "
            'AND starts_with(source_event_key, @prefix) ORDER BY id',
          ),
          parameters: {
            'prefix': 'baton_partner_asked:${first.id}:$_candA:',
          },
        )).map((r) => r.toList()).toList();
        final askedBefore = await askedRows();
        expect(askedBefore, hasLength(3));
        final keysBefore = await _keys(writer, _asked);
        final eventsBefore = await _count(writer, 'attention_occurrence');
        expect((await _rows(writer, first.id))[_candA]!.invites, 3);
        await name(first.id, _candA, _partnerX);
        final row = (await _rows(writer, first.id))[_candA]!;
        expect(row.partner, _partnerX);
        expect(row.invites, 3);
        expect(await _keys(writer, _asked), keysBefore);
        expect(await _count(writer, 'attention_occurrence'), eventsBefore);
        expect(await askedRows(), askedBefore);
        await expectLater(
          name(first.id, _candA, _partnerW),
          throwsA(isA<BatonPartnerInvalidException>()),
        );
        expect(await _rows(writer, first.id), containsPair(_candA, row));
        expect(await _keys(writer, _asked), keysBefore);

        // EXPLAIN the actual repository statements and bound values rather
        // than a copy of the SQL that could drift from namedPartnerIds.
        await instrumentedDb.transaction(() async {
          plans.enabled = true;
          try {
            expect(
              await named(first.id, _candA),
              {_partnerX, _partnerY, _partnerZ},
            );
          } finally {
            plans.enabled = false;
          }
        });
        expect(
          plans.reads,
          hasLength(1),
          reason: 'Only the namedPartnerIds call is instrumented',
        );
        final read = plans.reads.single;
        expect(read.statement, contains('source_event_key'));
        expect(read.statement, contains('attention_occurrence'));
        expect(read.args, contains('baton_partner_asked:${first.id}:$_candA:'));
        expect(
          read.explainedStatement,
          'EXPLAIN (COSTS OFF) ${read.statement}',
        );
        expect(read.explainedArgs, read.args);
        expect(read.seqscan, 'off');
        final plan = read.text;
        expect(
          plan,
          isNot(matches(r'Seq Scan on (?:public\.)?attention_occurrence\b')),
          reason: 'Partner history must avoid a ledger scan:\n$plan',
        );
        final occurrenceScans = _historyPlanNodes(read.plan)
            .where(
              (node) =>
                  node['Relation Name'] == 'attention_occurrence' &&
                  {
                    'Index Scan',
                    'Index Only Scan',
                    'Bitmap Heap Scan',
                  }.contains(node['Node Type']),
            )
            .toList();
        expect(occurrenceScans, isNotEmpty, reason: plan);
        final occurrenceIndexes = await writer.execute(
          'SELECT indexname, indexdef FROM pg_indexes '
          "WHERE schemaname = 'public' AND tablename = 'attention_occurrence'",
        );
        final usedDefinitions = <String>[];
        for (final scan in occurrenceScans) {
          // A bitmap index node belongs to the occurrence heap scan above
          // it; an index used on another relation cannot satisfy this check.
          final indexNodes = _historyPlanNodes(
            scan,
          ).where((node) => node.containsKey('Index Name')).toList();
          expect(indexNodes, isNotEmpty, reason: plan);
          for (final indexNode in indexNodes) {
            final catalogRows = occurrenceIndexes
                .where(
                  (row) => row[0] == indexNode['Index Name'],
                )
                .toList();
            expect(catalogRows, hasLength(1), reason: plan);
            usedDefinitions.add(catalogRows.single[1]! as String);
            final condition = indexNode['Index Cond'] as String? ?? '';
            expect(condition, contains('source_event_key'), reason: plan);
            expect(
              condition,
              contains('baton_partner_asked:${first.id}:$_candA:'),
              reason:
                  'This occurrence index must bound the requested prefix: $plan',
            );
          }
        }
        // The event predicate can be a runtime filter/index condition or
        // the predicate of a partial index actually used by this lookup.
        final eventRestriction = [plan, ...usedDefinitions].join('\n');
        expect(eventRestriction, contains('event_type'));
        expect(eventRestriction, contains('batonPartnerAsked'));
      },
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
          _answerIs(true),
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
          _answerIs(false),
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
          answers.where((b) => _acceptedOf(b) == false),
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
          _answerIs(true),
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
            released.where((b) => _acceptedOf(b) == false),
            hasLength(1),
          );
          expect(await _peopleInSeveralPairs(writer, baton.id), isEmpty);
        },
      );

      test(
        'joining a pair whose inviter sorts first releases the older pair',
        () async {
          final baton = await createBaton();
          await respond(_candB, baton, canHelp: true, partnerUserId: _partnerX);
          await partnerRespond(_partnerX, baton, inviter: _candB, accept: true);
          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);

          await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);

          final rows = await _rows(writer, baton.id);
          expect(rows[_candA]!.partner, _partnerX);
          expect(rows[_candA]!.partnerResponse, _accepted);
          expect(rows[_candB]!.response, _waiting);
          expect(rows[_candB]!.partnerResponse, _declined);
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

    group('declining is always allowed', () {
      test(
        'an invited person who is no longer admitted can still decline',
        () async {
          final baton = await createBaton();
          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
          await writer.execute(
            "DELETE FROM public.beacon_participant WHERE user_id = '$_partnerX'",
          );

          await partnerRespond(
            _partnerX,
            baton,
            inviter: _candA,
            accept: false,
          );

          final row = (await _rows(writer, baton.id))[_candA]!;
          expect(row.response, _waiting);
          expect(row.partnerResponse, _declined);
          expect(row.respondedAt, isNull);
          expect(await _recipients(writer, _answered), [_candA]);
          expect(
            await _eventBlob(writer, _answered, _candA),
            _answerIs(false),
          );
        },
      );

      for (final (label, blocker, blocked) in [
        ('the invited person blocked the inviter', _partnerX, _candA),
        ('the inviter blocked the invited person', _candA, _partnerX),
      ]) {
        test('an invitation can be declined when $label', () async {
          final baton = await createBaton();
          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
          await block(blocker, blocked);

          await partnerRespond(
            _partnerX,
            baton,
            inviter: _candA,
            accept: false,
          );

          final row = (await _rows(writer, baton.id))[_candA]!;
          expect(row.response, _waiting);
          expect(row.partnerResponse, _declined);
        });
      }

      test('a joined person who lost admission can still withdraw', () async {
        final baton = await createBaton();
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
        await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);
        await writer.execute(
          "DELETE FROM public.beacon_participant WHERE user_id = '$_partnerX'",
        );

        await partnerRespond(_partnerX, baton, inviter: _candA, accept: false);

        final row = (await _rows(writer, baton.id))[_candA]!;
        expect(row.response, _waiting);
        expect(row.partnerResponse, _declined);
        expect(row.respondedAt, isNull);
      });
    });

    group('a confirmed pair releases its members other invitations', () {
      Future<void> expectReleased(
        RoomBaton baton,
        String person,
      ) async {
        final row = (await _rows(writer, baton.id))[person]!;
        expect(row.response, _waiting);
        expect(row.partnerResponse, _declined);
        expect(row.respondedAt, isNull);
        final answers = await _eventBlobs(writer, _answered, person);
        expect(
          answers.where((b) => _acceptedOf(b) == false),
          hasLength(1),
          reason: '$person is told the invitation is over',
        );
      }

      test(
        'joining releases a competing invitation to the same person',
        () async {
          final baton = await createBaton();
          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
          await respond(_candB, baton, canHelp: true, partnerUserId: _partnerX);

          await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);

          final rows = await _rows(writer, baton.id);
          expect(rows[_candA]!.response, _canHelp);
          expect(rows[_candA]!.partner, _partnerX);
          expect(rows[_candA]!.partnerResponse, _accepted);
          await expectReleased(baton, _candB);
          expect(
            rows.entries.where(
              (e) =>
                  e.value.partnerResponse == _pending &&
                  (e.key == _candA ||
                      e.key == _partnerX ||
                      e.value.partner == _candA ||
                      e.value.partner == _partnerX),
            ),
            isEmpty,
          );
        },
      );

      test(
        'a chain of pending invitations is released around the new pair',
        () async {
          final baton = await createBaton(
            candidates: [
              (userId: _candA, tier: 1),
              (userId: _candB, tier: 1),
              (userId: _partnerY, tier: 1),
            ],
          );
          await respond(_candA, baton, canHelp: true, partnerUserId: _candB);
          await respond(_candB, baton, canHelp: true, partnerUserId: _partnerY);
          await respond(_partnerY, baton, canHelp: true, partnerUserId: _candA);

          await partnerRespond(_candB, baton, inviter: _candA, accept: true);

          final rows = await _rows(writer, baton.id);
          expect(rows[_candA]!.partner, _candB);
          expect(rows[_candA]!.partnerResponse, _accepted);
          expect(rows[_candB]!.partner, _candA);
          expect(rows[_candB]!.partnerResponse, _accepted);
          await expectReleased(baton, _partnerY);
          expect(
            rows.values.where(
              (r) =>
                  r.partnerResponse == _pending &&
                  (r.partner == _candA || r.partner == _candB),
            ),
            isEmpty,
          );
          expect(await _peopleInSeveralPairs(writer, baton.id), isEmpty);
        },
      );

      test(
        'a mutual pair released by choosing releases a third invitation',
        () async {
          final baton = await createBaton(
            candidates: [
              (userId: _candA, tier: 1),
              (userId: _candB, tier: 1),
              (userId: _partnerY, tier: 1),
            ],
          );
          await respond(_partnerY, baton, canHelp: true, partnerUserId: _candA);
          await respond(_candB, baton, canHelp: true, partnerUserId: _candA);

          await respond(_candA, baton, canHelp: true, partnerUserId: _candB);

          final rows = await _rows(writer, baton.id);
          expect(rows[_candA]!.partnerResponse, _accepted);
          expect(rows[_candB]!.partnerResponse, _accepted);
          await expectReleased(baton, _partnerY);
        },
      );
    });

    group('the partner cap counts distinct people', () {
      test(
        'naming the same person again after declines uses no extra slot',
        () async {
          final baton = await createBaton();
          for (var i = 0; i < 3; i++) {
            await respond(
              _candA,
              baton,
              canHelp: true,
              partnerUserId: _partnerX,
            );
            await partnerRespond(
              _partnerX,
              baton,
              inviter: _candA,
              accept: false,
            );
          }

          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
          var row = (await _rows(writer, baton.id))[_candA]!;
          expect(row.partner, _partnerX);
          expect(row.partnerResponse, _pending);
          expect(row.invites, 1);

          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerY);
          await respond(_candA, baton, canHelp: true, partnerUserId: _partnerZ);
          row = (await _rows(writer, baton.id))[_candA]!;
          expect(row.invites, 3);

          final rowsBefore = await _rows(writer, baton.id);
          await expectLater(
            respond(_candA, baton, canHelp: true, partnerUserId: _partnerW),
            throwsA(isA<BatonPartnerInvalidException>()),
          );
          expect(await _rows(writer, baton.id), rowsBefore);
        },
      );

      test('switching to someone else and back uses no extra slot', () async {
        final baton = await createBaton();
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerY);
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);

        var row = (await _rows(writer, baton.id))[_candA]!;
        expect(row.partner, _partnerX);
        expect(row.invites, 2);

        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerZ);
        row = (await _rows(writer, baton.id))[_candA]!;
        expect(row.invites, 3);

        final rowsBefore = await _rows(writer, baton.id);
        final keysBefore = await _keys(writer, _asked);
        await expectLater(
          respond(_candA, baton, canHelp: true, partnerUserId: _partnerW),
          throwsA(isA<BatonPartnerInvalidException>()),
        );
        expect(await _rows(writer, baton.id), rowsBefore);
        expect((await _rows(writer, baton.id))[_candA]!.partner, _partnerZ);
        expect(await _keys(writer, _asked), keysBefore);
        expect(await _recipients(writer, _asked), isNot(contains(_partnerW)));
      });
    });

    group('a partner whose account was deleted', () {
      late RoomBaton baton;

      setUp(() async {
        baton = await createBaton();
        await respond(_candB, baton, canHelp: true);
        await respond(_candA, baton, canHelp: true, partnerUserId: _partnerX);
        await partnerRespond(_partnerX, baton, inviter: _candA, accept: true);
        await writer.execute(
          "DELETE FROM public.beacon_participant WHERE user_id = '$_partnerX'",
        );
        await writer.execute(
          'DELETE FROM public."user" '
          "WHERE id = '$_partnerX'",
        );
        final row = (await _rows(writer, baton.id))[_candA]!;
        expect(row.partner, isNull, reason: 'fixture: partner erased');
        expect(row.partnerResponse, _accepted, reason: 'fixture');
      });

      Future<Map<String, Object?>> payloadFor(String viewer) async {
        final rows = await BeaconRoomRepository(database).listMessagesEnriched(
          beaconId: _request,
          viewerUserId: viewer,
        );
        final raw = rows.singleWhere(
          (r) => r['id'] == baton.messageId,
        )['batonDataJson'];
        return (jsonDecode(raw! as String) as Map).cast<String, Object?>();
      }

      test('is shown as waiting and not counted as eligible', () async {
        final p = await payloadFor(_author);

        final a = (p['candidates']! as List)
            .cast<Map<String, Object?>>()
            .singleWhere((c) => c['userId'] == _candA);
        expect(a['response'], 'waiting');
        expect(a.containsKey('partner'), isFalse);
        expect(
          ((p['pairs'] as List?) ?? const [])
              .cast<Map<String, Object?>>()
              .where((pair) => pair['takerUserId'] == _candA),
          isEmpty,
        );
        expect(p['eligibleCount'], 1);
        expect(p['allAnswered'], isFalse);

        final mine = await payloadFor(_candA);
        expect(
          (mine['myPartner']! as Map<String, Object?>)['status'],
          'declined',
        );
      });

      test('cannot be selected, while the solo candidate still can', () async {
        await expectLater(
          batonCase.select(
            actorId: _author,
            batonId: baton.id,
            userId: _candA,
          ),
          throwsA(isA<BatonTakerNotAvailableException>()),
        );

        await batonCase.select(actorId: _author, batonId: baton.id);

        final marker = await writer.execute(
          Sql.named(
            'SELECT system_payload::text FROM public.beacon_room_message '
            'WHERE semantic_marker = @marker AND beacon_id = @beacon',
          ),
          parameters: {
            'marker': BeaconRoomSemanticMarker.batonTaken,
            'beacon': _request,
          },
        );
        expect(
          marker,
          hasLength(1),
          reason: 'one taken marker for the request',
        );
        final payload = jsonDecode(marker.single[0]! as String) as Map;
        expect(payload['takerUserId'], _candB);
        expect(payload['coTakerUserId'], isNull);
      });
    });

    // The join and the withdrawal each hold their own pooled connection, so
    // the race needs a handle with several connections even when CI forces
    // pool size 1 for the rest of the file.
    test(
      'racing join against withdrawal always ends consistent',
      tags: [
        'multi-connection',
      ],
      () async {
        final race = openMultiConnectionPgDatabase(target);
        addTearDown(race.db.close);
        expect(
          race.env.pgPoolSettings.maxConnectionCount,
          greaterThan(1),
          reason: 'the race must not be serialized by a one-connection pool',
        );
        final raceCase = _buildCase(race.db, race.env);
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
              raceCase.partnerRespond(
                actorId: _partnerX,
                batonId: baton.id,
                inviterUserId: _candA,
                accept: true,
              ),
            ),
            raceCase.respond(
              actorId: _candA,
              batonId: baton.id,
              canHelp: false,
            ),
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
      },
    );
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

/// The `accepted` flag carried in an event blob (see `_eventBlobs`): the
/// first JSON object holding that key, read after decoding.
bool? _acceptedOf(String blob) {
  bool? found;
  void walk(Object? node) {
    if (node is Map) {
      if (node['accepted'] is bool) found ??= node['accepted'] as bool;
      node.values.forEach(walk);
    } else if (node is List) {
      node.forEach(walk);
    } else if (node is String && node.startsWith(RegExp(r'[{\[]'))) {
      try {
        walk(jsonDecode(node));
      } on FormatException {
        // not JSON
      }
    }
  }

  var rest = blob;
  while (rest.isNotEmpty) {
    final end = _firstObjectEnd(rest);
    if (end <= 0) break;
    walk(jsonDecode(rest.substring(0, end)));
    rest = rest.substring(end);
  }
  return found;
}

int _firstObjectEnd(String s) {
  var depth = 0;
  var inString = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (c == r'\\') {
        i++;
      } else if (c == '"') {
        inString = false;
      }
    } else if (c == '"') {
      inString = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}' && --depth == 0) {
      return i + 1;
    }
  }
  return -1;
}

Matcher _answerIs(bool accepted) => predicate<String>(
  (blob) => _acceptedOf(blob) == accepted,
  'an answer receipt with accepted == $accepted',
);

/// Explains each real attention read on the same executor with the original
/// parameters. Planner settings are restored before returning to the caller.
final class _PartnerHistoryPlans extends QueryInterceptor {
  bool enabled = false;
  final reads =
      <
        ({
          String statement,
          List<Object?> args,
          String explainedStatement,
          List<Object?> explainedArgs,
          String seqscan,
          String text,
          Map<String, Object?> plan,
        })
      >[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (enabled) {
      await executor.runCustom('SET enable_seqscan = off', []);
      try {
        final setting = await executor.runSelect('SHOW enable_seqscan', []);
        final explainedStatement = 'EXPLAIN (COSTS OFF) $statement';
        final explainedArgs = List<Object?>.of(args);
        final rows = await executor.runSelect(
          explainedStatement,
          explainedArgs,
        );
        final jsonRows = await executor.runSelect(
          'EXPLAIN (COSTS OFF, FORMAT JSON) $statement',
          explainedArgs,
        );
        final rawPlan = jsonRows.single.values.single;
        final decoded = rawPlan is String ? jsonDecode(rawPlan) : rawPlan;
        final root = ((decoded! as List).single as Map)['Plan']! as Map;
        reads.add((
          statement: statement,
          args: List<Object?>.of(args),
          explainedStatement: explainedStatement,
          explainedArgs: explainedArgs,
          seqscan: setting.single.values.single! as String,
          text: rows.map((row) => row.values.single).join('\n'),
          plan: root.cast<String, Object?>(),
        ));
      } finally {
        await executor.runCustom('RESET enable_seqscan', []);
      }
    }
    return super.runSelect(executor, statement, args);
  }
}

/// Walks the structured plan while preserving each relation's subtree.
Iterable<Map<String, Object?>> _historyPlanNodes(
  Map<String, Object?> node,
) sync* {
  yield node;
  for (final child in (node['Plans'] as List?) ?? const []) {
    yield* _historyPlanNodes((child as Map).cast<String, Object?>());
  }
}
