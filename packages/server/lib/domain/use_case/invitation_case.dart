import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/beacon_visibility.dart';
import 'package:tentura_server/domain/coordination/resolve_forward_parent_edge.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/invite_preview_result.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/exception.dart';

import '_use_case_base.dart';
import 'contact_case.dart';

@Injectable(order: 2)
final class InvitationCase extends UseCaseBase {
  InvitationCase(
    this._invitationRepository,
    this._userRepository,
    this._beaconRepository,
    this._friendshipLookup,
    this._contactRepository,
    this._guard,
    this._forwardEdgeRepository, {
    required super.env,
    required super.logger,
  });

  final InvitationRepositoryPort _invitationRepository;

  final UserRepositoryPort _userRepository;

  final BeaconRepositoryPort _beaconRepository;

  final VoteUserFriendshipLookupPort _friendshipLookup;

  final UserContactRepositoryPort _contactRepository;

  final BeaconAccessGuard _guard;

  final ForwardEdgeRepositoryPort _forwardEdgeRepository;

  Future<InvitationEntity> create({
    required String userId,
    required String addresseeName,
    String? beaconId,
  }) async {
    String? parentForwardEdgeId;
    if (beaconId != null) {
      if (!await _guard.canReadContent(beaconId: beaconId, viewerId: userId)) {
        throw const UnauthorizedException(
          description: 'Issuer cannot read request content',
        );
      }
      final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
      if (!beacon.allowsForward) {
        throw const UnauthorizedException(
          description: 'Request does not allow forwarding',
        );
      }
      final inbound = await _forwardEdgeRepository.fetchActiveInboundEdges(
        beaconId: beaconId,
        recipientId: userId,
      );
      parentForwardEdgeId = resolveForwardParentEdgeId(
        clientParentEdgeId: null,
        activeInboundEdges: inbound,
        senderId: userId,
        authorId: beacon.author.id,
      );
    }

    return _invitationRepository.create(
      issuerId: userId,
      addresseeName: ContactCase.normalizeName(addresseeName),
      beaconId: beaconId,
      parentForwardEdgeId: parentForwardEdgeId,
    );
  }

  /// Renames the addressee of the caller's own, still unconsumed invite.
  Future<InvitationEntity> update({
    required String invitationId,
    required String userId,
    required String addresseeName,
  }) async => _invitationRepository.updateAddresseeName(
    invitationId: invitationId,
    userId: userId,
    addresseeName: ContactCase.normalizeName(addresseeName),
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
    final beaconId = invitation.beaconId;
    if (beaconId != null) {
      beacon = await _previewBeaconForInvite(
        beaconId: beaconId,
        issuerId: invitation.issuer.id,
        invitationExists: true,
        invitationConsumed: invitation.isAccepted,
        invitationExpired: invitation.isExpired,
      );
    }

    var inviter = invitation.issuer;
    if (callerUserId != null && callerUserId != inviter.id) {
      final contactName = await _contactRepository.getName(
        viewerId: callerUserId,
        subjectId: inviter.id,
      );
      if (contactName != null) {
        inviter = inviter.copyWith(displayName: contactName);
      }
    }

    return InvitePreviewResult(
      codeStatus: codeStatus,
      callerStatus: callerStatus,
      inviter: inviter,
      beacon: beacon,
    );
  }

  Future<BeaconEntity?> _previewBeaconForInvite({
    required String beaconId,
    required String issuerId,
    required bool invitationExists,
    required bool invitationConsumed,
    required bool invitationExpired,
  }) async {
    BeaconEntity beacon;
    try {
      beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    } catch (_) {
      return null;
    }

    final issuerCanRead = await _guard.canReadContent(
      beaconId: beaconId,
      viewerId: issuerId,
    );
    final canPreview = BeaconVisibility.canPreviewInvite(
      BeaconInvitePreviewFacts(
        invitationExists: invitationExists,
        invitationConsumed: invitationConsumed,
        invitationExpired: invitationExpired,
        hasBeaconId: true,
        beaconStatus: beacon.status,
        beaconAllowsForward: beacon.allowsForward,
        issuerCanReadContent: issuerCanRead,
        issuerCanForward: beacon.allowsForward && issuerCanRead,
      ),
    );
    if (!canPreview) {
      return null;
    }

    return BeaconEntity(
      id: beacon.id,
      title: beacon.title,
      description: beacon.description,
      author: beacon.author,
      createdAt: beacon.createdAt,
      updatedAt: beacon.updatedAt,
      status: beacon.status,
    );
  }

  Future<bool> accept({
    required String invitationId,
    required String userId,
  }) => _userRepository.bindMutual(
    invitationId: invitationId,
    userId: userId,
    bindFriendship: true,
  );

  Future<bool> acceptAsExisting({
    required String code,
    required String userId,
  }) async {
    final invitation = await _invitationRepository.getById(invitationId: code);
    if (invitation == null) {
      throw IdNotFoundException(id: code);
    }
    if (invitation.issuer.id == userId) {
      throw const InvitationWrongException(
        description: 'Cannot accept your own invite',
      );
    }
    if (await _friendshipLookup.isReciprocalSubscribe(
      viewerId: userId,
      peerId: invitation.issuer.id,
    )) {
      if (invitation.beaconId != null &&
          !invitation.isAccepted &&
          !invitation.isExpired) {
        return _acceptBeaconInviteOnly(invitation: invitation, userId: userId);
      }
      return true;
    }
    if (invitation.isAccepted || invitation.isExpired) {
      throw IdNotFoundException(id: code);
    }

    if (invitation.beaconId != null) {
      return _acceptBeaconInviteOnly(invitation: invitation, userId: userId);
    }

    return accept(invitationId: code, userId: userId);
  }

  Future<bool> _acceptBeaconInviteOnly({
    required InvitationEntity invitation,
    required String userId,
  }) async {
    final beaconId = invitation.beaconId!;
    if (!await _guard.canReadContent(
      beaconId: beaconId,
      viewerId: invitation.issuer.id,
    )) {
      throw IdNotFoundException(id: invitation.id);
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsForward ||
        beacon.status == BeaconStatus.draft ||
        beacon.status == BeaconStatus.deleted) {
      throw IdNotFoundException(id: invitation.id);
    }

    return _userRepository.bindMutual(
      invitationId: invitation.id,
      userId: userId,
      bindFriendship: false,
    );
  }

  Future<bool> delete({
    required String invitationId,
    required String userId,
  }) => _invitationRepository.deleteById(
    invitationId: invitationId,
    userId: userId,
  );
}
