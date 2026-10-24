import 'package:meta/meta.dart' show immutable;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura/domain/entity/image_entity.dart';

import 'constellation_anchor_projection.dart';

part 'constellation_field.freezed.dart';

enum ConstellationHeldState {
  none,
  offered,
  participant,
  forwarded,
  mine,
}

/// Why a person is on the field (wire name `presence`).
enum ConstellationFieldMembership {
  visible,
  bond,
  temporary,
  contactOnly,
}

/// Automatic tags derived from the viewer's trust relation to a person.
enum ConstellationAutoTagKind {
  mutualContact,
  iTrust,
  trustsMe,
}

/// A Request the viewer works on together with a bond person.
@immutable
class ConstellationBondContext {
  const ConstellationBondContext({required this.beaconId, required this.title});

  final String beaconId;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is ConstellationBondContext &&
      other.beaconId == beaconId &&
      other.title == title;

  @override
  int get hashCode => Object.hash(beaconId, title);
}

@freezed
abstract class ConstellationField with _$ConstellationField {
  const factory ConstellationField({
    required DateTime loadedAt,
    required String context,
    @Default([]) List<ConstellationPerson> peers,
    @Default([]) List<ConstellationTrustEdgeEntity> edges,
    @Default([]) List<ConstellationRequest> requests,
    @Default([]) List<ConstellationPost> posts,
    @Default([]) List<ConstellationMemberWeb> memberWebs,
    @Default(false) bool peersCapped,
    @Default(false) bool requestsCapped,

    /// Everyone the viewer trusts directly (#246): always on the field and
    /// outside both peer caps. Kept across ANCHORS refreshes, which carry
    /// none.
    @Default([]) List<String> directContactIds,
    ConstellationAnchorProjection? anchorProjection,
  }) = _ConstellationField;

  const ConstellationField._();

  ConstellationAnchorProjection get resolvedAnchorProjection =>
      anchorProjection ?? ConstellationAnchorProjection.empty;
}

@freezed
abstract class ConstellationPerson with _$ConstellationPerson {
  const factory ConstellationPerson({
    required String id,
    String? displayName,
    String? handle,
    ImageEntity? image,

    /// False for a pinned person outside the viewer's visible set.
    @Default(true) bool visible,

    /// A contact node without content (#246): someone the viewer trusts
    /// directly who is outside the viewer's visible set. Identity only; the
    /// field holds no edge of theirs but the viewer's own.
    @Default(false) bool contactOnly,

    /// Why the person is on the field; read only with
    /// `kFieldMembershipV2Enabled`.
    @Default(ConstellationFieldMembership.visible)
    ConstellationFieldMembership fieldMembership,

    /// The viewer's own tags on the person (ids only).
    @Default([]) List<String> ownTagIds,
    @Default({}) Set<ConstellationAutoTagKind> autoTagKinds,
    DateTime? firstSeenAt,

    /// The Request that made a temporary person visible.
    String? temporaryBeaconId,

    /// The Requests a bond person works on with the viewer.
    @Default([]) List<ConstellationBondContext> bondContexts,
  }) = _ConstellationPerson;
}

@freezed
abstract class ConstellationTrustEdgeEntity
    with _$ConstellationTrustEdgeEntity {
  const factory ConstellationTrustEdgeEntity({
    required String src,
    required String dst,
    required int tier,
  }) = _ConstellationTrustEdgeEntity;
}

@freezed
abstract class ConstellationRequest with _$ConstellationRequest {
  const factory ConstellationRequest({
    required String id,
    required String authorId,
    required String title,
    required int status,
    @Default([]) List<String> needs,
    String? primaryNeedSlug,
    DateTime? startAt,
    DateTime? endAt,
    String? addressLabel,
    @Default(false) bool hasCoordinates,
    @Default(false) bool isMine,
    @Default(false) bool viewerHasActiveHelpOffer,
    @Default(false) bool viewerIsRoomParticipant,
    @Default(false) bool viewerHasForwardEdge,
    @Default(0) int helpOfferCount,
    @Default(BeaconCoverSource.photo) BeaconCoverSource coverSource,
    ImageEntity? coverThumb,

    /// The Post this Request budded from, when the viewer can read it.
    String? parentBeaconId,
  }) = _ConstellationRequest;

  const ConstellationRequest._();

  ConstellationHeldState get heldState {
    if (isMine) {
      return ConstellationHeldState.mine;
    }
    if (viewerHasActiveHelpOffer) {
      return ConstellationHeldState.offered;
    }
    if (viewerIsRoomParticipant) {
      return ConstellationHeldState.participant;
    }
    if (viewerHasForwardEdge) {
      return ConstellationHeldState.forwarded;
    }
    return ConstellationHeldState.none;
  }
}

/// A Post on the Constellation field; labelled by its root excerpt.
@freezed
abstract class ConstellationPost with _$ConstellationPost {
  const factory ConstellationPost({
    required String id,
    required String authorId,
    required String rootExcerpt,
    required DateTime lastActivityAt,
    @Default(false) bool isPinned,
    @Default(0) int hiddenReachCount,
  }) = _ConstellationPost;
}

/// `inside`: the author or an admitted member who opened the Post;
/// `forwarded`: a recipient of an active forward edge who has not opened it.
enum ConstellationMemberWebState { forwarded, inside }

@freezed
abstract class ConstellationMemberWeb with _$ConstellationMemberWeb {
  const factory ConstellationMemberWeb({
    required String beaconId,
    required String personId,
    required ConstellationMemberWebState state,
  }) = _ConstellationMemberWeb;
}
