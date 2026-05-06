import 'package:tentura_server/domain/entity/invitation_entity.dart';

abstract class InvitationRepositoryPort {
  Future<InvitationEntity?> getById({
    required String invitationId,
  });

  Future<InvitationEntity> create({
    required String issuerId,
    String? beaconId,
  });

  Future<bool> deleteById({
    required String invitationId,
    required String userId,
  });
}
