import 'package:tentura_server/domain/entity/gql_public/beacon_close_review_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_extend_review_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_image_added_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_image_staged_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_involvement_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_status_result.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_draft_row_result.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_participant_result.dart';
import 'package:tentura_server/domain/entity/evaluation/evaluations_written_about_viewer_row.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_received_result.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_summary_result.dart';
import 'package:tentura_server/domain/entity/gql_public/forward_graph_result.dart';
import 'package:tentura_server/domain/entity/gql_public/review_window_status_result.dart';

Map<String, dynamic> beaconCloseReviewResultToGqlMap(
  BeaconCloseReviewResult dto,
) => {
  'id': dto.id,
  'status': dto.status,
  'closesAt': dto.closesAt?.toUtc().toIso8601String(),
};

Map<String, dynamic> beaconExtendReviewResultToGqlMap(
  BeaconExtendReviewResult dto,
) => {
  'id': dto.id,
  'closesAt': dto.closesAt.toUtc().toIso8601String(),
  'extensionsRemaining': dto.extensionsRemaining,
};

Map<String, dynamic> beaconImageAddedResultToGqlMap(
  BeaconImageAddedResult dto,
) => {
  'id': dto.id,
  'imageId': dto.imageId,
  'beacon': dto.beacon.asJson,
};

Map<String, dynamic> beaconImageStagedResultToGqlMap(
  BeaconImageStagedResult dto,
) => {
  'imageId': dto.imageId,
  'beaconId': dto.beaconId,
};

Map<String, dynamic> beaconStatusResultToGqlMap(
  BeaconStatusResult dto,
) => {
  'beaconId': dto.beaconId,
  'status': dto.status,
  'statusChangedAt': dto.statusChangedAt?.toUtc().toIso8601String(),
};

Map<String, dynamic> forwardGraphEdgeToGqlMap(ForwardGraphEdgeResult dto) => {
  'id': dto.id,
  'beaconId': dto.beaconId,
  'senderId': dto.senderId,
  'recipientId': dto.recipientId,
  'parentEdgeId': dto.parentEdgeId,
  'batchId': dto.batchId,
};

Map<String, dynamic> forwardGraphResultToGqlMap(ForwardGraphResult dto) => {
  'beaconId': dto.beaconId,
  'authorId': dto.authorId,
  'viewerId': dto.viewerId,
  'helpOffererIds': dto.helpOffererIds,
  'edges': dto.edges.map(forwardGraphEdgeToGqlMap).toList(),
};

Map<String, dynamic> myForwardRecipientToGqlMap(MyForwardRecipientResult dto) =>
    {
      'edgeId': dto.edgeId,
      'recipientId': dto.recipientId,
      'note': dto.note,
      'readAt': dto.readAt?.toIso8601String(),
      'hasOnwardChild': dto.hasOnwardChild,
      'recipientRejected': dto.recipientRejected,
    };

Map<String, dynamic> beaconInvolvementResultToGqlMap(
  BeaconInvolvementResult dto,
) => {
  'forwardedToIds': dto.forwardedToIds,
  'helpOfferedIds': dto.helpOfferedIds,
  'withdrawnIds': dto.withdrawnIds,
  'rejectedIds': dto.rejectedIds,
  'watchingIds': dto.watchingIds,
  'onwardForwarderIds': dto.onwardForwarderIds,
  'myForwardedRecipients': dto.myForwardedRecipients
      .map(myForwardRecipientToGqlMap)
      .toList(),
};

Map<String, dynamic> evaluationParticipantToGqlMap(
  EvaluationParticipantResult dto,
) => {
  'userId': dto.userId,
  'displayName': dto.displayName,
  'imageId': dto.imageId,
  'role': dto.role,
  'contributionSummary': dto.contributionSummary,
  'causalHint': dto.causalHint,
  'value': dto.value,
  'reasonTags': dto.reasonTags,
  'note': dto.note,
  'promptVariant': dto.promptVariant,
};

Map<String, dynamic> evaluationDraftRowToGqlMap(EvaluationDraftRowResult dto) =>
    {
      'evaluatedUserId': dto.evaluatedUserId,
      'value': dto.value,
      'reasonTags': dto.reasonTags,
      'note': dto.note,
    };

Map<String, dynamic> reviewWindowStatusToGqlMap(ReviewWindowStatusResult dto) =>
    {
      'beaconId': dto.beaconId,
      'hasWindow': dto.hasWindow,
      'beaconTitle': dto.beaconTitle,
      'openedAt': dto.openedAt?.toUtc().toIso8601String(),
      'closesAt': dto.closesAt?.toUtc().toIso8601String(),
      'windowComplete': dto.windowComplete,
      'userReviewStatus': dto.userReviewStatus,
      'reviewedCount': dto.reviewedCount,
      'totalCount': dto.totalCount,
      'extensionsUsed': dto.extensionsUsed,
      'canCloseNow': dto.canCloseNow,
    };

Map<String, dynamic> evaluationSummaryToGqlMap(EvaluationSummaryResult dto) => {
  'suppressed': dto.suppressed,
  'tone': dto.tone,
  'message': dto.message,
  'topReasonTags': dto.topReasonTags,
  'neg2': dto.neg2,
  'neg1': dto.neg1,
  'zero': dto.zero,
  'pos1': dto.pos1,
  'pos2': dto.pos2,
  'roleSummaryLine': dto.roleSummaryLine,
};

Map<String, dynamic> evaluationReceivedToGqlMap(
  EvaluationReceivedResult dto,
) => {
  'beaconId': dto.beaconId,
  'beaconTitle': dto.beaconTitle,
  'windowClosed': dto.windowClosed,
  'rows': dto.rows.map(evaluationReceivedRowToGqlMap).toList(),
};

Map<String, dynamic> evaluationReceivedRowToGqlMap(
  EvaluationReceivedRow dto,
) => {
  'reviewerId': dto.reviewerId,
  'reviewerDisplayName': dto.reviewerDisplayName,
  'reviewerImageId': dto.reviewerImageId,
  'reviewerRole': dto.reviewerRole.dbValue,
  'value': dto.value,
  'tone': dto.tone.name,
  'reasonTags': dto.reasonTags,
  'note': dto.note,
  'occurredAt': dto.occurredAt.toUtc().toIso8601String(),
};

Map<String, dynamic> evaluationsWrittenAboutViewerRowToGqlMap(
  EvaluationsWrittenAboutViewerRow dto,
) => {
  'beaconId': dto.beaconId,
  'beaconTitle': dto.beaconTitle,
  'beaconClosedAt': dto.beaconClosedAt?.toUtc().toIso8601String(),
  'evaluatorId': dto.evaluatorId,
  'evaluatedUserId': dto.evaluatedUserId,
  'value': dto.value,
  'tone': dto.tone.name,
  'reasonTags': dto.reasonTags,
  'note': dto.note,
  'occurredAt': dto.occurredAt.toUtc().toIso8601String(),
};
