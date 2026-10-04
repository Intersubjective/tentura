import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/beacon_visibility.dart';
import 'package:tentura_server/domain/coordination/resolve_forward_parent_edge.dart';
import 'package:tentura_server/domain/policy/beacon_forward_policy.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invite_accepted_notification_intent.dart';
import 'package:tentura_server/domain/entity/invite_preview_result.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

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
    this._forwardEdgeRepository,
    this._userBlockRepository, {
    PostLockPort? postLock,
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _postLock = postLock,
       _attentionIntents = attentionIntents,
       _attention = attention;

  final InvitationRepositoryPort _invitationRepository;

  final UserRepositoryPort _userRepository;

  final BeaconRepositoryPort _beaconRepository;

  final VoteUserFriendshipLookupPort _friendshipLookup;

  final UserContactRepositoryPort _contactRepository;

  final BeaconAccessGuard _guard;

  final ForwardEdgeRepositoryPort _forwardEdgeRepository;

  final UserBlockRepositoryPort _userBlockRepository;

  final PostLockPort? _postLock;

  final AttentionIntentCase? _attentionIntents;

  final TransactionalAttentionCase? _attention;

  Future<InvitationEntity> create({
    required String userId,
    required String addresseeName,
    String? beaconId,
  }) async {
    if (beaconId == null) {
      return _invitationRepository.create(
        issuerId: userId,
        addresseeName: ContactCase.normalizeOptionalName(addresseeName),
      );
    }
    if (!await _guard.canReadContent(beaconId: beaconId, viewerId: userId)) {
      throw const UnauthorizedException(
        description: 'Issuer cannot read request content',
      );
    }

    Future<InvitationEntity> createForBeacon(BeaconEntity beacon) async {
      if (!beacon.allowsForward) {
        throw const UnauthorizedException(
          description: 'Request does not allow forwarding',
        );
      }
      if (!BeaconForwardPolicy.canForward(beacon: beacon, senderId: userId)) {
        throw const UnauthorizedException(
          description: 'Forwarding is off for this post',
        );
      }
      final inbound = await _forwardEdgeRepository.fetchActiveInboundEdges(
        beaconId: beaconId,
        recipientId: userId,
      );
      return _invitationRepository.create(
        issuerId: userId,
        addresseeName: ContactCase.normalizeOptionalName(addresseeName),
        beaconId: beaconId,
        parentForwardEdgeId: resolveForwardParentEdgeId(
          clientParentEdgeId: null,
          activeInboundEdges: inbound,
          senderId: userId,
          authorId: beacon.author.id,
        ),
      );
    }

    final firstRead = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (firstRead.kind != BeaconKind.post) return createForBeacon(firstRead);
    return _attention!.runAction(
      actorUserId: userId,
      action: (_) async =>
          createForBeacon(await _beaconUnderPostLock(beaconId)),
    );
  }

  /// Reads the beacon; for a Post takes the Post lock first and re-reads, so
  /// everything the caller checks afterwards is judged under the lock. Must
  /// run inside the caller's transaction.
  Future<BeaconEntity> _beaconUnderPostLock(String beaconId) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.kind != BeaconKind.post) return beacon;
    await _postLock!.lockForPostMutation(beaconId);
    return _beaconRepository.getBeaconById(beaconId: beaconId);
  }

  /// The invite's issuer must still be allowed to forward its beacon.
  Future<void> _requireIssuerCanForward(InvitationEntity invitation) async {
    final beacon = await _beaconUnderPostLock(invitation.beaconId!);
    _requireBeaconInviteForward(invitation: invitation, beacon: beacon);
  }

  void _requireBeaconInviteForward({
    required InvitationEntity invitation,
    required BeaconEntity beacon,
  }) {
    if (!beacon.allowsForward) {
      throw IdNotFoundException(id: invitation.id);
    }
    if (!BeaconForwardPolicy.canForward(
      beacon: beacon,
      senderId: invitation.issuer.id,
    )) {
      throw const UnauthorizedException(
        description: 'Forwarding is off for this post',
      );
    }
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
  }) async {
    final invitation = await _invitationRepository.getById(
      invitationId: invitationId,
    );
    if (invitation == null) {
      throw IdNotFoundException(id: invitationId);
    }
    if (await _userBlockRepository.isBlockedPair(
      a: userId,
      b: invitation.issuer.id,
    )) {
      throw IdNotFoundException(id: invitationId);
    }
    return _acceptAndRecord(
      invitation: invitation,
      userId: userId,
      emitMutualConnection: true,
      mutation: () async {
        if (invitation.beaconId != null) {
          await _requireIssuerCanForward(invitation);
        }
        return _userRepository.bindMutual(
          invitationId: invitationId,
          userId: userId,
          bindFriendship: true,
        );
      },
    );
  }

  Future<bool> acceptAsExisting({
    required String code,
    required String userId,
  }) async {
    final invitation = await _invitationRepository.getById(invitationId: code);
    if (invitation == null) {
      throw IdNotFoundException(id: code);
    }
    if (await _userBlockRepository.isBlockedPair(
      a: userId,
      b: invitation.issuer.id,
    )) {
      throw IdNotFoundException(id: code);
    }
    if (invitation.issuer.id == userId) {
      throw const InvitationWrongException(
        description: 'Cannot accept your own invite',
      );
    }
    if (invitation.beaconId != null &&
        (invitation.isAccepted || invitation.isExpired)) {
      throw IdNotFoundException(id: code);
    }
    if (await _friendshipLookup.isReciprocalSubscribe(
      viewerId: userId,
      peerId: invitation.issuer.id,
    )) {
      if (invitation.beaconId != null) {
        return _acceptAndRecord(
          invitation: invitation,
          userId: userId,
          emitInviteAccepted: false,
          mutation: () => _acceptBeaconInviteOnly(
            invitation: invitation,
            userId: userId,
          ),
        );
      }
      return true;
    }
    if (invitation.isAccepted || invitation.isExpired) {
      throw IdNotFoundException(id: code);
    }

    if (invitation.beaconId != null) {
      return _acceptAndRecord(
        invitation: invitation,
        userId: userId,
        emitInviteAccepted: false,
        mutation: () => _acceptBeaconInviteOnly(
          invitation: invitation,
          userId: userId,
        ),
      );
    }

    return accept(invitationId: code, userId: userId);
  }

  Future<bool> _acceptAndRecord({
    required InvitationEntity invitation,
    required String userId,
    required Future<bool> Function() mutation,
    bool emitMutualConnection = false,
    bool emitInviteAccepted = true,
  }) => _attention!.runAction(
    actorUserId: userId,
    action: (transaction) async {
      final accepted = await mutation();
      if (accepted) {
        if (emitInviteAccepted) {
          final accepter = await _userRepository.getById(userId);
          await transaction.record(
            await _attentionIntents!.inviteAccepted(
              notification: InviteAcceptedNotificationIntent(
                inviterUserId: invitation.issuer.id,
                accepterUserId: userId,
                accepterDisplayName: accepter.displayName,
                actionUrl: '/#/profile/view/$userId',
                inviteOrigin: 'existing_account',
                accepterHandle: accepter.handle,
              ),
              sourceEventKey: 'invitation:${invitation.id}:accepted',
            ),
          );
        }
        if (emitMutualConnection) {
          await transaction.record(
            await _attentionIntents!.mutualConnectionFormed(
              actorUserId: invitation.issuer.id,
              counterpartUserId: userId,
              sourceEventKey: 'invitation:${invitation.id}:mutual',
            ),
          );
        }
      }
      return accepted;
    },
  );

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
    final beacon = await _beaconUnderPostLock(beaconId);
    if (await _userBlockRepository.isBlockedPair(
          a: userId,
          b: invitation.issuer.id,
        ) ||
        !beacon.allowsForward ||
        beacon.status == BeaconStatus.draft ||
        beacon.status == BeaconStatus.deleted) {
      throw IdNotFoundException(id: invitation.id);
    }
    _requireBeaconInviteForward(invitation: invitation, beacon: beacon);

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
