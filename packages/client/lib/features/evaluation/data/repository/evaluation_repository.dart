import 'package:built_collection/built_collection.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';

import '../gql/_g/beacon_close_with_review.req.gql.dart';
import '../gql/_g/evaluation_draft_participants.data.gql.dart';
import '../gql/_g/evaluation_draft_participants.req.gql.dart';
import '../gql/_g/evaluation_draft_save.req.gql.dart';
import '../gql/_g/evaluation_finalize.req.gql.dart';
import '../gql/_g/evaluation_participants.data.gql.dart';
import '../gql/_g/evaluation_participants.req.gql.dart';
import '../gql/_g/evaluation_skip.req.gql.dart';
import '../gql/_g/evaluation_submit.req.gql.dart';
import '../gql/_g/evaluation_summary.req.gql.dart';
import '../gql/_g/review_window_status.req.gql.dart';

@lazySingleton
class EvaluationRepository {
  EvaluationRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'EvaluationRepository';

  EvaluationParticipant _participantFromGraphqlRow({
    required String userId,
    required String title,
    required String imageId,
    required int role,
    required String contributionSummary,
    required String causalHint,
    required String promptVariant,
    required int? value,
    required List<String>? reasonTags,
    required String note,
  }) {
    final tags = reasonTags ?? const <String>[];
    return EvaluationParticipant(
      userId: userId,
      title: title,
      imageId: imageId,
      role: _roleFromInt(role),
      contributionSummary: contributionSummary,
      causalHint: causalHint,
      promptVariant: promptVariant,
      currentValue: EvaluationValue.fromWire(value),
      reasonTags: tags,
      note: note,
    );
  }

  EvaluationParticipant _mapParticipant(
    GEvaluationParticipantsData_evaluationParticipants e,
  ) =>
      _participantFromGraphqlRow(
        userId: e.userId,
        title: e.title,
        imageId: e.imageId,
        role: e.role,
        contributionSummary: e.contributionSummary,
        causalHint: e.causalHint,
        promptVariant: e.promptVariant,
        value: e.value,
        reasonTags: e.reasonTags?.toList(),
        note: e.note,
      );

  EvaluationParticipant _mapDraftParticipant(
    GEvaluationDraftParticipantsData_evaluationDraftParticipants e,
  ) =>
      _participantFromGraphqlRow(
        userId: e.userId,
        title: e.title,
        imageId: e.imageId,
        role: e.role,
        contributionSummary: e.contributionSummary,
        causalHint: e.causalHint,
        promptVariant: e.promptVariant,
        value: e.value,
        reasonTags: e.reasonTags?.toList(),
        note: e.note,
      );

  Future<List<EvaluationParticipant>> fetchParticipants(String beaconId) =>
      _remoteApiService
          .request(
            GEvaluationParticipantsReq(
              (b) => b.vars.id = beaconId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final rows =
                r.dataOrThrow(label: _label).evaluationParticipants;
            if (rows == null) {
              return <EvaluationParticipant>[];
            }
            return rows.map(_mapParticipant).toList();
          });

  Future<List<EvaluationParticipant>> fetchDraftParticipants(String beaconId) =>
      _remoteApiService
          .request(
            GEvaluationDraftParticipantsReq(
              (b) => b.vars.id = beaconId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final rows =
                r.dataOrThrow(label: _label).evaluationDraftParticipants;
            if (rows == null) {
              return <EvaluationParticipant>[];
            }
            return rows.map(_mapDraftParticipant).toList();
          });

  Future<ReviewWindowInfo> fetchReviewWindowStatus(String beaconId) =>
      _remoteApiService
          .request(
            GReviewWindowStatusReq(
              (b) => b.vars.id = beaconId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final s = r.dataOrThrow(label: _label).reviewWindowStatus;
            return ReviewWindowInfo(
              beaconId: s.beaconId,
              hasWindow: s.hasWindow,
              beaconTitle: s.beaconTitle,
              openedAt: s.openedAt,
              closesAt: s.closesAt,
              windowComplete: s.windowComplete ?? false,
              userReviewStatus: s.userReviewStatus,
              reviewedCount: s.reviewedCount ?? 0,
              totalCount: s.totalCount ?? 0,
            );
          });

  /// Draft screen: load window (for beacon title) and targets in parallel.
  Future<({ReviewWindowInfo window, List<EvaluationParticipant> participants})>
      fetchDraftModeBootstrap(String beaconId) async {
    late ReviewWindowInfo window;
    late List<EvaluationParticipant> participants;
    await Future.wait<void>([
      fetchReviewWindowStatus(beaconId).then((w) => window = w),
      fetchDraftParticipants(beaconId).then((p) => participants = p),
    ]);
    return (window: window, participants: participants);
  }

  Future<EvaluationSummary> fetchSummary(String beaconId) =>
      _remoteApiService
          .request(
            GEvaluationSummaryReq(
              (b) => b.vars.id = beaconId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
            final s = r.dataOrThrow(label: _label).evaluationSummary;
            return EvaluationSummary(
              suppressed: s.suppressed,
              tone: s.tone,
              message: s.message,
              topReasonTags: s.topReasonTags?.toList() ?? const [],
              neg2: s.neg2,
              neg1: s.neg1,
              zero: s.zero,
              pos1: s.pos1,
              pos2: s.pos2,
              roleSummaryLine: s.roleSummaryLine,
            );
          });

  Future<void> submit({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String> reasonTags = const [],
    String note = '',
  }) async {
    await _remoteApiService
        .request(
          GEvaluationSubmitReq(
            (b) => b.vars
              ..id = beaconId
              ..evaluatedUserId = evaluatedUserId
              ..value = value
              ..reasonTags = ListBuilder<String>(reasonTags)
              ..note = note.isEmpty ? null : note,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
  }

  Future<void> draftSave({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String> reasonTags = const [],
    String note = '',
  }) async {
    await _remoteApiService
        .request(
          GEvaluationDraftSaveReq(
            (b) => b.vars
              ..id = beaconId
              ..evaluatedUserId = evaluatedUserId
              ..value = value
              ..reasonTags = ListBuilder<String>(reasonTags)
              ..note = note.isEmpty ? null : note,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
  }

  Future<void> finalize(String beaconId) async {
    await _remoteApiService
        .request(
          GEvaluationFinalizeReq((b) => b.vars.id = beaconId),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
  }

  Future<void> skip(String beaconId) async {
    await _remoteApiService
        .request(
          GEvaluationSkipReq((b) => b.vars.id = beaconId),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
  }

  /// Returns new beacon state (5) and review end time.
  Future<({String closesAt})> beaconCloseWithReview(String beaconId) =>
      _remoteApiService
          .request(
            GBeaconCloseWithReviewReq((b) => b.vars.id = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => (
              closesAt: r.dataOrThrow(label: _label).beaconCloseWithReview
                  .closesAt,
            ),
          );
}

EvaluationParticipantRole _roleFromInt(int v) => switch (v) {
      0 => EvaluationParticipantRole.author,
      1 => EvaluationParticipantRole.committer,
      2 => EvaluationParticipantRole.forwarder,
      _ => EvaluationParticipantRole.committer,
    };
