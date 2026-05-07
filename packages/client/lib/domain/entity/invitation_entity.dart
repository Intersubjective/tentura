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
  }) = _InvitationEntity;

  const InvitationEntity._();
}
