import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';

const _beaconId = 'Baaaaaaaaaaaa';
const _userId = 'Uaaaaaaaaaaaa';
const _otherUserId = 'Ubbbbbbbbbbbb';
const _factId = 'Faaaaaaaaaaaa';
const _messageId = 'Raaaaaaaaaaaa';
final _now = DateTime.utc(2026, 3, 1);

BeaconFactCardEntity testFact({
  required String id,
  int visibility = BeaconFactCardVisibilityBits.public,
  String? sourceMessageId,
  String pinnedBy = _userId,
  String factText = 'fact',
}) =>
    BeaconFactCardEntity(
      id: id,
      beaconId: _beaconId,
      factText: factText,
      visibility: visibility,
      pinnedBy: pinnedBy,
      sourceMessageId: sourceMessageId,
      createdAt: _now,
    );

class _StubFacts extends Fake implements BeaconFactCardRepositoryPort {
  List<BeaconFactCardEntity> rows = const [];
  BeaconFactCardEntity? dupBySource;
  String? lastPinnedText;
  int? lastPinnedVisibility;
  String? lastPinnedBy;
  String? lastPinnedSourceMessageId;
  String? lastCorrectedText;
  String? lastRemovedFactId;
  int? lastSetVisibility;

  @override
  Future<BeaconFactCardEntity?> findNonRemovedBySourceMessage({
    required String beaconId,
    required String sourceMessageId,
  }) async =>
      dupBySource;

  @override
  Future<List<BeaconFactCardEntity>> listForBeacon(String beaconId) async =>
      rows;

  @override
  Future<BeaconFactCardEntity> pinFact({
    required String beaconId,
    required String factText,
    required int visibility,
    required String pinnedBy,
    String? sourceMessageId,
  }) async {
    lastPinnedText = factText;
    lastPinnedVisibility = visibility;
    lastPinnedBy = pinnedBy;
    lastPinnedSourceMessageId = sourceMessageId;
    return testFact(
      id: _factId,
      visibility: visibility,
      sourceMessageId: sourceMessageId,
      pinnedBy: pinnedBy,
      factText: factText,
    );
  }

  @override
  Future<void> correct({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String newText,
  }) async {
    lastCorrectedText = newText;
  }

  @override
  Future<void> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) async {
    lastRemovedFactId = factCardId;
  }

  @override
  Future<void> setVisibility({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int visibility,
  }) async {
    lastSetVisibility = visibility;
  }
}

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  bool isAuthor = false;
  bool isSteward = false;
  BeaconParticipantRecord? participant;
  Map<String, String> attachmentsByMessageId = const {};
  Map<String, String> titlesByUserId = const {};

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      isAuthor;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async =>
      isSteward;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async =>
      participant;

  @override
  Future<Map<String, String>> attachmentsJsonByMessageIds(
    Iterable<String> messageIds,
  ) async =>
      {
        for (final id in messageIds)
          if (attachmentsByMessageId.containsKey(id)) id: attachmentsByMessageId[id]!,
      };

  @override
  Future<Map<String, String>> userTitlesByIds(Iterable<String> userIds) async =>
      {
        for (final id in userIds)
          if (titlesByUserId.containsKey(id)) id: titlesByUserId[id]!,
      };
}

void main() {
  late _StubFacts facts;
  late _StubRoom room;
  late BeaconFactCardCase case_;

  void grantAdmittedAccess() {
    room
      ..isAuthor = false
      ..isSteward = false
      ..participant = testBeaconParticipant(
        beaconId: _beaconId,
        userId: _userId,
        roomAccess: RoomAccessBits.admitted,
      );
  }

  void denyRoomAccess() {
    room
      ..isAuthor = false
      ..isSteward = false
      ..participant = testBeaconParticipant(
        beaconId: _beaconId,
        userId: _userId,
        roomAccess: RoomAccessBits.requested,
      );
  }

  setUp(() {
    facts = _StubFacts();
    room = _StubRoom();
    case_ = BeaconFactCardCase(
      facts,
      room,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconFactCardCaseTest'),
    );
    grantAdmittedAccess();
  });

  group('BeaconFactCardCase room access', () {
    test('pin allows beacon author', () async {
      room
        ..isAuthor = true
        ..participant = null;

      final r = await case_.pin(
        beaconId: _beaconId,
        factText: 'hello',
        visibility: BeaconFactCardVisibilityBits.public,
        userId: _userId,
      );

      expect(r, {'id': _factId, 'beaconId': _beaconId});
      expect(facts.lastPinnedText, 'hello');
    });

    test('pin allows beacon steward', () async {
      room
        ..isSteward = true
        ..participant = null;

      await case_.pin(
        beaconId: _beaconId,
        factText: 'steward pin',
        visibility: BeaconFactCardVisibilityBits.room,
        userId: _userId,
      );

      expect(facts.lastPinnedVisibility, BeaconFactCardVisibilityBits.room);
    });

    test('pin allows admitted participant', () async {
      grantAdmittedAccess();

      await case_.pin(
        beaconId: _beaconId,
        factText: 'member pin',
        visibility: BeaconFactCardVisibilityBits.public,
        userId: _userId,
      );

      expect(facts.lastPinnedBy, _userId);
    });

    test('pin denies user without room access', () async {
      denyRoomAccess();

      await expectLater(
        case_.pin(
          beaconId: _beaconId,
          factText: 'nope',
          visibility: BeaconFactCardVisibilityBits.public,
          userId: _userId,
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            contains('Room access required'),
          ),
        ),
      );
      expect(facts.lastPinnedText, isNull);
    });

    test('correct denies user without room access', () async {
      denyRoomAccess();

      await expectLater(
        case_.correct(
          factCardId: _factId,
          beaconId: _beaconId,
          actorUserId: _userId,
          newText: 'edit',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(facts.lastCorrectedText, isNull);
    });

    test('remove denies user without room access', () async {
      denyRoomAccess();

      await expectLater(
        case_.remove(
          factCardId: _factId,
          beaconId: _beaconId,
          actorUserId: _userId,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(facts.lastRemovedFactId, isNull);
    });

    test('setVisibility denies user without room access', () async {
      denyRoomAccess();

      await expectLater(
        case_.setVisibility(
          factCardId: _factId,
          beaconId: _beaconId,
          actorUserId: _userId,
          visibility: BeaconFactCardVisibilityBits.public,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(facts.lastSetVisibility, isNull);
    });
  });

  group('BeaconFactCardCase pin', () {
    test('throws when source message already pinned', () async {
      facts.dupBySource = testFact(
        id: 'Fexisting',
        sourceMessageId: _messageId,
      );

      await expectLater(
        case_.pin(
          beaconId: _beaconId,
          factText: 'dup',
          visibility: BeaconFactCardVisibilityBits.public,
          userId: _userId,
          sourceMessageId: _messageId,
        ),
        throwsA(
          isA<BeaconFactCardAlreadyPinnedException>().having(
            (e) => e.existingFactCardId,
            'existingFactCardId',
            'Fexisting',
          ),
        ),
      );
      expect(facts.lastPinnedText, isNull);
    });

    test('forwards sourceMessageId to repository', () async {
      await case_.pin(
        beaconId: _beaconId,
        factText: 'from chat',
        visibility: BeaconFactCardVisibilityBits.room,
        userId: _userId,
        sourceMessageId: _messageId,
      );

      expect(facts.lastPinnedSourceMessageId, _messageId);
    });
  });

  group('BeaconFactCardCase mutations', () {
    test('correct delegates to repository when admitted', () async {
      final ok = await case_.correct(
        factCardId: _factId,
        beaconId: _beaconId,
        actorUserId: _userId,
        newText: 'updated',
      );

      expect(ok, isTrue);
      expect(facts.lastCorrectedText, 'updated');
    });

    test('remove delegates to repository when admitted', () async {
      final ok = await case_.remove(
        factCardId: _factId,
        beaconId: _beaconId,
        actorUserId: _userId,
      );

      expect(ok, isTrue);
      expect(facts.lastRemovedFactId, _factId);
    });

    test('setVisibility delegates to repository when admitted', () async {
      final ok = await case_.setVisibility(
        factCardId: _factId,
        beaconId: _beaconId,
        actorUserId: _userId,
        visibility: BeaconFactCardVisibilityBits.room,
      );

      expect(ok, isTrue);
      expect(facts.lastSetVisibility, BeaconFactCardVisibilityBits.room);
    });
  });

  group('BeaconFactCardCase.list visibility', () {
    test('admitted user sees public and room facts', () async {
      grantAdmittedAccess();
      facts.rows = [
        testFact(
          id: 'Fpub',
          visibility: BeaconFactCardVisibilityBits.public,
          factText: 'public',
        ),
        testFact(
          id: 'Froom',
          visibility: BeaconFactCardVisibilityBits.room,
          factText: 'room-only',
        ),
      ];

      final rows = await case_.list(beaconId: _beaconId, userId: _userId);

      expect(rows.map((e) => e['id']), ['Fpub', 'Froom']);
      expect(rows.map((e) => e['factText']), ['public', 'room-only']);
    });

    test('non-admitted user sees only public facts', () async {
      denyRoomAccess();
      facts.rows = [
        testFact(
          id: 'Fpub',
          visibility: BeaconFactCardVisibilityBits.public,
          factText: 'public',
        ),
        testFact(
          id: 'Froom',
          visibility: BeaconFactCardVisibilityBits.room,
          factText: 'hidden',
        ),
      ];

      final rows = await case_.list(beaconId: _beaconId, userId: _userId);

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'Fpub');
    });

    test('author without participant row sees room facts', () async {
      room
        ..isAuthor = true
        ..participant = null;
      facts.rows = [
        testFact(
          id: 'Froom',
          visibility: BeaconFactCardVisibilityBits.room,
        ),
      ];

      final rows = await case_.list(beaconId: _beaconId, userId: _userId);

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'Froom');
    });

    test('fetches attachments only for visible facts with source messages',
        () async {
      denyRoomAccess();
      facts.rows = [
        testFact(
          id: 'Fpub',
          visibility: BeaconFactCardVisibilityBits.public,
          sourceMessageId: 'Rpub',
        ),
        testFact(
          id: 'Froom',
          visibility: BeaconFactCardVisibilityBits.room,
          sourceMessageId: 'Rroom',
        ),
      ];
      room.attachmentsByMessageId = {
        'Rpub': '[{"id":"A1"}]',
        'Rroom': '[{"id":"A2"}]',
      };

      final rows = await case_.list(beaconId: _beaconId, userId: _userId);

      expect(rows, hasLength(1));
      expect(rows.single['attachmentsJson'], '[{"id":"A1"}]');
    });

    test('enriches pinnedByTitle from room user titles', () async {
      grantAdmittedAccess();
      facts.rows = [
        testFact(
          id: 'F1',
          pinnedBy: _otherUserId,
        ),
      ];
      room.titlesByUserId = {_otherUserId: 'Helper Name'};

      final rows = await case_.list(beaconId: _beaconId, userId: _userId);

      expect(rows.single['pinnedByTitle'], 'Helper Name');
      expect(rows.single['pinnedBy'], _otherUserId);
    });

    test('list does not require room access for public-only rows', () async {
      denyRoomAccess();
      facts.rows = [
        testFact(
          id: 'Fpub',
          visibility: BeaconFactCardVisibilityBits.public,
        ),
      ];

      final rows = await case_.list(beaconId: _beaconId, userId: _userId);

      expect(rows, hasLength(1));
    });
  });
}
