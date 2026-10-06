import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import '../gql/_g/beacon_model.data.gql.dart';
import 'image_model.dart';
import 'user_model.dart';

extension type const BeaconModel(GBeaconModel i) implements GBeaconModel {
  Beacon toEntity() {
    final author = (i.author as UserModel).toEntity();
    return Beacon(
      id: i.id,
      author: author,
      title: i.title,
      status: BeaconStatus.fromSmallint(i.status),
      statusChangedAt: i.status_changed_at,
      createdAt: i.created_at,
      updatedAt: i.updated_at,
      description: i.description,
      isPinned: i.is_pinned ?? false,
      context: i.context ?? '',
      myVote: i.my_vote ?? 0,
      coordinates: i.lat == null || i.long == null
          ? Coordinates.zero
          : Coordinates(
              lat: i.lat ?? 0,
              long: i.long ?? 0,
            ),
      addressLabel: i.address_label,
      // No `score`/`rScore`: Requests are not MeritRank nodes, so asking
      // Hasura's `scores` for them only made MeritRank log "Node not found".
      images: [
        for (final bi in i.beacon_images) (bi.image as ImageModel).asEntity,
      ],
      tags: {
        if (i.tags.isNotEmpty) ...i.tags.split(','),
      },
      needs: {
        if (i.needs.isNotEmpty) ...i.needs.split(','),
      },
      startAt: i.start_at,
      endAt: i.end_at,
      helpOfferCount:
          (i.help_offers_aggregate.aggregate?.count ?? 0) +
          i.participant_help_offers.length,
      unansweredHelpOfferCount: i.unanswered_help_offers.aggregate?.count ?? 0,
      primaryNeedSlug: i.primary_need_slug,
      coverImageId: i.cover_image_id,
      coverSource: BeaconCoverSource.fromWireOrPhoto(i.cover_source),
      coverThumb: i.cover_thumb_image == null
          ? null
          : (i.cover_thumb_image as ImageModel).asEntity,
      lineageParentBeaconId: i.lineage_parent_beacon_id,
      lineageRootBeaconId: i.lineage_root_beacon_id,
      canReadContent: i.can_read_content ?? true,
      canReadInvolvement: i.can_read_involvement ?? true,
      canReadAdmittedHelpers: i.can_read_admitted_helpers ?? true,
      accessLevel: i.access_level == null
          ? null
          : BeaconAccessLevel.fromInt(i.access_level),
      accessReasons: i.access_reasons ?? 0,
      isDiscoverable: i.is_discoverable,
      kind: BeaconKind.fromValue(i.kind),
      forwardPolicy: BeaconForwardPolicyValue.fromValue(i.forward_policy),
      lastActivityAt: i.last_activity_at,
      postRootMessageId: i.post_root_message_id,
      viewerCanForward: i.viewer_can_forward ?? false,
    );
  }
}
