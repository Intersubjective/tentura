import 'package:test/test.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';

/// tentura-617.4 — plan §14.2 / §14.5: sealed repository outcomes that the
/// use case maps to return values or exceptions.
String describeEdit(FactEditOutcome o) => switch (o) {
  FactEditApplied(:final newSeq) => 'applied:$newSeq',
  FactEditNoOp(:final currentSeq) => 'noop:$currentSeq',
  FactEditNotFound() => 'notFound',
  FactEditRemoved() => 'removed',
  FactEditRateLimited() => 'rateLimited',
  FactEditConflict(:final currentSeq) => 'conflict:$currentSeq',
  FactRestoreSourceMissing() => 'restoreSourceMissing',
};

String describePin(FactPinOutcome o) => switch (o) {
  FactPinned(:final entity) => 'pinned:${entity.id}',
  FactAlreadyPinned(:final existingFactCardId) => 'already:$existingFactCardId',
};

void main() {
  group('FactEditOutcome', () {
    test('every variant is exhaustively matchable with its payload', () {
      expect(describeEdit(const FactEditApplied(newSeq: 4)), 'applied:4');
      expect(describeEdit(const FactEditNoOp(currentSeq: 3)), 'noop:3');
      expect(describeEdit(const FactEditNotFound()), 'notFound');
      expect(describeEdit(const FactEditRemoved()), 'removed');
      expect(describeEdit(const FactEditRateLimited()), 'rateLimited');
      expect(describeEdit(const FactEditConflict(currentSeq: 7)), 'conflict:7');
      expect(
        describeEdit(const FactRestoreSourceMissing()),
        'restoreSourceMissing',
      );
    });
  });

  group('FactPinOutcome', () {
    test('pinned carries the entity, already-pinned the existing id', () {
      final entity = BeaconFactCardEntity(
        id: 'Fnew',
        beaconId: 'Bxyz',
        factText: 'fact',
        visibility: 0,
        pinnedBy: 'Uaaa',
        createdAt: DateTime.utc(2026, 9),
      );
      expect(describePin(FactPinned(entity: entity)), 'pinned:Fnew');
      expect(
        describePin(const FactAlreadyPinned(existingFactCardId: 'Fold')),
        'already:Fold',
      );
    });
  });
}
