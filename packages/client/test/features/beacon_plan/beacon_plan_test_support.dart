import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_plan/data/repository/beacon_plan_repository.dart';
import 'package:tentura/features/beacon_plan/domain/use_case/beacon_plan_case.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';

/// In-memory [BeaconPlanRepository] for cubit / widget tests.
class FakeBeaconPlanRepository implements BeaconPlanRepository {
  FakeBeaconPlanRepository(this.plan);

  BeaconPlan plan;

  final changesController = StreamController<String>.broadcast();

  final setDoneCalls = <(String, bool)>[];
  final ackCalls = <int>[];
  final saveCalls = <(int, PlanSnapshot, String)>[];
  final cantMakeCalls = <(String, PlanCantMakeOption, String?)>[];
  final cantMakeExcerpts = <String?>[];
  final restoreCalls = <(int, int)>[];
  int fetchCount = 0;

  BeaconPlanException? setDoneError;

  /// Errors thrown by the next saves, in order.
  final saveErrors = <BeaconPlanException>[];
  final revisionsBySeq = <int, PlanSnapshot>{};
  PlanRevisionPage page = const PlanRevisionPage();

  @override
  Stream<String> get changes => changesController.stream;

  @override
  Future<void> dispose() => changesController.close();

  @override
  Future<BeaconPlan> fetch(String beaconId) async {
    fetchCount++;
    return plan;
  }

  @override
  Future<PlanRevisionPage> revisions(String beaconId, {int? beforeSeq}) async =>
      page;

  @override
  Future<PlanRevisionSnapshot> revision(String beaconId, int seq) async =>
      PlanRevisionSnapshot(
        seq: seq,
        kind: PlanRevisionKind.edited,
        snapshot: revisionsBySeq[seq] ?? PlanSnapshot.empty,
      );

  @override
  Future<PlanSaveOutcome> save({
    required String beaconId,
    required int baseRevisionSeq,
    required PlanSnapshot steps,
    String comment = '',
  }) async {
    saveCalls.add((baseRevisionSeq, steps, comment));
    if (saveErrors.isNotEmpty) throw saveErrors.removeAt(0);
    return PlanSaveOutcome(
      kind: PlanSaveOutcomeKind.applied,
      revisionSeq: baseRevisionSeq + 1,
    );
  }

  @override
  Future<PlanSaveOutcome> restore({
    required String beaconId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) async {
    restoreCalls.add((fromSeq, baseRevisionSeq));
    return PlanSaveOutcome(
      kind: PlanSaveOutcomeKind.applied,
      revisionSeq: baseRevisionSeq + 1,
    );
  }

  @override
  Future<void> setDone({required String stepId, required bool done}) async {
    setDoneCalls.add((stepId, done));
    final error = setDoneError;
    if (error != null) throw error;
    plan = plan.withStepDone(
      stepId,
      done: done,
      actorId: 'ME',
      now: DateTime.utc(2026, 10, 12, 12),
    );
  }

  @override
  Future<void> ack({required String beaconId, required int uptoSeq}) async =>
      ackCalls.add(uptoSeq);

  @override
  Future<PlanSaveOutcome> cantMake({
    required String stepId,
    required PlanCantMakeOption option,
    required int baseRevisionSeq,
    DateTime? newStartAt,
    DateTime? newEndAt,
    String? toUserId,
    String? excerpt,
  }) async {
    cantMakeCalls.add((stepId, option, toUserId));
    cantMakeExcerpts.add(excerpt);
    return PlanSaveOutcome(
      kind: PlanSaveOutcomeKind.applied,
      revisionSeq: baseRevisionSeq + 1,
    );
  }
}

BeaconPlanCase planCaseFor(FakeBeaconPlanRepository repo) =>
    BeaconPlanCase(repo, env: const Env(), logger: Logger('plan-test'));

/// `beaconPlan` as the server's `BeaconPlanCase.view` writes it.
String planJson({
  Map<String, Object?>? viewerPending,
  bool editable = true,
}) => jsonEncode({
  'beaconId': 'B1',
  'revisionSeq': 4,
  'changeSeq': 9,
  'lastEditedById': 'U2',
  'lastEditedAt': '2026-10-12T07:10:00.000Z',
  'copiedFromBeaconId': null,
  'copiedFromTitle': null,
  'editable': editable,
  'tickable': true,
  'steps': [
    {
      'id': 'PS000000000001',
      'index': 1,
      'title': 'Buy screws',
      'description': '',
      'assigneeId': 'U2',
      'startAt': '2026-10-12T08:30:00.000Z',
      'endAt': null,
      'doneAt': '2026-10-12T08:40:00.000Z',
      'doneById': 'U2',
      'createdSeq': 1,
      'contentSeq': 1,
      'ackSeq': 1,
      'assigneeAckPending': false,
    },
    {
      'id': 'PS000000000002',
      'index': 2,
      'title': 'Bring boards',
      'description': 'to the school gate',
      'assigneeId': 'ME',
      'startAt': '2026-10-12T10:00:00.000Z',
      'endAt': '2026-10-12T10:30:00.000Z',
      'doneAt': null,
      'doneById': null,
      'createdSeq': 1,
      'contentSeq': 3,
      'ackSeq': 3,
      'assigneeAckPending': true,
    },
    {
      'id': 'PS000000000003',
      'index': 3,
      'title': 'Build frame',
      'description': '',
      'assigneeId': 'ME',
      'startAt': '2026-10-12T11:30:00.000Z',
      'endAt': null,
      'doneAt': null,
      'doneById': null,
      'createdSeq': 2,
      'contentSeq': 2,
      'ackSeq': 2,
      'assigneeAckPending': false,
    },
    {
      'id': 'PS000000000004',
      'index': 4,
      'title': 'Return the cart',
      'description': '',
      'assigneeId': null,
      'startAt': null,
      'endAt': null,
      'doneAt': null,
      'doneById': null,
      'createdSeq': 4,
      'contentSeq': 4,
      'ackSeq': 4,
      'assigneeAckPending': false,
    },
  ],
  'members': [
    {
      'userId': 'ME',
      'pendingFromSeq': 3,
      'ackedSeq': 2,
      'ackedAt': '2026-10-12T06:00:00.000Z',
    },
  ],
  'viewerPending': viewerPending,
  'names': {'U2': 'Olga', 'ME': 'Ivan'},
  'unknownKey': 'ignored',
});
