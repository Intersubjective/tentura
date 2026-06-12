import 'package:tentura_server/domain/entity/invitation_entity.dart';

abstract class InvitationRepositoryPort {
  Future<InvitationEntity?> getById({
    required String invitationId,
  });

  Future<InvitationEntity> create({
    required String issuerId,
    required String addresseeName,
    String? beaconId,
  });

  /// Renames the addressee of the caller's own, still unconsumed invite.
  /// Throws `IdNotFoundException` when no such invite exists.
  Future<InvitationEntity> updateAddresseeName({
    required String invitationId,
    required String userId,
    required String addresseeName,
  });

  Future<bool> deleteById({
    required String invitationId,
    required String userId,
  });
}
