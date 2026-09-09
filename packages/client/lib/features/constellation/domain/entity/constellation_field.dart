import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura/domain/entity/image_entity.dart';

part 'constellation_field.freezed.dart';

enum ConstellationHeldState {
  none,
  offered,
  participant,
  forwarded,
  mine,
}

@freezed
abstract class ConstellationField with _$ConstellationField {
  const factory ConstellationField({
    required DateTime loadedAt,
    required String context,
    @Default([]) List<ConstellationPerson> peers,
    @Default([]) List<ConstellationTrustEdgeEntity> edges,
    @Default([]) List<ConstellationRequest> requests,
    @Default(false) bool peersCapped,
    @Default(false) bool requestsCapped,
  }) = _ConstellationField;
}

@freezed
abstract class ConstellationPerson with _$ConstellationPerson {
  const factory ConstellationPerson({
    required String id,
    String? displayName,
    String? handle,
    ImageEntity? image,
  }) = _ConstellationPerson;
}

@freezed
abstract class ConstellationTrustEdgeEntity with _$ConstellationTrustEdgeEntity {
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
    ImageEntity? coverThumb,
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
