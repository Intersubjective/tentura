import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/invitation_entity.dart';

import 'package:tentura_server/domain/port/invitation_repository_port.dart';

import 'data/invitations.dart';

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
  Future<bool> deleteById({
    required String invitationId,
    required String userId,
  }) => Future.value(storageById.remove(invitationId) != null);

  @override
  Future<InvitationEntity?> getById({
    required String invitationId,
  }) => Future.value(storageById[invitationId]);
}
