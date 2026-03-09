import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/invitation_entity.dart';

import '../invitation_repository.dart';
import 'data/invitations.dart';

@Injectable(
  as: InvitationRepository,
  env: [Environment.test],
  order: 1,
)
class InvitationRepositoryMock implements InvitationRepository {
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
