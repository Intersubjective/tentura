import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_baton_data.dart';

String _json(Map<String, Object?> map) => jsonEncode(map);

void main() {
  group('RoomBatonData.tryParse viewer shapes', () {
    test('author while collecting: candidates, allAnswered, eligibleCount', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'collecting',
          'viewerRole': 'author',
          'candidates': [
            {
              'userId': 'Uaaaaaaaaaaa',
              'title': 'Alice',
              'tier': 1,
              'response': 'can_help',
              'respondedAt': '2026-10-05T10:00:00.000Z',
            },
            {
              'userId': 'Ubbbbbbbbbbb',
              'title': 'Bob',
              'tier': 2,
              'response': 'cant_help',
              'respondedAt': '2026-10-05T10:05:00.000Z',
            },
            {
              'userId': 'Uccccccccccc',
              'title': 'Carol',
              'tier': 1,
              'response': 'waiting',
              'respondedAt': null,
            },
          ],
          'allAnswered': false,
          'eligibleCount': 1,
        }),
      );

      expect(data, isA<RoomBatonAuthorData>());
      final author = data! as RoomBatonAuthorData;
      expect(author.id, 'Zbaton000001');
      expect(author.status, RoomBatonStatus.collecting);
      expect(author.allAnswered, isFalse);
      expect(author.eligibleCount, 1);
      expect(author.taker, isNull);
      expect(author.selectionMode, isNull);
      expect(author.candidates.map((c) => c.userId), [
        'Uaaaaaaaaaaa',
        'Ubbbbbbbbbbb',
        'Uccccccccccc',
      ]);
      expect(author.candidates.map((c) => c.title), ['Alice', 'Bob', 'Carol']);
      expect(author.candidates.map((c) => c.tier), [1, 2, 1]);
      expect(author.candidates.map((c) => c.response), [
        RoomBatonResponse.canHelp,
        RoomBatonResponse.cantHelp,
        RoomBatonResponse.waiting,
      ]);
      expect(
        author.candidates.first.respondedAt,
        DateTime.utc(2026, 10, 5, 10),
      );
      expect(author.candidates.first.respondedAt!.isUtc, isTrue);
      expect(author.candidates.last.respondedAt, isNull);
    });

    test('author after selection carries taker and selection mode', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'taken',
          'viewerRole': 'author',
          'candidates': [
            {
              'userId': 'Uaaaaaaaaaaa',
              'title': 'Alice',
              'tier': 1,
              'response': 'can_help',
              'respondedAt': '2026-10-05T10:00:00.000Z',
            },
          ],
          'allAnswered': true,
          'eligibleCount': 1,
          'taker': {'id': 'Uaaaaaaaaaaa', 'title': 'Alice'},
          'selectionMode': 'manual',
        }),
      );

      final author = data! as RoomBatonAuthorData;
      expect(author.status, RoomBatonStatus.taken);
      expect(author.allAnswered, isTrue);
      expect(author.taker?.id, 'Uaaaaaaaaaaa');
      expect(author.taker?.title, 'Alice');
      expect(author.selectionMode, RoomBatonSelectionMode.manual);
    });

    test('author selection mode auto is recognised', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'taken',
          'viewerRole': 'author',
          'candidates': <Object?>[],
          'allAnswered': true,
          'eligibleCount': 0,
          'taker': {'id': 'Uaaaaaaaaaaa', 'title': 'Alice'},
          'selectionMode': 'auto',
        }),
      );

      expect(
        (data! as RoomBatonAuthorData).selectionMode,
        RoomBatonSelectionMode.auto,
      );
    });

    test('candidate while collecting sees only their own response', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'collecting',
          'viewerRole': 'candidate',
          'myResponse': 'can_help',
        }),
      );

      expect(data, isA<RoomBatonCandidateData>());
      final candidate = data! as RoomBatonCandidateData;
      expect(candidate.id, 'Zbaton000001');
      expect(candidate.status, RoomBatonStatus.collecting);
      expect(candidate.myResponse, RoomBatonResponse.canHelp);
      expect(candidate.outcome, isNull);
      expect(candidate.taker, isNull);
    });

    test('candidate still waiting maps to the waiting response', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'collecting',
          'viewerRole': 'candidate',
          'myResponse': 'waiting',
        }),
      );

      expect(
        (data! as RoomBatonCandidateData).myResponse,
        RoomBatonResponse.waiting,
      );
    });

    test('candidate who was selected gets outcome you and the taker', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'taken',
          'viewerRole': 'candidate',
          'myResponse': 'can_help',
          'outcome': 'you',
          'taker': {'id': 'Uaaaaaaaaaaa', 'title': 'Alice'},
        }),
      );

      final candidate = data! as RoomBatonCandidateData;
      expect(candidate.status, RoomBatonStatus.taken);
      expect(candidate.outcome, RoomBatonOutcome.you);
      expect(candidate.taker?.id, 'Uaaaaaaaaaaa');
    });

    test('candidate who was not chosen gets someoneElse and no taker', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'taken',
          'viewerRole': 'candidate',
          'myResponse': 'can_help',
          'outcome': 'someoneElse',
        }),
      );

      final candidate = data! as RoomBatonCandidateData;
      expect(candidate.outcome, RoomBatonOutcome.someoneElse);
      expect(candidate.taker, isNull);
    });

    test('candidate who declined sees closed and no taker after selection', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'taken',
          'viewerRole': 'candidate',
          'myResponse': 'cant_help',
          'outcome': 'closed',
        }),
      );

      final candidate = data! as RoomBatonCandidateData;
      expect(candidate.status, RoomBatonStatus.taken);
      expect(candidate.myResponse, RoomBatonResponse.cantHelp);
      expect(candidate.outcome, RoomBatonOutcome.closed);
      expect(candidate.taker, isNull);
    });

    test('candidate who never answered sees closed and no taker after '
        'selection', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'taken',
          'viewerRole': 'candidate',
          'myResponse': 'waiting',
          'outcome': 'closed',
        }),
      );

      final candidate = data! as RoomBatonCandidateData;
      expect(candidate.status, RoomBatonStatus.taken);
      expect(candidate.myResponse, RoomBatonResponse.waiting);
      expect(candidate.outcome, RoomBatonOutcome.closed);
      expect(candidate.taker, isNull);
    });

    test('candidate on a cancelled baton gets closed without a response', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'cancelled',
          'viewerRole': 'candidate',
          'outcome': 'closed',
        }),
      );

      final candidate = data! as RoomBatonCandidateData;
      expect(candidate.status, RoomBatonStatus.cancelled);
      expect(candidate.outcome, RoomBatonOutcome.closed);
      expect(candidate.myResponse, isNull);
      expect(candidate.taker, isNull);
    });

    test('observer after selection sees only the taker', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'taken',
          'viewerRole': 'observer',
          'taker': {'id': 'Uaaaaaaaaaaa', 'title': 'Alice'},
        }),
      );

      expect(data, isA<RoomBatonObserverData>());
      final observer = data! as RoomBatonObserverData;
      expect(observer.id, 'Zbaton000001');
      expect(observer.status, RoomBatonStatus.taken);
      expect(observer.taker.id, 'Uaaaaaaaaaaa');
      expect(observer.taker.title, 'Alice');
    });
  });

  group('RoomBatonData.tryParse tolerance', () {
    test('ignores unknown keys at every level', () {
      final data = RoomBatonData.tryParse(
        _json({
          'id': 'Zbaton000001',
          'status': 'collecting',
          'viewerRole': 'author',
          'futureField': {'nested': true},
          'candidates': [
            {
              'userId': 'Uaaaaaaaaaaa',
              'title': 'Alice',
              'tier': 1,
              'response': 'waiting',
              'respondedAt': null,
              'futureCandidateField': 42,
            },
          ],
          'allAnswered': false,
          'eligibleCount': 0,
        }),
      );

      final author = data! as RoomBatonAuthorData;
      expect(author.candidates, hasLength(1));
      expect(author.candidates.single.userId, 'Uaaaaaaaaaaa');
    });

    test('null, empty and blank payloads parse to null', () {
      expect(RoomBatonData.tryParse(null), isNull);
      expect(RoomBatonData.tryParse(''), isNull);
      expect(RoomBatonData.tryParse('null'), isNull);
    });

    test('non-JSON text parses to null', () {
      expect(RoomBatonData.tryParse('not json'), isNull);
      expect(RoomBatonData.tryParse('{"id":'), isNull);
    });

    test('JSON that is not an object parses to null', () {
      expect(RoomBatonData.tryParse('[]'), isNull);
      expect(RoomBatonData.tryParse('"collecting"'), isNull);
      expect(RoomBatonData.tryParse('7'), isNull);
    });

    test('missing id parses to null', () {
      expect(
        RoomBatonData.tryParse(
          _json({
            'status': 'collecting',
            'viewerRole': 'candidate',
            'myResponse': 'waiting',
          }),
        ),
        isNull,
      );
    });

    test('unknown viewer role parses to null', () {
      expect(
        RoomBatonData.tryParse(
          _json({
            'id': 'Zbaton000001',
            'status': 'collecting',
            'viewerRole': 'moderator',
          }),
        ),
        isNull,
      );
    });

    test('unknown or missing status parses to null', () {
      expect(
        RoomBatonData.tryParse(
          _json({
            'id': 'Zbaton000001',
            'status': 'exploded',
            'viewerRole': 'candidate',
            'myResponse': 'waiting',
          }),
        ),
        isNull,
      );
      expect(
        RoomBatonData.tryParse(
          _json({
            'id': 'Zbaton000001',
            'viewerRole': 'candidate',
            'myResponse': 'waiting',
          }),
        ),
        isNull,
      );
    });

    test('author payload without a candidates list parses to null', () {
      expect(
        RoomBatonData.tryParse(
          _json({
            'id': 'Zbaton000001',
            'status': 'collecting',
            'viewerRole': 'author',
            'allAnswered': false,
            'eligibleCount': 0,
          }),
        ),
        isNull,
      );
    });

    test('author payload with a malformed candidate row parses to null', () {
      expect(
        RoomBatonData.tryParse(
          _json({
            'id': 'Zbaton000001',
            'status': 'collecting',
            'viewerRole': 'author',
            'candidates': [
              {'title': 'no user id', 'tier': 1, 'response': 'waiting'},
            ],
            'allAnswered': false,
            'eligibleCount': 0,
          }),
        ),
        isNull,
      );
    });

    test('observer payload without a taker parses to null', () {
      expect(
        RoomBatonData.tryParse(
          _json({
            'id': 'Zbaton000001',
            'status': 'taken',
            'viewerRole': 'observer',
          }),
        ),
        isNull,
      );
    });
  });
}
