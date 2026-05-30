import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/invite_preview_result.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';

import '../exception.dart';
import '_use_case_base.dart';

@Injectable(order: 2)
final class InvitationCase extends UseCaseBase {
  InvitationCase(
    this._invitationRepository,
    this._userRepository,
    this._beaconRepository,
    this._friendshipLookup, {
    required super.env,
    required super.logger,
  });

  final InvitationRepositoryPort _invitationRepository;

  final UserRepositoryPort _userRepository;

  final BeaconRepositoryPort _beaconRepository;

  final VoteUserFriendshipLookup _friendshipLookup;

  Future<InvitationEntity> create({
    required String userId,
    String? beaconId,
  }) => _invitationRepository.create(
    issuerId: userId,
    beaconId: beaconId,
  );

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

  /// Read-only preview of what [code] means for [callerUserId] (null =
  /// anonymous). Unlike [fetchById] this never throws on a consumed/expired
  /// code — it reports the state so the landing can render before any UI.
  Future<InvitePreviewResult> preview({
    required String code,
    String? callerUserId,
  }) async {
    final invitation = await _invitationRepository.getById(invitationId: code);
    if (invitation == null) {
      return const InvitePreviewResult(
        codeStatus: InviteCodeStatus.invalid,
        callerStatus: InviteCallerStatus.anonymous,
      );
    }

    final codeStatus = invitation.isAccepted
        ? InviteCodeStatus.consumed
        : invitation.isExpired
        ? InviteCodeStatus.expired
        : InviteCodeStatus.available;

    final InviteCallerStatus callerStatus;
    if (callerUserId == null) {
      callerStatus = InviteCallerStatus.anonymous;
    } else if (callerUserId == invitation.issuer.id) {
      callerStatus = InviteCallerStatus.isInviter;
    } else if (await _friendshipLookup.isReciprocalSubscribe(
      viewerId: callerUserId,
      peerId: invitation.issuer.id,
    )) {
      callerStatus = InviteCallerStatus.alreadyFriends;
    } else {
      callerStatus = InviteCallerStatus.existingUser;
    }

    BeaconEntity? beacon;
    if (invitation.beaconId != null) {
      try {
        beacon = await _beaconRepository.getBeaconById(
          beaconId: invitation.beaconId!,
        );
      } catch (_) {
        beacon = null; // beacon removed since the invite was minted
      }
    }

    return InvitePreviewResult(
      codeStatus: codeStatus,
      callerStatus: callerStatus,
      inviter: invitation.issuer,
      beacon: beacon,
    );
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
