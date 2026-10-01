import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_cancel_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_image_added_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_image_staged_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_involvement_result.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_status_result.dart';
import 'package:tentura_server/domain/entity/gql_public/forward_graph_result.dart';

Map<String, dynamic> beaconCancelResultToGqlMap(BeaconCancelResult dto) => {
  'id': dto.id,
  'status': dto.status,
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

Map<String, dynamic> beaconHierarchyOwnerSummaryToGqlMap(
  BeaconHierarchyOwnerSummary owner,
) => {
  'id': owner.id,
  'displayName': owner.displayName,
  'avatarImageId': owner.avatarImageId,
};

Map<String, dynamic> beaconHierarchySummaryToGqlMap(
  BeaconHierarchySummary summary,
) => {
  'beaconId': summary.beaconId,
  'title': summary.title,
  'description': summary.description,
  'owner': summary.owner == null
      ? null
      : beaconHierarchyOwnerSummaryToGqlMap(summary.owner!),
  'status': summary.status.smallintValue,
  'publishedAt': summary.publishedAt.toUtc().toIso8601String(),
  'statusChangedAt': summary.statusChangedAt?.toUtc().toIso8601String(),
  'isTombstone': summary.isTombstone,
  'coverSource': summary.coverSource.wireValue,
  'coverImageId': summary.coverImageId,
  'coverThumbImageId': summary.coverThumbImageId,
  'primaryNeedSlug': summary.primaryNeedSlug,
  'needs': summary.needs.join(','),
  'admittedHelperPreviews': summary.admittedHelperPreviews
      .map(beaconHierarchyOwnerSummaryToGqlMap)
      .toList(),
  'admittedHelperCount': summary.admittedHelperCount,
};

Map<String, dynamic> beaconHierarchyPageToGqlMap(BeaconHierarchyPage page) => {
  'summaries': page.summaries.map(beaconHierarchySummaryToGqlMap).toList(),
  'nextCursor': page.nextCursor,
};

Map<String, dynamic> beaconHierarchyCapabilitiesToGqlMap(
  BeaconHierarchyCapabilities capabilities,
) => {
  'canListChildren': capabilities.canListChildren,
  'canCreateChild': capabilities.canCreateChild,
  'denialCode': capabilities.denialCode?.name,
};

Map<String, dynamic> beaconParentReferenceToGqlMap(
  BeaconParentReference reference,
) => {
  'state': reference.state.name,
  'beaconId': reference.beaconId,
  'title': reference.title,
};

Map<String, dynamic> beaconPromotionSourceToGqlMap(
  BeaconPromotionSource source,
) => {
  'sourceBeaconId': source.sourceBeaconId,
  'sourceMessageId': source.sourceMessageId,
  'textPreview': source.textPreview,
  'author': beaconHierarchyOwnerSummaryToGqlMap(source.author),
};

Map<String, dynamic> beaconChildCreateResultToGqlMap(
  BeaconChildCreateResult result,
) => {
  'outcome': result.outcome.name,
  'beaconId': result.beaconId,
  'beacon': switch (result.outcome) {
    BeaconChildCommandOutcome.created ||
    BeaconChildCommandOutcome.replayed =>
      result.beacon?.asJson,
    BeaconChildCommandOutcome.alreadyPromoted => null,
  },
};
