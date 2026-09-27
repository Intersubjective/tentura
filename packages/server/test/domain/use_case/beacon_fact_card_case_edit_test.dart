import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';

/// tentura-617.11 (issue #181 plan §14.5, §8.3, §8.11): `correct` / `restore`
/// validate the text first, run the fused `loadRoomAccess` preflight, pass
/// the env rate-limit knobs to the port and map every [FactEditOutcome] to
/// the new seq or to an exception.
const _beaconId = 'Baaaaaaaaaaaa';
const _userId = 'Uaaaaaaaaaaaa';
const _factId = 'Faaaaaaaaaaaa';

typedef _EditCall = ({
  String factCardId,
  String beaconId,
  String actorUserId,
  String newText,
  int baseRevisionSeq,
  Duration rateWindow,
  int rateMax,
  Duration quietWindow,
  String? attachmentsJson,
});

typedef _RestoreCall = ({
  String factCardId,
  String beaconId,
  String actorUserId,
  int fromSeq,
  int baseRevisionSeq,
  Duration rateWindow,
  int rateMax,
  Duration quietWindow,
});

class _MockFacts extends Fake implements BeaconFactCardRepositoryPort {
  BeaconFactRoomAccess access = BeaconFactRoomAccess(
    beaconStatus: BeaconStatus.open.smallintValue,
    canUseRoom: true,
    canReadContent: true,
    exists: true,
  );

  FactEditOutcome outcome = const FactEditApplied(newSeq: 2);

  int loadRoomAccessCalls = 0;
  int listForBeaconCalls = 0;
  final editCalls = <_EditCall>[];
  final restoreCalls = <_RestoreCall>[];

  int get portWriteCalls => editCalls.length + restoreCalls.length;

  @override
  Future<BeaconFactRoomAccess> loadRoomAccess({
    required String beaconId,
    required String userId,
  }) async {
    loadRoomAccessCalls++;
    return access;
  }

  @override
  Future<List<BeaconFactCardEntity>> listForBeacon({
    required String beaconId,
    required bool includeRoomOnly,
  }) async {
    listForBeaconCalls++;
    return const [];
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
    editCalls.add((
      factCardId: factCardId,
      beaconId: beaconId,
      actorUserId: actorUserId,
      newText: newText,
      baseRevisionSeq: baseRevisionSeq,
      rateWindow: rateWindow,
      rateMax: rateMax,
      quietWindow: quietWindow,
      attachmentsJson: attachmentsJson,
    ));
    return outcome;
  }

  @override
  Future<FactEditOutcome> restoreRevision({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int fromSeq,
    required int baseRevisionSeq,
    required Duration rateWindow,
    required int rateMax,
    required Duration quietWindow,
  }) async {
    restoreCalls.add((
      factCardId: factCardId,
      beaconId: beaconId,
      actorUserId: actorUserId,
      fromSeq: fromSeq,
      baseRevisionSeq: baseRevisionSeq,
      rateWindow: rateWindow,
      rateMax: rateMax,
      quietWindow: quietWindow,
    ));
    return outcome;
  }
}

/// Access goes through the fused `loadRoomAccess`; the legacy per-check
/// room lookups must not be used.
class _UnusedRoom extends Fake implements BeaconRoomRepositoryPort {}

class _UnusedImage extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

/// Lifecycle comes from `loadRoomAccess.beaconStatus`, not a second read.
class _UnusedHierarchy extends Fake implements BeaconHierarchyRepositoryPort {}

void main() {
  late _MockFacts facts;

  BeaconFactCardCase buildCase(Env env) => BeaconFactCardCase(
    facts,
    _UnusedRoom(),
    _UnusedImage(),
    _UnusedTasks(),
    _UnusedHierarchy(),
    FakeBeaconAccessGuard(),
    env: env,
    logger: Logger('BeaconFactCardCaseEditTest'),
  );

  late BeaconFactCardCase case_;

  setUp(() {
    facts = _MockFacts();
    case_ = buildCase(Env(environment: Environment.test));
  });

  Future<int> correct({
    String newText = 'New text',
    int baseSeq = 1,
    String? attachmentsJson,
  }) =>
      case_.correct(
        factCardId: _factId,
        beaconId: _beaconId,
        actorUserId: _userId,
        newText: newText,
        baseRevisionSeq: baseSeq,
        attachmentsJson: attachmentsJson,
      );

  Future<int> restore({int fromSeq = 1, int baseSeq = 2}) => case_.restore(
    factCardId: _factId,
    beaconId: _beaconId,
    actorUserId: _userId,
    fromSeq: fromSeq,
    baseRevisionSeq: baseSeq,
  );

  group('BeaconFactCardCase.correct — §14.5 outcome map', () {
    test('FactEditApplied returns the new seq', () async {
      facts.outcome = const FactEditApplied(newSeq: 7);
      expect(await correct(baseSeq: 6), 7);
      expect(facts.editCalls, hasLength(1));
    });

    test('FactEditNoOp returns the current seq', () async {
      facts.outcome = const FactEditNoOp(currentSeq: 4);
      expect(await correct(baseSeq: 4), 4);
    });

    test('FactEditNotFound → IdNotFoundException', () async {
      facts.outcome = const FactEditNotFound();
      await expectLater(correct(), throwsA(isA<IdNotFoundException>()));
    });

    test('FactEditRemoved → BeaconFactCardRemovedException', () async {
      facts.outcome = const FactEditRemoved();
      await expectLater(
        correct(),
        throwsA(isA<BeaconFactCardRemovedException>()),
      );
    });

    test('FactEditRateLimited → BeaconFactCardRateLimitedException', () async {
      facts.outcome = const FactEditRateLimited();
      await expectLater(
        correct(),
        throwsA(isA<BeaconFactCardRateLimitedException>()),
      );
    });

    test('FactEditConflict → BeaconFactCardEditConflictException carrying '
        'currentSeq', () async {
      facts.outcome = const FactEditConflict(currentSeq: 9);
      await expectLater(
        correct(baseSeq: 3),
        throwsA(
          isA<BeaconFactCardEditConflictException>().having(
            (e) => e.currentSeq,
            'currentSeq',
            9,
          ),
        ),
      );
    });

  });

  group('BeaconFactCardCase.restore — §14.5 outcome map', () {
    test('FactEditApplied returns the new seq', () async {
      facts.outcome = const FactEditApplied(newSeq: 3);
      expect(await restore(), 3);
      expect(facts.restoreCalls, hasLength(1));
      expect(facts.editCalls, isEmpty);
    });

    test('FactEditNoOp returns the current seq', () async {
      facts.outcome = const FactEditNoOp(currentSeq: 2);
      expect(await restore(), 2);
    });

    test('FactEditNotFound → IdNotFoundException', () async {
      facts.outcome = const FactEditNotFound();
      await expectLater(restore(), throwsA(isA<IdNotFoundException>()));
    });

    test('FactEditRemoved → BeaconFactCardRemovedException', () async {
      facts.outcome = const FactEditRemoved();
      await expectLater(
        restore(),
        throwsA(isA<BeaconFactCardRemovedException>()),
      );
    });

    test('FactEditRateLimited → BeaconFactCardRateLimitedException', () async {
      facts.outcome = const FactEditRateLimited();
      await expectLater(
        restore(),
        throwsA(isA<BeaconFactCardRateLimitedException>()),
      );
    });

    test('FactEditConflict → BeaconFactCardEditConflictException carrying '
        'currentSeq', () async {
      facts.outcome = const FactEditConflict(currentSeq: 5);
      await expectLater(
        restore(),
        throwsA(
          isA<BeaconFactCardEditConflictException>().having(
            (e) => e.currentSeq,
            'currentSeq',
            5,
          ),
        ),
      );
    });

    test('FactRestoreSourceMissing → IdWrongException', () async {
      facts.outcome = const FactRestoreSourceMissing();
      await expectLater(
        restore(fromSeq: 99),
        throwsA(isA<IdWrongException>()),
      );
    });
  });

  group('BeaconFactCardCase.correct — validation and preflight', () {
    for (final blank in ['', '   ', '\n\t ']) {
      test('blank text ${blank.codeUnits} → BeaconCreateException before '
          'any port call', () async {
        await expectLater(
          correct(newText: blank),
          throwsA(isA<BeaconCreateException>()),
        );
        expect(facts.loadRoomAccessCalls, 0);
        expect(facts.portWriteCalls, 0);
      });
    }

    test('blank text is rejected even without room access', () async {
      facts.access = facts.access.copyWith(canUseRoom: false);
      await expectLater(
        correct(newText: '  '),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(facts.loadRoomAccessCalls, 0);
    });

    test(
      'empty text with attachmentsJson recomputes fact_text from filenames',
      () async {
        facts.outcome = const FactEditApplied(newSeq: 2);
        expect(
          await correct(
            newText: '',
            attachmentsJson:
                '[{"id":"A1","fileName":"gate.jpg"},'
                '{"id":"A2","fileName":"door.png"}]',
          ),
          2,
        );
        expect(facts.editCalls, hasLength(1));
        expect(facts.editCalls.single.newText, 'gate.jpg, door.png');
        expect(
          facts.editCalls.single.attachmentsJson,
          contains('"id":"A1"'),
        );
      },
    );

    test('attachmentsJson is forwarded on text+attach edits', () async {
      facts.outcome = const FactEditApplied(newSeq: 3);
      const json = '[{"id":"Ax"}]';
      expect(await correct(newText: 'Caption', attachmentsJson: json), 3);
      expect(facts.editCalls.single.attachmentsJson, json);
    });

    test('!canUseRoom → UnauthorizedException(Room access required)', () async {
      facts.access = facts.access.copyWith(canUseRoom: false);
      await expectLater(
        correct(),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Room access required',
          ),
        ),
      );
      expect(facts.loadRoomAccessCalls, 1);
      expect(facts.portWriteCalls, 0);
    });

    test('unknown beacon → UnauthorizedException(Room access required)',
        () async {
      facts.access = facts.access.copyWith(exists: false, canUseRoom: false);
      await expectLater(
        correct(),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Room access required',
          ),
        ),
      );
      expect(facts.portWriteCalls, 0);
    });

    for (final status in BeaconStatus.values.where(
      (s) => !s.allowsDiscussionWrites,
    )) {
      test('closed lifecycle $status → BeaconCreateException', () async {
        facts.access = facts.access.copyWith(
          beaconStatus: status.smallintValue,
        );
        await expectLater(
          correct(),
          throwsA(
            isA<BeaconCreateException>().having(
              (e) => e.description,
              'description',
              'Discussion is read-only for this request',
            ),
          ),
        );
        expect(facts.portWriteCalls, 0);
      });
    }

    test('does not infer the base seq from listForBeacon', () async {
      await correct(baseSeq: 3);
      expect(facts.listForBeaconCalls, 0);
      expect(facts.editCalls.single.baseRevisionSeq, 3);
    });

    test('forwards ids and the trimmed text', () async {
      await correct(newText: '  Trimmed  ');
      final call = facts.editCalls.single;
      expect(call.factCardId, _factId);
      expect(call.beaconId, _beaconId);
      expect(call.actorUserId, _userId);
      expect(call.newText, 'Trimmed');
    });
  });

  group('BeaconFactCardCase.restore — preflight', () {
    test('!canUseRoom → UnauthorizedException(Room access required)', () async {
      facts.access = facts.access.copyWith(canUseRoom: false);
      await expectLater(
        restore(),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Room access required',
          ),
        ),
      );
      expect(facts.portWriteCalls, 0);
    });

    for (final status in BeaconStatus.values.where(
      (s) => !s.allowsDiscussionWrites,
    )) {
      test('closed lifecycle $status → BeaconCreateException', () async {
        facts.access = facts.access.copyWith(
          beaconStatus: status.smallintValue,
        );
        await expectLater(
          restore(),
          throwsA(
            isA<BeaconCreateException>().having(
              (e) => e.description,
              'description',
              'Discussion is read-only for this request',
            ),
          ),
        );
        expect(facts.portWriteCalls, 0);
      });
    }

    test('unknown beacon → UnauthorizedException(Room access required)',
        () async {
      facts.access = facts.access.copyWith(exists: false, canUseRoom: false);
      await expectLater(
        restore(),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Room access required',
          ),
        ),
      );
      expect(facts.portWriteCalls, 0);
    });

    test('does not infer the base seq from listForBeacon', () async {
      await restore(baseSeq: 3);
      expect(facts.listForBeaconCalls, 0);
      expect(facts.restoreCalls.single.baseRevisionSeq, 3);
    });

    test('forwards fromSeq and baseRevisionSeq', () async {
      await restore(baseSeq: 4);
      final call = facts.restoreCalls.single;
      expect(call.factCardId, _factId);
      expect(call.beaconId, _beaconId);
      expect(call.actorUserId, _userId);
      expect(call.fromSeq, 1);
      expect(call.baseRevisionSeq, 4);
    });
  });

  group('BeaconFactCardCase edit/restore — §8.3 rate-limit knobs', () {
    test('Env defaults: FACT_EDIT_RATE_WINDOW 60 s, FACT_EDIT_RATE_MAX 20', () {
      final env = Env(environment: Environment.test);
      expect(env.factEditRateWindow, const Duration(seconds: 60));
      expect(env.factEditRateMax, 20);
    });

    test('correct passes rateWindow 60 s, rateMax 20, quietWindow 5 min by '
        'default', () async {
      await correct();
      final call = facts.editCalls.single;
      expect(call.rateWindow, const Duration(seconds: 60));
      expect(call.rateMax, 20);
      expect(call.quietWindow, const Duration(minutes: 5));
      expect(call.quietWindow, kFactEditQuietWindow);
    });

    test('restore passes rateWindow 60 s, rateMax 20, quietWindow 5 min by '
        'default', () async {
      await restore();
      final call = facts.restoreCalls.single;
      expect(call.rateWindow, const Duration(seconds: 60));
      expect(call.rateMax, 20);
      expect(call.quietWindow, const Duration(minutes: 5));
    });

    test('configured env knobs reach the port', () async {
      case_ = buildCase(
        Env(
          environment: Environment.test,
          factEditRateWindow: const Duration(seconds: 15),
          factEditRateMax: 3,
        ),
      );
      await correct();
      await restore();
      expect(facts.editCalls.single.rateWindow, const Duration(seconds: 15));
      expect(facts.editCalls.single.rateMax, 3);
      expect(
        facts.restoreCalls.single.rateWindow,
        const Duration(seconds: 15),
      );
      expect(facts.restoreCalls.single.rateMax, 3);
    });
  });
}
