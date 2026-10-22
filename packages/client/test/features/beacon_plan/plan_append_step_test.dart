// `BeaconPlanCase.appendStep` (#479): the plan step offered after a «Who'll
// take it?» pick goes through the ordinary whole-plan save. Against a fake
// that saves like the server (head + revisions, three-way merge by step,
// 1336 when the base is unusable):
//  - a Request without a plan gets one;
//  - two appends from the same base both land (simultaneous appends);
//  - someone else's edit meanwhile is kept (merge), and a stale base is
//    retried on a fresh read with the same step id (conflicting edit);
//  - a retry after an uncertain answer (the save landed, the reply was lost)
//    adds nothing (stable step id);
//  - other errors (assignee left) propagate without a retry.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';
import 'package:tentura/features/beacon_plan/domain/use_case/beacon_plan_case.dart';

import 'beacon_plan_test_support.dart';

/// Saves like `BeaconPlanCase.save` on the server: CAS on the head with a
/// three-way merge from the base revision.
class _ServerLikePlanRepository extends FakeBeaconPlanRepository {
  _ServerLikePlanRepository() : super(BeaconPlan.fromJson(_view(0, [])));

  final history = <int, PlanSnapshot>{0: PlanSnapshot.empty};
  int head = 0;

  /// Runs inside the next save, before it reads the head (someone else's
  /// write landing meanwhile).
  Future<void> Function()? beforeNextSave;

  /// Bases the server no longer has (forces 1336).
  final forgottenBases = <int>{};

  /// The next save commits, then its reply is lost.
  bool loseNextReply = false;

  PlanSnapshot get current => history[head]!;

  static Map<String, Object?> _view(int seq, List<PlanStepSnapshot> steps) => {
    'beaconId': 'B1',
    'revisionSeq': seq,
    'editable': true,
    'tickable': true,
    'steps': [
      for (final (i, s) in steps.indexed) {...s.toJson(), 'index': i + 1},
    ],
  };

  @override
  Future<BeaconPlan> fetch(String beaconId) async {
    fetchCount++;
    return BeaconPlan.fromJson(
      jsonDecode(jsonEncode(_view(head, current.steps)))
          as Map<String, Object?>,
    );
  }

  /// Someone else's direct write.
  void commit(PlanSnapshot snapshot) {
    head++;
    history[head] = snapshot;
  }

  @override
  Future<PlanSaveOutcome> save({
    required String beaconId,
    required int baseRevisionSeq,
    required PlanSnapshot steps,
    String comment = '',
  }) async {
    saveCalls.add((baseRevisionSeq, steps, comment));
    final hook = beforeNextSave;
    beforeNextSave = null;
    if (hook != null) await hook();
    if (saveErrors.isNotEmpty) throw saveErrors.removeAt(0);
    var merged = steps;
    if (head != baseRevisionSeq) {
      final base = history[baseRevisionSeq];
      if (base == null || forgottenBases.contains(baseRevisionSeq)) {
        throw PlanEditConflictException(currentSeq: head);
      }
      switch (PlanMerge.threeWay(base, current, steps)) {
        case PlanMergeConflict(:final stepIds):
          throw PlanEditConflictException(
            currentSeq: head,
            conflictStepIds: stepIds,
          );
        case PlanMergeMerged(:final snapshot):
          merged = snapshot;
      }
    }
    if (merged.sameAs(current)) {
      return PlanSaveOutcome(kind: PlanSaveOutcomeKind.noop, revisionSeq: head);
    }
    commit(merged);
    if (loseNextReply) {
      loseNextReply = false;
      throw Exception('connection reset');
    }
    return PlanSaveOutcome(
      kind: PlanSaveOutcomeKind.applied,
      revisionSeq: head,
    );
  }
}

const _bring = PlanStepSnapshot(
  id: 'PS00000000b001',
  title: 'Bring straps',
  assigneeId: 'U-helper',
);

const _other = PlanStepSnapshot(
  id: 'PS00000000b002',
  title: 'Book the van',
  assigneeId: 'U-other',
);

const _existing = PlanStepSnapshot(id: 'PS00000000e001', title: 'Load boxes');

void main() {
  late _ServerLikePlanRepository repo;
  late BeaconPlanCase planCase;

  setUp(() {
    repo = _ServerLikePlanRepository();
    planCase = planCaseFor(repo);
  });

  test('creates the plan when the Request has none', () async {
    final added = await planCase.appendStep(beaconId: 'B1', step: _bring);

    expect(added, isTrue);
    expect(repo.saveCalls.single.$1, 0, reason: 'saved on base 0');
    expect(repo.current.steps, [_bring]);
  });

  test('appends after the existing steps', () async {
    repo.commit(const PlanSnapshot([_existing]));

    await planCase.appendStep(beaconId: 'B1', step: _bring);

    expect(repo.current.ids, [_existing.id, _bring.id]);
  });

  test('two appends from the same base both land', () async {
    repo.commit(const PlanSnapshot([_existing]));
    // The other append reads the same head, then lands first.
    repo.beforeNextSave = () async {
      final other = _ServerLikePlanRepository()
        ..history.addAll(repo.history)
        ..head = repo.head;
      await planCaseFor(other).appendStep(beaconId: 'B1', step: _other);
      repo.commit(other.current);
    };

    await planCase.appendStep(beaconId: 'B1', step: _bring);

    expect(repo.current.ids.toSet(), {_existing.id, _other.id, _bring.id});
    expect(repo.saveCalls, hasLength(1), reason: 'merged, not retried');
  });

  test("keeps someone else's edit made meanwhile", () async {
    repo.commit(const PlanSnapshot([_existing]));
    repo.beforeNextSave = () async => repo.commit(
      PlanSnapshot([_existing.copyWith(title: 'Load boxes at 9')]),
    );

    await planCase.appendStep(beaconId: 'B1', step: _bring);

    expect(repo.current[_existing.id]!.title, 'Load boxes at 9');
    expect(repo.current[_bring.id], _bring);
  });

  test(
    'a stale base is retried on a fresh read with the same step id',
    () async {
      repo.commit(const PlanSnapshot([_existing]));
      repo.beforeNextSave = () async {
        repo.commit(
          PlanSnapshot([_existing.copyWith(title: 'Load boxes at 9')]),
        );
        repo.forgottenBases.add(1);
      };

      final added = await planCase.appendStep(beaconId: 'B1', step: _bring);

      expect(added, isTrue);
      expect(repo.saveCalls, hasLength(2));
      expect(repo.saveCalls.first.$1, 1);
      expect(repo.saveCalls.last.$1, 2, reason: 'fresh head');
      expect(repo.saveCalls.last.$2[_bring.id], _bring);
      expect(repo.current.ids, [_existing.id, _bring.id]);
      expect(repo.current[_existing.id]!.title, 'Load boxes at 9');
    },
  );

  test('gives up after the attempts and rethrows the conflict', () async {
    repo.saveErrors.addAll([
      const PlanEditConflictException(currentSeq: 0),
      const PlanEditConflictException(currentSeq: 0),
      const PlanEditConflictException(currentSeq: 0),
    ]);

    await expectLater(
      planCase.appendStep(beaconId: 'B1', step: _bring),
      throwsA(isA<PlanEditConflictException>()),
    );
    expect(repo.saveCalls, hasLength(3));
    expect(repo.current.isEmpty, isTrue);
  });

  test('a retry after a lost reply adds nothing', () async {
    repo.loseNextReply = true;

    await expectLater(
      planCase.appendStep(beaconId: 'B1', step: _bring),
      throwsA(isA<Exception>()),
    );
    expect(repo.current.steps, [_bring], reason: 'the first save landed');

    final again = await planCase.appendStep(beaconId: 'B1', step: _bring);

    expect(again, isFalse, reason: 'already in the plan');
    expect(repo.saveCalls, hasLength(1), reason: 'no second write');
    expect(repo.current.steps, [_bring]);
  });

  test('an assignee who left is reported, not retried', () async {
    repo.saveErrors.add(const PlanAssigneeNotAdmittedException());

    await expectLater(
      planCase.appendStep(beaconId: 'B1', step: _bring),
      throwsA(isA<PlanAssigneeNotAdmittedException>()),
    );
    expect(repo.saveCalls, hasLength(1));
    expect(repo.current.isEmpty, isTrue);
  });
}
