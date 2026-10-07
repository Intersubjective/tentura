import 'package:built_collection/built_collection.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/beacon_close_result.dart';
import '../../domain/entity/closure_band.dart';
import '../../domain/entity/closure_draft_flag.dart';
import '../../domain/entity/closure_member.dart';
import '../../domain/entity/closure_outcome.dart';
import '../../domain/entity/closure_result.dart';
import '../../domain/entity/closure_role.dart';
import '../../domain/entity/closure_state.dart';
import '../gql/_g/beacon_cancel.req.gql.dart';
import '../gql/_g/beacon_close.req.gql.dart';
import '../gql/_g/beacon_close_now.req.gql.dart';
import '../gql/_g/beacon_extend_closure.req.gql.dart';
import '../gql/_g/beacon_reopen.req.gql.dart';
import '../gql/_g/closure_done.req.gql.dart';
import '../gql/_g/closure_result_for_viewer.req.gql.dart';
import '../gql/_g/closure_save_author_split.req.gql.dart';
import '../gql/_g/closure_save_outcome.req.gql.dart';
import '../gql/_g/closure_save_story.req.gql.dart';
import '../gql/_g/closure_set_mark.req.gql.dart';
import '../gql/_g/closure_skip.req.gql.dart';
import '../gql/_g/closure_state.req.gql.dart';
import '../gql/_g/closure_toggle_support.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class ClosureRepository {
  ClosureRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'ClosureRepository';

  Future<ClosureState> fetchState(String beaconId) => _remoteApiService
      .request(GClosureStateReq((b) => b.vars.beaconId = beaconId))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        final s = r.dataOrThrow(label: _label).closureState;
        return ClosureState(
          epoch: s.epoch,
          status: s.status,
          role: ClosureRole.fromWire(s.role.name),
          members: [
            for (final m in s.members)
              ClosureMember(
                id: m.id,
                displayName: m.displayName,
                avatarId: m.avatarId,
                helpTypes: m.helpTypes?.toList(),
                offerText: m.offerText,
                notInRequest: m.notInRequest,
                departure: m.departure,
              ),
          ],
          outcomes: s.outcomes == null
              ? null
              : {
                  for (final o in s.outcomes!)
                    o.helperId: ClosureOutcome.fromWire(o.outcome.name),
                },
          split: s.split == null
              ? null
              : {for (final e in s.split!) e.helperId: e.pct},
          mySupport: s.mySupport?.toList() ?? const [],
          inCalcText: s.inCalcText,
          myMarks: s.myMarks?.toList() ?? const [],
          closesAt: DateTime.parse(s.closesAt).toUtc(),
          earlyCloseAt: s.earlyCloseAt == null
              ? null
              : DateTime.parse(s.earlyCloseAt!).toUtc(),
          canCloseNow: s.canCloseNow ?? false,
          canReopen: s.canReopen ?? false,
          extensionsUsed: s.extensionsUsed ?? 0,
          story: s.story,
        );
      });

  Future<ClosureResult?> fetchResultForViewer(String beaconId) =>
      _remoteApiService
          .request(
            GClosureResultForViewerReq((b) => b.vars.beaconId = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final s = r.dataOrThrow(label: _label).closureResultForViewer;
            if (s == null) return null;
            return ClosureResult(
              outcome: ClosureOutcome.fromWire(s.outcome.name),
              band: ClosureBand.fromWire(s.band.name),
              draftFlag: ClosureDraftFlag.fromWire(s.draftFlag.name),
              marks: s.marks?.toList() ?? const [],
              story: s.story,
            );
          });

  Future<void> saveOutcome({
    required String beaconId,
    required int expectedEpoch,
    required String helperId,
    required ClosureOutcome? outcome,
  }) => _remoteApiService
      .request(
        GClosureSaveOutcomeReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..expectedEpoch = expectedEpoch
            ..helperId = helperId
            ..outcome = outcome == null
                ? null
                : Gv2_ClosureOutcome.valueOf(outcome.wire),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  /// A null [split] clears the custom split.
  Future<void> saveAuthorSplit({
    required String beaconId,
    required int expectedEpoch,
    required Map<String, int>? split,
  }) => _remoteApiService
      .request(
        GClosureSaveAuthorSplitReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..expectedEpoch = expectedEpoch
            ..split = split == null
                ? null
                : ListBuilder<Gv2_ClosureSplitEntryInput>([
                    for (final e in split.entries)
                      Gv2_ClosureSplitEntryInput(
                        (s) => s
                          ..helperId = e.key
                          ..pct = e.value,
                      ),
                  ]),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  /// Returns the id of the target whose support was released to make room,
  /// if any.
  Future<String?> toggleSupport({
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) => _remoteApiService
      .request(
        GClosureToggleSupportReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..expectedEpoch = expectedEpoch
            ..targetId = targetId
            ..on = on,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).closureToggleSupport.released);

  Future<void> done({required String beaconId, required int expectedEpoch}) =>
      _remoteApiService
          .request(
            GClosureDoneReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..expectedEpoch = expectedEpoch,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label));

  Future<void> skip({required String beaconId, required int expectedEpoch}) =>
      _remoteApiService
          .request(
            GClosureSkipReq(
              (b) => b.vars
                ..beaconId = beaconId
                ..expectedEpoch = expectedEpoch,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label));

  Future<void> setMark({
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) => _remoteApiService
      .request(
        GClosureSetMarkReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..expectedEpoch = expectedEpoch
            ..targetId = targetId
            ..on = on,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<void> saveStory({
    required String beaconId,
    required int expectedEpoch,
    required String body,
  }) => _remoteApiService
      .request(
        GClosureSaveStoryReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..expectedEpoch = expectedEpoch
            ..body = body,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<void> close(String beaconId) => _remoteApiService
      .request(GBeaconCloseReq((b) => b.vars.beaconId = beaconId))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<void> closeNow({
    required String beaconId,
    required int expectedEpoch,
  }) => _remoteApiService
      .request(
        GBeaconCloseNowReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..expectedEpoch = expectedEpoch,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<void> extendClosure({
    required String beaconId,
    required int expectedEpoch,
  }) => _remoteApiService
      .request(
        GBeaconExtendClosureReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..expectedEpoch = expectedEpoch,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<void> reopen({
    required String beaconId,
    required int expectedEpoch,
  }) => _remoteApiService
      .request(
        GBeaconReopenReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..expectedEpoch = expectedEpoch,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<BeaconLifecycleMutationResult> beaconCancel(String beaconId) =>
      _remoteApiService
          .request(GBeaconCancelReq((b) => b.vars.id = beaconId))
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final result = r.dataOrThrow(label: _label).beaconCancel;
            return BeaconLifecycleMutationResult(
              beaconId: result.id,
              state: result.status,
            );
          });

  // The request-view and My Work callers carry no epoch, so each of these
  // reads the closure state first and reports the state it ends in.

  Future<BeaconCloseResult> beaconClose({required String beaconId}) async {
    await close(beaconId);
    final closure = await fetchState(beaconId);
    return BeaconCloseResult(
      beaconId: beaconId,
      state: closure.status,
      closesAt: closure.epoch == 0 ? null : closure.closesAt.toIso8601String(),
    );
  }

  Future<BeaconExtendReviewResult> beaconExtendReview(String beaconId) async {
    final before = await fetchState(beaconId);
    await extendClosure(beaconId: beaconId, expectedEpoch: before.epoch);
    final after = await fetchState(beaconId);
    return BeaconExtendReviewResult(
      beaconId: beaconId,
      closesAt: after.closesAt.toIso8601String(),
    );
  }

  Future<BeaconLifecycleMutationResult> beaconReopen(String beaconId) async {
    final before = await fetchState(beaconId);
    await reopen(beaconId: beaconId, expectedEpoch: before.epoch);
    final after = await fetchState(beaconId);
    return BeaconLifecycleMutationResult(
      beaconId: beaconId,
      state: after.status,
    );
  }

  Future<BeaconLifecycleMutationResult> beaconCloseNow(String beaconId) async {
    final before = await fetchState(beaconId);
    await closeNow(beaconId: beaconId, expectedEpoch: before.epoch);
    final after = await fetchState(beaconId);
    return BeaconLifecycleMutationResult(
      beaconId: beaconId,
      state: after.status,
    );
  }
}
