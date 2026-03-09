import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/invitation_repository.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';

import '../exception.dart';

@Injectable(order: 2)
class InvitationCase {
  InvitationCase(
    this._invitationRepository,
    this._userRepository,
  );

  final InvitationRepository _invitationRepository;

  final UserRepository _userRepository;

  Future<InvitationEntity> fetchById({
    required String invitationId,
  }) async {
    final invitation = await _invitationRepository.getById(
      invitationId: invitationId,
    );
    if (invitation == null || invitation.isAccepted || invitation.isExpired) {
      throw IdNotFoundException(id: invitationId);
    }
    return invitation;
  }

  Future<bool> accept({
    required String invitationId,
    required String userId,
  }) => _userRepository.bindMutual(
    invitationId: invitationId,
    userId: userId,
  );

  Future<bool> delete({
    required String invitationId,
    required String userId,
  }) => _invitationRepository.deleteById(
    invitationId: invitationId,
    userId: userId,
  );
}
