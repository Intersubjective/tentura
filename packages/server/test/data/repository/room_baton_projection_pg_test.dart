@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/room_baton_repository.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ubatonprj_au1';
const _a = 'Ubatonprj_ca1';
const _b = 'Ubatonprj_cb1';
const _c = 'Ubatonprj_cc1';
const _d = 'Ubatonprj_cd1';
const _observer = 'Ubatonprj_ob1';

const _request = 'Bbatonprj_rq1';
const _message = 'Rbatonprj_rq1';
const _plainMessage = 'Rbatonprj_pl1';
const _pollMessage = 'Rbatonprj_po1';
const _pollId = 'Zbatonprj_po1';
const _batonId = 'Lbatonprj_ba1';

const _titles = <String, String>{
  _author: 'Author Name',
  _a: 'Alice Name',
  _b: 'Bob Name',
  _c: 'Carol Name',
  _d: 'Dave Name',
  _observer: 'Olga Name',
};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_BATON_PROJECTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_baton_projection',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('viewer-specific baton data on room messages', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late BeaconRoomRepository room;
    late RoomBatonRepository batons;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      room = BeaconRoomRepository(database);
      batons = RoomBatonRepository(database);
    });

    setUp(() => _resetFixture(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    /// Raw `batonDataJson` string the viewer receives for [messageId].
    Future<String?> rawFor(String viewer, [String messageId = _message]) async {
      final rows = await room.listMessagesEnriched(
        beaconId: _request,
        viewerUserId: viewer,
      );
      final row = rows.singleWhere((r) => r['id'] == messageId);
      expect(
        row.containsKey('batonDataJson'),
        isTrue,
        reason: 'every message row carries the batonDataJson key',
      );
      return row['batonDataJson'] as String?;
    }

    Future<Map<String, Object?>?> payloadFor(
      String viewer, [
      String messageId = _message,
    ]) async {
      final raw = await rawFor(viewer, messageId);
      if (raw == null) {
        return null;
      }
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    }

    /// A (tier 1, can_help), B (tier 2, cant_help), C (tier 1, waiting).
    Future<void> createBaton({
      List<({String userId, int tier})>? candidates,
      Map<String, BatonResponse>? responses,
    }) async {
      await batons.create(
        id: _batonId,
        messageId: _message,
        beaconId: _request,
        authorId: _author,
        candidates:
            candidates ??
            [
              (userId: _a, tier: 1),
              (userId: _b, tier: 2),
              (userId: _c, tier: 1),
            ],
      );
      final answers =
          responses ?? {_a: BatonResponse.canHelp, _b: BatonResponse.cantHelp};
      for (final e in answers.entries) {
        await batons.updateCandidateResponse(
          batonId: _batonId,
          userId: e.key,
          response: e.value,
          respondedAt: DateTime.utc(2026, 10, 1, 12),
        );
      }
    }

    Future<void> selectTaker(
      String takerId,
      BatonSelectionMode mode,
    ) => batons.select(
      batonId: _batonId,
      takerId: takerId,
      mode: mode,
      resolvedAt: DateTime.utc(2026, 10, 2, 12),
    );

    Future<void> cancelBaton() => batons.cancel(
      batonId: _batonId,
      resolvedAt: DateTime.utc(2026, 10, 2, 12),
    );

    /// Asserts [raw] leaks nothing about [others]: neither ids nor titles,
    /// and none of the author-only candidate-list fields.
    void expectNoLeakOf(String raw, Iterable<String> others) {
      for (final other in others) {
        expect(raw, isNot(contains(other)), reason: 'id of $other leaked');
        expect(
          raw,
          isNot(contains(_titles[other])),
          reason: 'title of $other leaked',
        );
      }
      for (final key in [
        'candidates',
        'tier',
        'respondedAt',
        'eligibleCount',
      ]) {
        expect(
          raw,
          isNot(contains('"$key"')),
          reason: 'author-only field $key leaked',
        );
      }
    }

    group('while collecting', () {
      test(
        'author sees every candidate with tier, response and titles',
        () async {
          await createBaton();

          final payload = await payloadFor(_author);

          expect(payload, isNotNull);
          expect(
            payload!.keys.toSet(),
            {
              'id',
              'status',
              'viewerRole',
              'candidates',
              'allAnswered',
              'eligibleCount',
            },
          );
          expect(payload['id'], _batonId);
          expect(payload['status'], 'collecting');
          expect(payload['viewerRole'], 'author');
          expect(payload['allAnswered'], isFalse);
          expect(payload['eligibleCount'], 1);

          final candidates = (payload['candidates']! as List)
              .cast<Map<String, Object?>>();
          expect(candidates, hasLength(3));
          final byUser = {
            for (final c in candidates) c['userId']! as String: c,
          };
          expect(byUser.keys.toSet(), {_a, _b, _c});
          for (final c in candidates) {
            expect(
              c.keys.toSet(),
              {'userId', 'title', 'tier', 'response', 'respondedAt'},
            );
            expect(c['title'], _titles[c['userId']]);
          }
          expect(byUser[_a]!['tier'], 1);
          expect(byUser[_a]!['response'], 'can_help');
          expect(byUser[_a]!['respondedAt'], isNotNull);
          expect(byUser[_b]!['tier'], 2);
          expect(byUser[_b]!['response'], 'cant_help');
          expect(byUser[_b]!['respondedAt'], isNotNull);
          expect(byUser[_c]!['tier'], 1);
          expect(byUser[_c]!['response'], 'waiting');
          expect(byUser[_c]!['respondedAt'], isNull);
        },
      );

      test('author sees allAnswered once nobody is waiting', () async {
        await createBaton(
          responses: {
            _a: BatonResponse.canHelp,
            _b: BatonResponse.cantHelp,
            _c: BatonResponse.canHelp,
          },
        );

        final payload = await payloadFor(_author);

        expect(payload, isNotNull);
        expect(payload!['allAnswered'], isTrue);
        expect(payload['eligibleCount'], 2);
      });

      test(
        'candidate sees only its own response and no other candidate id',
        () async {
          await createBaton();

          final raw = await rawFor(_a);
          expect(raw, isNotNull);
          final payload = (jsonDecode(raw!) as Map).cast<String, Object?>();

          expect(payload.keys.toSet(), {
            'id',
            'status',
            'viewerRole',
            'myResponse',
          });
          expect(payload['id'], _batonId);
          expect(payload['status'], 'collecting');
          expect(payload['viewerRole'], 'candidate');
          expect(payload['myResponse'], 'can_help');
          expectNoLeakOf(raw, [_b, _c, _author, _observer]);
        },
      );

      test(
        'refusing and waiting candidates see their own state only',
        () async {
          await createBaton();

          final refusedRaw = await rawFor(_b);
          final waitingRaw = await rawFor(_c);
          final refused = (jsonDecode(refusedRaw!) as Map)
              .cast<String, Object?>();
          final waiting = (jsonDecode(waitingRaw!) as Map)
              .cast<String, Object?>();
          expectNoLeakOf(refusedRaw, [_a, _c, _observer]);
          expectNoLeakOf(waitingRaw, [_a, _b, _observer]);

          expect(refused, isNotNull);
          expect(refused['viewerRole'], 'candidate');
          expect(refused['status'], 'collecting');
          expect(refused['myResponse'], 'cant_help');
          expect(waiting, isNotNull);
          expect(waiting['viewerRole'], 'candidate');
          expect(waiting['status'], 'collecting');
          expect(waiting['myResponse'], 'waiting');
          for (final p in [refused, waiting]) {
            expect(p.keys.toSet(), {
              'id',
              'status',
              'viewerRole',
              'myResponse',
            });
          }
        },
      );

      test('a room member who was not asked sees nothing', () async {
        await createBaton();

        expect(await rawFor(_observer), isNull);
      });
    });

    group('after the author selects a taker', () {
      Future<void> takeByA() async {
        await createBaton(
          candidates: [
            (userId: _a, tier: 1),
            (userId: _b, tier: 2),
            (userId: _c, tier: 1),
            (userId: _d, tier: 1),
          ],
          responses: {
            _a: BatonResponse.canHelp,
            _b: BatonResponse.cantHelp,
            _d: BatonResponse.canHelp,
          },
        );
        await selectTaker(_a, BatonSelectionMode.manual);
      }

      test('author sees the collecting view plus taker and mode', () async {
        await takeByA();

        final payload = await payloadFor(_author);

        expect(payload, isNotNull);
        expect(payload!.keys.toSet(), {
          'id',
          'status',
          'viewerRole',
          'candidates',
          'allAnswered',
          'eligibleCount',
          'taker',
          'selectionMode',
        });
        expect(payload['viewerRole'], 'author');
        expect(payload['status'], 'taken');
        expect(payload['taker'], {'id': _a, 'title': _titles[_a]});
        expect(payload['selectionMode'], 'manual');
        expect(
          (payload['candidates']! as List).length,
          4,
          reason: 'the author keeps the full candidate list',
        );
      });

      test('observer sees only the taker, never candidates', () async {
        await takeByA();

        final raw = await rawFor(_observer);
        expect(raw, isNotNull);
        final payload = (jsonDecode(raw!) as Map).cast<String, Object?>();

        expect(payload.keys.toSet(), {'id', 'status', 'viewerRole', 'taker'});
        expect(payload['viewerRole'], 'observer');
        expect(payload['status'], 'taken');
        expect(payload['taker'], {'id': _a, 'title': _titles[_a]});
        expect(payload.containsKey('candidates'), isFalse);
        expectNoLeakOf(raw, [_b, _c, _d, _author]);
      });

      test('the taker sees outcome "you" and itself as taker', () async {
        await takeByA();

        final raw = await rawFor(_a);
        expect(raw, isNotNull);
        final payload = (jsonDecode(raw!) as Map).cast<String, Object?>();

        expectNoLeakOf(raw, [_b, _c, _d]);
        expect(payload.keys.toSet(), {
          'id',
          'status',
          'viewerRole',
          'myResponse',
          'outcome',
          'taker',
        });
        expect(payload['viewerRole'], 'candidate');
        expect(payload['status'], 'taken');
        expect(payload['myResponse'], 'can_help');
        expect(payload['outcome'], 'you');
        expect(payload['taker'], {'id': _a, 'title': _titles[_a]});
      });

      test(
        'another can-help candidate sees "someoneElse" without the taker',
        () async {
          await takeByA();

          final raw = await rawFor(_d);
          expect(raw, isNotNull);
          final payload = (jsonDecode(raw!) as Map).cast<String, Object?>();

          expect(payload.keys.toSet(), {
            'id',
            'status',
            'viewerRole',
            'myResponse',
            'outcome',
          });
          expect(payload['status'], 'taken');
          expect(payload['outcome'], 'someoneElse');
          expect(payload['myResponse'], 'can_help');
          expect(payload.containsKey('taker'), isFalse);
          expectNoLeakOf(raw, [_a, _b, _c]);
        },
      );

      test(
        'candidates who refused or never answered see "closed" without the taker',
        () async {
          await takeByA();

          for (final (viewer, response) in [
            (_b, 'cant_help'),
            (_c, 'waiting'),
          ]) {
            final raw = await rawFor(viewer);
            expect(raw, isNotNull, reason: '$viewer is a candidate');
            final payload = (jsonDecode(raw!) as Map).cast<String, Object?>();

            expect(payload.keys.toSet(), {
              'id',
              'status',
              'viewerRole',
              'myResponse',
              'outcome',
            });
            expect(payload['status'], 'taken');
            expect(payload['outcome'], 'closed');
            expect(payload['myResponse'], response);
            expect(payload.containsKey('taker'), isFalse);
            expectNoLeakOf(raw, [_a, _d, if (viewer == _b) _c else _b]);
          }
        },
      );
    });

    group('after the author cancels', () {
      setUp(() async {
        await createBaton();
        await cancelBaton();
      });

      test('author and observer see nothing', () async {
        expect(await rawFor(_author), isNull);
        expect(await rawFor(_observer), isNull);
      });

      test('every candidate sees only a closed outcome', () async {
        for (final viewer in [_a, _b, _c]) {
          final raw = await rawFor(viewer);
          expect(raw, isNotNull, reason: '$viewer is a candidate');
          final payload = (jsonDecode(raw!) as Map).cast<String, Object?>();

          expect(payload.keys.toSet(), {
            'id',
            'status',
            'viewerRole',
            'outcome',
          });
          expect(payload['viewerRole'], 'candidate');
          expect(payload['status'], 'cancelled');
          expect(payload['outcome'], 'closed');
          expectNoLeakOf(raw, [
            for (final other in [_a, _b, _c])
              if (other != viewer) other,
          ]);
        }
      });
    });

    group('messages without a baton', () {
      test('carry a null batonDataJson for every viewer', () async {
        await createBaton();

        for (final viewer in [_author, _a, _observer]) {
          expect(await rawFor(viewer, _plainMessage), isNull);
        }
      });

      test('keep pollDataJson unchanged alongside a baton elsewhere', () async {
        await createBaton();

        final rows = await room.listMessagesEnriched(
          beaconId: _request,
          viewerUserId: _a,
        );
        final poll = rows.singleWhere((r) => r['id'] == _pollMessage);

        expect(poll.containsKey('batonDataJson'), isTrue);
        expect(poll['batonDataJson'], isNull);
        final pollData = (jsonDecode(poll['pollDataJson']! as String) as Map)
            .cast<String, Object?>();
        expect(pollData['id'], _pollId);
        expect(pollData['question'], 'Which day?');
        expect(pollData.containsKey('batonDataJson'), isFalse);

        final batonMessage = rows.singleWhere((r) => r['id'] == _message);
        expect(batonMessage['pollDataJson'], isNull);
        expect(batonMessage['batonDataJson'], isNotNull);
      });
    });
  });
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_room_baton_candidate,
  public.beacon_room_baton,
  public.polling,
  public.beacon_room_message,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _a, _b, _c, _d, _observer];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @title, @key)
'''),
      parameters: {
        'id': users[i],
        'title': _titles[users[i]],
        'key': pgTestPublicKey('batonprj', i + 1),
      },
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
VALUES ('Pbatonprj${(n++).toString().padLeft(3, '0')}', '$_request', '$user', 0, 0, 3)
''');
  }
  await writer.execute('''
INSERT INTO public.polling (id, author_id, question)
VALUES ('$_pollId', '$_author', 'Which day?')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  ('$_message', '$_request', '$_author', 'Can someone take this?'),
  ('$_plainMessage', '$_request', '$_author', 'Just a note')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, linked_polling_id)
VALUES ('$_pollMessage', '$_request', '$_author', 'Poll', '$_pollId')
''');
}
