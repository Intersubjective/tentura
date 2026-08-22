import 'package:freezed_annotation/freezed_annotation.dart';

import 'identifiable.dart';

part 'invitation_entity.freezed.dart';

@freezed
abstract class InvitationEntity extends Identifiable with _$InvitationEntity {
  const factory InvitationEntity({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? invitedId,
    String? beaconId,
    String? beaconTitle,

    /// Who this invite is for, as the issuer named them (subjective
    /// profiles). Null only on legacy invites.
    String? addresseeName,

    /// 'new_account' | 'existing_account'. Null while pending.
    String? inviteOrigin,

    /// When this invite was consumed. Null while pending.
    DateTime? acceptedAt,

    /// Accepter's current display name, via the `invited` relationship.
    /// Null while pending, or if the accepter is hidden to this viewer.
    String? invitedName,

    /// Accepter's current avatar image id. Same nullability as [invitedName].
    String? invitedImageId,
  }) = _InvitationEntity;

  const InvitationEntity._();

  bool get isAccepted => invitedId != null;
}
