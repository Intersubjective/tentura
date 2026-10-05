import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';

import '../../domain/entity/beacon_plan.dart';
import '../../domain/entity/plan_revision.dart';
import '../gql/_g/beacon_plan_ack.req.gql.dart';
import '../gql/_g/beacon_plan_get.req.gql.dart';
import '../gql/_g/beacon_plan_restore.req.gql.dart';
import '../gql/_g/beacon_plan_revision.req.gql.dart';
import '../gql/_g/beacon_plan_revisions.req.gql.dart';
import '../gql/_g/beacon_plan_save.req.gql.dart';
import '../gql/_g/beacon_plan_step_cant_make.req.gql.dart';
import '../gql/_g/beacon_plan_step_set_done.req.gql.dart';

/// Request plan («либретто», #220) over Tentura V2 GraphQL. Every operation
/// carries one JSON string; this repository turns it into domain entities.
@lazySingleton
class BeaconPlanRepository {
  BeaconPlanRepository(this._remoteApiService, RealtimeSyncPort realtimeSync) {
    _realtimeSub = realtimeSync.entityChanges
        .where((c) => c.kind == RealtimeEntityKind.beaconPlan)
        .map((c) => c.aggregateId)
        .where((id) => id.isNotEmpty)
        .listen(_changes.add);
  }

  static const _label = 'BeaconPlan';

  final RemoteApiService _remoteApiService;

  late final StreamSubscription<String> _realtimeSub;

  final _changes = StreamController<String>.broadcast();

  /// Ids of Requests whose plan changed on the server (realtime
  /// `beacon_plan`); subscribers refetch.
  Stream<String> get changes => _changes.stream;

  @disposeMethod
  Future<void> dispose() async {
    await _realtimeSub.cancel();
    await _changes.close();
  }

  Future<BeaconPlan> fetch(String beaconId) => _remoteApiService
      .request(GBeaconPlanGetReq((b) => b.vars.beaconId = beaconId))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => BeaconPlan.decode(r.dataOrThrow(label: _label).beaconPlan));

  Future<PlanRevisionPage> revisions(String beaconId, {int? beforeSeq}) =>
      _remoteApiService
          .request(
            GBeaconPlanRevisionsReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..beforeSeq = beforeSeq,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => PlanRevisionPage.decode(
              r.dataOrThrow(label: _label).beaconPlanRevisions,
            ),
          );

  Future<PlanRevisionSnapshot> revision(String beaconId, int seq) =>
      _remoteApiService
          .request(
            GBeaconPlanRevisionReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..seq = seq,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => PlanRevisionSnapshot.decode(
              r.dataOrThrow(label: _label).beaconPlanRevision,
            ),
          );

  /// Saves [steps] as the next revision on top of [baseRevisionSeq].
  Future<PlanSaveOutcome> save({
    required String beaconId,
    required int baseRevisionSeq,
    required PlanSnapshot steps,
    String comment = '',
  }) => _remoteApiService
      .request(
        GBeaconPlanSaveReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..baseRevisionSeq = baseRevisionSeq
            ..stepsJson = steps.encode()
            ..comment = comment.trim().isEmpty ? null : comment.trim(),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) =>
            PlanSaveOutcome.decode(r.dataOrThrow(label: _label).beaconPlanSave),
      );

  Future<PlanSaveOutcome> restore({
    required String beaconId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) => _remoteApiService
      .request(
        GBeaconPlanRestoreReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..fromSeq = fromSeq
            ..baseRevisionSeq = baseRevisionSeq,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => PlanSaveOutcome.decode(
          r.dataOrThrow(label: _label).beaconPlanRestore,
        ),
      );

  Future<void> setDone({required String stepId, required bool done}) =>
      _remoteApiService
          .request(
            GBeaconPlanStepSetDoneReq(
              (b) => b.vars
                ..stepId = stepId
                ..done = done,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label));

  Future<void> ack({required String beaconId, required int uptoSeq}) =>
      _remoteApiService
          .request(
            GBeaconPlanAckReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..uptoSeq = uptoSeq,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label));

  Future<PlanSaveOutcome> cantMake({
    required String stepId,
    required PlanCantMakeOption option,
    required int baseRevisionSeq,
    DateTime? newStartAt,
    DateTime? newEndAt,
    String? toUserId,
    String? excerpt,
  }) => _remoteApiService
      .request(
        GBeaconPlanStepCantMakeReq(
          (b) => b.vars
            ..stepId = stepId
            ..option = option.wire
            ..baseRevisionSeq = baseRevisionSeq
            ..newStartAt = formatPlanInstant(newStartAt)
            ..newEndAt = formatPlanInstant(newEndAt)
            ..toUserId = toUserId
            ..excerpt = excerpt,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => PlanSaveOutcome.decode(
          r.dataOrThrow(label: _label).beaconPlanStepCantMake,
        ),
      );
}
