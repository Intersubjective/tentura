import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';

import '../exception.dart';
import '_use_case_base.dart';

@Injectable(order: 2)
final class InvitationCase extends UseCaseBase {
  InvitationCase(
    this._invitationRepository,
    this._userRepository, {
    required super.env,
    required super.logger,
  });

  final InvitationRepositoryPort _invitationRepository;

  final UserRepositoryPort _userRepository;

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
