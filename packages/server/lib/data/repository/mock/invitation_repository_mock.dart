import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';

import 'data/invitations.dart';
import 'data/users.dart';

@Injectable(
  as: InvitationRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class InvitationRepositoryMock implements InvitationRepositoryPort {
  final storageById = <String, InvitationEntity>{
    ...kInvitationsById,
  };

  @override
  Future<InvitationEntity> create({
    required String issuerId,
    required String addresseeName,
    String? beaconId,
  }) async {
    final issuer = kUserByPublicKey.values
        .where((e) => e.id == issuerId)
        .firstOrNull;
    if (issuer == null) {
      throw IdNotFoundException(id: issuerId);
    }
    final now = DateTime.now();
    final entity = InvitationEntity(
      id: InvitationEntity.newId,
      issuer: issuer,
      createdAt: now,
      updatedAt: now,
      beaconId: beaconId,
      addresseeName: addresseeName,
    );
    storageById[entity.id] = entity;
    return entity;
  }

  @override
  Future<InvitationEntity> updateAddresseeName({
    required String invitationId,
    required String userId,
    required String addresseeName,
  }) async {
    final invitation = storageById[invitationId];
    if (invitation == null ||
        invitation.issuer.id != userId ||
        invitation.isAccepted) {
      throw IdNotFoundException(id: invitationId);
    }
    final updated = invitation.copyWith(
      addresseeName: addresseeName,
      updatedAt: DateTime.now(),
    );
    storageById[invitationId] = updated;
    return updated;
  }

  @override
  Future<bool> deleteById({
    required String invitationId,
    required String userId,
  }) => Future.value(storageById.remove(invitationId) != null);

  @override
  Future<InvitationEntity?> getById({
    required String invitationId,
  }) => Future.value(storageById[invitationId]);
}
