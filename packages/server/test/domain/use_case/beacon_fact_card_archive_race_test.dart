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
import 'package:tentura_server/domain/use_case/room_write_guard.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';

/// A fact write that passed the preflight but lost a race with closing or
/// archiving: the database refuses it, and the caller must see the room
/// read-only exception rather than the raw database error.

const _beaconId = 'Brequestrace1';
const _factId = 'Ffactrace0001';
const _userId = 'Uuserrace0001';

/// Stands in for the database error a guarded write raises after archiving.
final class _ArchivedWriteError implements Exception {
  const _ArchivedWriteError();

  @override
  String toString() => 'post_archived';
}

/// Writable published Request room; every write fails with [_ArchivedWriteError].
final class _RacingFacts extends Fake implements BeaconFactCardRepositoryPort {
  @override
  Future<BeaconFactRoomAccess> loadRoomAccess({
    required String beaconId,
    required String userId,
  }) async => BeaconFactRoomAccess(
    beaconStatus: BeaconStatus.open.smallintValue,
    canUseRoom: true,
    canReadContent: true,
    exists: true,
    kind: 0,
    isDraft: false,
    isExpiredPost: false,
  );

  @override
  Future<BeaconFactCardEntity> pinFact({
    required String beaconId,
    required String factText,
    required int visibility,
    required String pinnedBy,
    String? sourceMessageId,
  }) async => throw const _ArchivedWriteError();

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
  }) async => throw const _ArchivedWriteError();

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
  }) async => throw const _ArchivedWriteError();

  @override
  Future<void> setVisibility({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int visibility,
  }) async => throw const _ArchivedWriteError();

  @override
  Future<bool> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) async => throw const _ArchivedWriteError();
}

/// Hierarchy repository that classifies [_ArchivedWriteError] as a read-only
/// refusal when [classifiesAsReadOnly].
final class _WriteStateHierarchy extends FakeBeaconHierarchyRepository
    implements BeaconRoomWriteStatePort {
  _WriteStateHierarchy({required this.classifiesAsReadOnly});

  final bool classifiesAsReadOnly;

  @override
  Future<bool> isExpiredPost(String beaconId) async => false;

  @override
  bool isReadOnlyWriteError(Object error) =>
      classifiesAsReadOnly && error is _ArchivedWriteError;
}

final class _UnusedRoom extends Fake implements BeaconRoomRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}

void main() {
  BeaconFactCardCase build(BeaconHierarchyRepositoryPort hierarchy) =>
      BeaconFactCardCase(
        _RacingFacts(),
        _UnusedRoom(),
        _UnusedImages(),
        _UnusedTasks(),
        hierarchy,
        FakeBeaconAccessGuard(),
        env: Env(environment: Environment.test),
        logger: Logger('BeaconFactCardArchiveRaceTest'),
      );

  Map<String, Future<Object?> Function()> writes(BeaconFactCardCase c) => {
    'pin': () => c.pin(
      beaconId: _beaconId,
      factText: 'Fact',
      visibility: BeaconFactCardVisibilityBits.room,
      userId: _userId,
    ),
    'correct': () => c.correct(
      factCardId: _factId,
      beaconId: _beaconId,
      actorUserId: _userId,
      newText: 'Edited',
      baseRevisionSeq: 1,
    ),
    'restore': () => c.restore(
      factCardId: _factId,
      beaconId: _beaconId,
      actorUserId: _userId,
      fromSeq: 1,
      baseRevisionSeq: 2,
    ),
    'setVisibility': () => c.setVisibility(
      factCardId: _factId,
      beaconId: _beaconId,
      actorUserId: _userId,
      visibility: BeaconFactCardVisibilityBits.public,
    ),
    'remove': () => c.remove(
      factCardId: _factId,
      beaconId: _beaconId,
      actorUserId: _userId,
    ),
  };

  final isReadOnly = isA<BeaconCreateException>()
      .having(
        (e) => e.description,
        'description',
        kRoomReadOnlyException.description,
      )
      .having(
        (e) => e.code.codeNumber,
        'code',
        kRoomReadOnlyException.code.codeNumber,
      );

  group('A fact write that loses a race with archiving', () {
    final c = build(_WriteStateHierarchy(classifiesAsReadOnly: true));
    for (final MapEntry(key: op, value: write) in writes(c).entries) {
      test('$op surfaces the room read-only exception', () async {
        await expectLater(write(), throwsA(isReadOnly));
      });
    }
  });

  group('A fact write failing for another reason', () {
    final c = build(_WriteStateHierarchy(classifiesAsReadOnly: false));
    for (final MapEntry(key: op, value: write) in writes(c).entries) {
      test('$op rethrows the original error unchanged', () async {
        await expectLater(write(), throwsA(isA<_ArchivedWriteError>()));
      });
    }
  });
}
