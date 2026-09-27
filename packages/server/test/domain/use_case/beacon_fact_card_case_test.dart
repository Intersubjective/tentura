import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/fake_beacon_access_guard.dart';

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
  String pinnedByTitle = '',
}) =>
    BeaconFactCardEntity(
      id: id,
      beaconId: _beaconId,
      factText: factText,
      visibility: visibility,
      pinnedBy: pinnedBy,
      sourceMessageId: sourceMessageId,
      createdAt: _now,
      pinnedByTitle: pinnedByTitle,
    );

class _StubFacts extends Fake implements BeaconFactCardRepositoryPort {
  _StubFacts(this.room, this.guard, this.hierarchy);

  final _StubRoom room;
  final FakeBeaconAccessGuard guard;
  final _StubHierarchy hierarchy;
  List<BeaconFactCardEntity> rows = const [];
  BeaconFactCardEntity? dupBySource;
  String? lastPinnedText;
  int? lastPinnedVisibility;
  String? lastPinnedBy;
  String? lastPinnedSourceMessageId;
  String? lastCorrectedText;
  String? lastCorrectedAttachmentsJson;
  String? lastRemovedFactId;
  int? lastSetVisibility;
  Map<String, String> headAttachmentsByFactId = const {};

  @override
  Future<BeaconFactRoomAccess> loadRoomAccess({
    required String beaconId,
    required String userId,
  }) async =>
      BeaconFactRoomAccess(
        beaconStatus: hierarchy.status?.smallintValue ?? 0,
        canUseRoom: room.isAuthor ||
            room.isSteward ||
            room.participant?.roomAccess == RoomAccessBits.admitted,
        canReadContent: guard.contentAllowed,
        exists: true,
      );

  @override
  Future<List<BeaconFactCardEntity>> listForBeacon({
    required String beaconId,
    required bool includeRoomOnly,
  }) async {
    listForBeaconCalls++;
    return [
      for (final e in rows)
        if (includeRoomOnly || e.visibility != BeaconFactCardVisibilityBits.room)
          e,
    ];
  }

  int listForBeaconCalls = 0;

  @override
  Future<BeaconFactCardEntity> pinFact({
    required String beaconId,
    required String factText,
    required int visibility,
    required String pinnedBy,
    String? sourceMessageId,
  }) async {
    final dup = dupBySource;
    if (dup != null) {
      throw BeaconFactCardAlreadyPinnedException(existingFactCardId: dup.id);
    }
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
  Future<FactEditOutcome> editText({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String newText,
    required int baseRevisionSeq,
    required Duration rateWindow,
    required int rateMax,
    required Duration quietWindow,
    String? attachmentsJson,
  }) async {
    lastCorrectedText = newText;
    lastCorrectedAttachmentsJson = attachmentsJson;
    return FactEditApplied(newSeq: baseRevisionSeq + 1);
  }

  @override
  Future<Map<String, String>> headAttachmentsJsonByFactIds(
    Iterable<String> factCardIds,
  ) async => {
        for (final id in factCardIds)
          if (headAttachmentsByFactId.containsKey(id))
            id: headAttachmentsByFactId[id]!,
      };

  @override
  Future<String> attachmentsJsonForRevision({
    required String factCardId,
    required int seq,
  }) async =>
      headAttachmentsByFactId[factCardId] ?? '[]';

  @override
  Future<bool> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) async {
    lastRemovedFactId = factCardId;
    return true;
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

class _UnusedImage extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

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


class _StubHierarchy extends Fake implements BeaconHierarchyRepositoryPort {
  BeaconStatus? status = BeaconStatus.open;

  @override
  Future<BeaconStatus?> loadBeaconStatus(String beaconId) async => status;
}

void main() {
  late _StubFacts facts;
  late _StubRoom room;
  late _StubHierarchy hierarchy;
  late FakeBeaconAccessGuard guard;
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
    room = _StubRoom();
    guard = FakeBeaconAccessGuard();
    hierarchy = _StubHierarchy();
    facts = _StubFacts(room, guard, hierarchy);
    case_ = BeaconFactCardCase(
      facts,
      room,
      _UnusedImage(),
      _UnusedTasks(),
      hierarchy,
      guard,
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
          baseRevisionSeq: 1,
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
      final seq = await case_.correct(
        factCardId: _factId,
        beaconId: _beaconId,
        actorUserId: _userId,
        newText: 'updated',
        baseRevisionSeq: 1,
      );

      expect(seq, 2);
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

    test('stranger without content read is refused before facts load',
        () async {
      denyRoomAccess();
      guard.contentAllowed = false;
      facts.rows = [
        testFact(
          id: 'Fpub',
          visibility: BeaconFactCardVisibilityBits.public,
        ),
      ];

      await expectLater(
        case_.list(beaconId: _beaconId, userId: _userId),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Viewer cannot read request content',
          ),
        ),
      );
      expect(facts.listForBeaconCalls, 0);
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

    test('fetches head revision attachments for listed facts', () async {
      denyRoomAccess();
      facts
        ..rows = [
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
        ]
        ..headAttachmentsByFactId = {
          'Fpub': '[{"id":"A1"}]',
          'Froom': '[{"id":"A2"}]',
        };

      final rows = await case_.list(beaconId: _beaconId, userId: _userId);

      expect(rows, hasLength(1));
      expect(rows.single['attachmentsJson'], '[{"id":"A1"}]');
    });

    test('maps the joined pinnedByTitle from the list row', () async {
      grantAdmittedAccess();
      facts.rows = [
        testFact(
          id: 'F1',
          pinnedBy: _otherUserId,
          pinnedByTitle: 'Helper Name',
        ),
      ];

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

  group('BeaconFactCardCase lifecycle write policy', () {
    test('pin rejects closed request', () async {
      hierarchy.status = BeaconStatus.closed;

      await expectLater(
        case_.pin(
          beaconId: _beaconId,
          factText: 'hello',
          visibility: BeaconFactCardVisibilityBits.public,
          userId: _userId,
        ),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'Discussion is read-only for this request',
          ),
        ),
      );
      expect(facts.lastPinnedText, isNull);
    });

    test('correct rejects cancelled request', () async {
      hierarchy.status = BeaconStatus.cancelled;

      await expectLater(
        case_.correct(
          factCardId: _factId,
          beaconId: _beaconId,
          actorUserId: _userId,
          newText: 'x',
          baseRevisionSeq: 1,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('pin allows wrapping-up request', () async {
      hierarchy.status = BeaconStatus.reviewOpen;

      final r = await case_.pin(
        beaconId: _beaconId,
        factText: 'still open',
        visibility: BeaconFactCardVisibilityBits.public,
        userId: _userId,
      );

      expect(r['id'], _factId);
      expect(facts.lastPinnedText, 'still open');
    });
  });
}
