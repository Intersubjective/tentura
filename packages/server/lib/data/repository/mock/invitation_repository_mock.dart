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
    );
    storageById[entity.id] = entity;
    return entity;
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
